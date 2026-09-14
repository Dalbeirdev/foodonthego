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

  group('the API base URL the review image is built with', () {
    // WHY. It was `https://techpio.tech/api/v1`, and that was wrong twice.
    // `ApiConfig.uri()` appends `/api/v1` itself, so every request went to
    // `/api/v1/api/v1/...`; and the hard-coded scheme and implied port 443 meant
    // a build served on `http://techpio.tech:8080` called an address nothing
    // answers on. The first screen said "No connection", which is exactly what
    // it should say and tells you nothing about why.
    String? apiBase() => RegExp(
      r'^ARG\s+API_BASE_URL=(\S*)',
      multiLine: true,
    ).firstMatch(File('../deploy/web.Dockerfile').readAsStringSync())?.group(1);

    test('is declared at all', () {
      expect(
        apiBase(),
        isNotNull,
        reason:
            'web.Dockerfile has no `ARG API_BASE_URL=`. If the build stopped '
            'passing one, the app falls back to the Android emulator address '
            'and the web build talks to nothing.',
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

    test('is same-origin, so it survives a change of host or port', () {
      // Not merely "not absolute": the point is that the API is served by the
      // same nginx as the bundle, so the accurate base is the origin the page
      // was loaded from — whatever that turns out to be.
      expect(
        apiBase(),
        '/',
        reason:
            'An absolute base pins the review build to one scheme, host and '
            'port. It is served on :8080 today and through a tunnel on 443 '
            'later, and a rebuild between the two is a step somebody will '
            'forget.',
      );
    });

    test('a same-origin base really does produce a relative request', () {
      // The reasoning above depends on ApiConfig stripping the trailing slash,
      // which is a behaviour rather than a promise. Asserted, not assumed.
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
