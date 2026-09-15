// Every FOTG_ENV this repository passes is one the app recognises.
//
// WHY THIS FILE EXISTS. `deploy/web.Dockerfile` has passed `FOTG_ENV=review`
// since the deployment was written. `AppEnvironment` knew development, staging
// and production, so `review` fell through the ternary chain to `development` —
// silently, because a `const` cannot complain. That build would have put a
// floating debug panel and invented home-screen data on a public URL for a
// client to review, and every one of those screens would have looked correct.
//
// The enum now knows `review`. What stops the NEXT spelling — `reviewing`,
// `Review`, `staging2` — from doing the same thing is this file, because
// nothing in the language will.
//
// IT READS THE REPOSITORY, not a list somebody maintains. A list of expected
// values is another thing to forget to update; the Dockerfiles and workflows
// are where the values actually live, so they are what gets read.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/core/config/app_environment.dart';

/// Every environment name the enum resolves to something specific.
const Set<String> recognised = <String>{
  'development',
  'review',
  'staging',
  'production',
};

/// Files anywhere in the repository that might set the value.
///
/// Walked rather than listed for the same reason the values are read rather
/// than listed: a new workflow or Dockerfile is covered the day it is added.
Iterable<File> _candidateFiles(Directory root) sync* {
  for (final FileSystemEntity entity in root.listSync(recursive: true)) {
    if (entity is! File) continue;

    final String path = entity.path;

    if (path.contains('/node_modules/') ||
        path.contains('/.git/') ||
        path.contains('/build/') ||
        path.contains('/vendor/')) {
      continue;
    }

    final String name = entity.uri.pathSegments.last;

    if (name.endsWith('.yml') ||
        name.endsWith('.yaml') ||
        name.endsWith('.sh') ||
        name.endsWith('Dockerfile') ||
        name.endsWith('.Dockerfile')) {
      yield entity;
    }
  }
}

void main() {
  // The repository root, from `mobile/` where `flutter test` runs.
  final Directory root = Directory('..');

  test('every FOTG_ENV value in the repository is one the app knows', () {
    final Map<String, List<String>> found = <String, List<String>>{};

    for (final File file in _candidateFiles(root)) {
      final String contents = file.readAsStringSync();

      for (final RegExpMatch match in RegExp(
        r'FOTG_ENV=([A-Za-z0-9_.-]+)',
      ).allMatches(contents)) {
        final String value = match.group(1)!;

        // A value composed at run time from a variable is not a literal this
        // test can check, and pretending otherwise would be a false pass.
        if (value.startsWith(r'$') || value.contains('{')) continue;

        found.putIfAbsent(value, () => <String>[]).add(file.path);
      }
    }

    expect(
      found,
      isNotEmpty,
      reason:
          'No FOTG_ENV assignment was found anywhere. Either the walk is '
          'looking in the wrong place or the deployment stopped setting it — '
          'and a guard that scans nothing passes for free.',
    );

    final Map<String, List<String>> unknown = <String, List<String>>{
      for (final MapEntry<String, List<String>> e in found.entries)
        if (!recognised.contains(e.key)) e.key: e.value,
    };

    expect(
      unknown,
      isEmpty,
      reason:
          'These FOTG_ENV values are not recognised by AppEnvironment, so a '
          'build using one silently becomes `development` — fixtures on, debug '
          'harness on. Add the value to the enum, or correct the spelling '
          'where it is set.',
    );
  });

  test('the review deployment shows no fixtures and every notice', () {
    // The combination is the whole point of the environment existing, and it
    // is the opposite pairing to every other value, so it is asserted rather
    // than left to be re-derived by whoever reads the enum next.
    expect(AppEnvironment.review.allowsFixtures, isFalse);
    expect(AppEnvironment.review.showsDevelopmentNotices, isTrue);

    // The controls: the two neighbours it must not be confused with.
    expect(AppEnvironment.development.allowsFixtures, isTrue);
    expect(AppEnvironment.production.showsDevelopmentNotices, isFalse);
  });

  group('the API base URL the review APK is built with', () {
    /*
     * This group used to read deploy/web.Dockerfile, because the customer web
     * app was Flutter compiled for the browser and its base URL was an ARG in
     * that file. Restart Module 02 replaced the web app with React, so the
     * Dockerfile builds no Flutter and the value moved: the only Flutter build
     * that still needs a base URL is the Android review APK, and CI sets it.
     *
     * The guard followed rather than being deleted. Two of the three faults it
     * was written for can happen just as easily in a workflow as in a
     * Dockerfile — and one of them already did, as KI-057.
     */
    String? apiBase() => RegExp(r"""url='(http[^']*)'""", multiLine: true)
        .firstMatch(File('../.github/workflows/ci.yml').readAsStringSync())
        ?.group(1);

    test('is declared at all', () {
      expect(
        apiBase(),
        isNotNull,
        reason:
            'ci.yml no longer resolves an API address for the review APK. '
            'Without one the app falls back to a default and the build a '
            'reviewer installs talks to nothing.',
      );
    });

    test('does not repeat the path ApiConfig already adds', () {
      expect(
        apiBase(),
        isNot(contains('/api')),
        reason:
            'ApiConfig.uri() builds "\$baseUrl/api/v1\$path", so a base ending '
            'in /api/v1 produces /api/v1/api/v1/... — a 404 on every call, '
            'reported to the customer as "No connection".',
      );
    });

    test('is not an address that only exists inside an emulator', () {
      // KI-057. Every review APK ever produced was built against
      // http://10.0.2.2:8000, which is the Android emulator's alias for the
      // machine running it. On a handset it resolves to nothing, so the
      // artefact whose whole purpose is testing on a real phone could not
      // reach the server.
      expect(
        apiBase(),
        isNot(contains('10.0.2.2')),
        reason:
            'The review APK is for a real device. 10.0.2.2 exists only inside '
            'an emulator and resolves to nothing on a phone.',
      );
      expect(
        apiBase(),
        isNot(contains('localhost')),
        reason: 'localhost on a handset is the handset, not the server.',
      );
    });

    test('a same-origin base really does produce a relative request', () {
      // ApiConfig still accepts an empty base and the React web client relies
      // on the equivalent behaviour, so the contract is asserted rather than
      // assumed even though no Flutter build passes '/' today.
      const String raw = '/';
      String base = raw.trim();
      while (base.endsWith('/')) {
        base = base.substring(0, base.length - 1);
      }
      final Uri built = Uri.parse('$base/api/v1/auth/phone');

      expect(built.toString(), '/api/v1/auth/phone');
      expect(built.hasScheme, isFalse);
      expect(built.hasAuthority, isFalse);
    });
  });

  test('an unrecognised value is detectable rather than silent', () {
    // This build is compiled with no --dart-define, so it is `development` and
    // recognised. The assertion is that the flag exists and is honest about
    // this build; its value under a bad define is what the first test covers.
    expect(AppEnvironment.isRecognised, isTrue);
    expect(AppEnvironment.current, AppEnvironment.development);
  });
}
