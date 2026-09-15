import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// What the shipped app is allowed to do, as opposed to what the tests are.
///
/// Every assertion here failed on the tree that produced the review APK, and
/// the whole suite was green at the time. That is the point of the file: a
/// Flutter test exercises Dart against fakes, and never once consults the
/// manifest or the plist that decide whether the built artifact may open a
/// socket or ask for a location. The release APK had no INTERNET permission —
/// it started, rendered, and reported every request to the customer as "No
/// connection" — and the iOS build had no location usage description, which is
/// not a denied permission but an immediate termination.
///
/// These read the real files rather than a copy of their contents, so they
/// notice an edit that removes a line as readily as one that never added it.
void main() {
  final Directory mobile = _mobileRoot();

  String read(String relative) {
    final File file = File('${mobile.path}/$relative');
    expect(
      file.existsSync(),
      isTrue,
      reason:
          '$relative is missing; the build cannot be reasoned about without it.',
    );
    return file.readAsStringSync();
  }

  group('the Android release manifest', () {
    late String manifest;

    setUp(() {
      manifest = read('android/app/src/main/AndroidManifest.xml');
    });

    test('declares INTERNET, in main and not only in the debug flavour', () {
      expect(
        manifest,
        contains('android.permission.INTERNET'),
        reason:
            'Only src/debug and src/profile declared INTERNET. Debug builds and '
            'integration tests therefore worked and the release APK could not '
            'make a single request.',
      );
    });

    test('declares the location permissions geolocator will not declare for it', () {
      for (final String permission in <String>[
        'android.permission.ACCESS_FINE_LOCATION',
        'android.permission.ACCESS_COARSE_LOCATION',
      ]) {
        expect(
          manifest,
          contains(permission),
          reason:
              '$permission is declared nowhere, so the journey planner cannot '
              'find where the customer is starting from.',
        );
      }
    });

    test(
      'points at a network security config rather than trusting the default',
      () {
        expect(
          manifest,
          contains(
            'android:networkSecurityConfig="@xml/network_security_config"',
          ),
          reason:
              'Without this the cleartext policy is whatever the target API '
              'level happens to default to, which changes between versions.',
        );
      },
    );

    test('never turns on cleartext for everything', () {
      expect(
        manifest,
        isNot(contains('android:usesCleartextTraffic="true"')),
        reason:
            'That opens every host. The named exceptions in '
            'network_security_config.xml are the supported way to do this.',
      );
    });
  });

  group('the Android network security config', () {
    late String config;

    setUp(() {
      config = read('android/app/src/main/res/xml/network_security_config.xml');
    });

    test('forbids cleartext by default', () {
      expect(
        config,
        contains('<base-config cleartextTrafficPermitted="false" />'),
        reason:
            'The base config is what applies to every host not named below. '
            'If it permits cleartext, naming hosts achieves nothing.',
      );
    });

    test('permits it only for hosts named one at a time', () {
      final Iterable<RegExpMatch> domains = RegExp(
        r'<domain[^>]*>([^<]+)</domain>',
      ).allMatches(config);

      expect(
        domains,
        isNotEmpty,
        reason: 'No host is named, so nothing can be reached over HTTP.',
      );

      for (final RegExpMatch match in domains) {
        final String host = match.group(1)!.trim();
        expect(
          host,
          isNot(contains('*')),
          reason: 'A wildcard host ("$host") is not a named exception.',
        );
      }
    });
  });

  group('the iOS Info.plist', () {
    late String plist;

    setUp(() {
      plist = read('ios/Runner/Info.plist');
    });

    test(
      'explains why the app wants a location, because iOS kills it otherwise',
      () {
        expect(
          plist,
          contains('<key>NSLocationWhenInUseUsageDescription</key>'),
          reason:
              'iOS terminates an app that requests location without this key. '
              'Not a denied permission — the process ends.',
        );

        final RegExpMatch? description = RegExp(
          r'<key>NSLocationWhenInUseUsageDescription</key>\s*<string>([^<]*)</string>',
        ).firstMatch(plist);

        expect(
          description,
          isNotNull,
          reason: 'The key is present with no string after it.',
        );
        expect(
          description!.group(1)!.trim().length,
          greaterThan(20),
          reason:
              'App Review rejects a usage string that does not say what the '
              'location is used for, and so would a customer reading it.',
        );
      },
    );

    test('does not disable App Transport Security wholesale', () {
      // The <key> element, not the bare word: the first draft of this matched
      // the string anywhere in the file and failed on a comment above the ATS
      // block explaining that the key is deliberately absent. A test that
      // cannot tell a declaration from a sentence about one is not checking
      // what it claims to.
      expect(
        plist,
        isNot(contains('<key>NSAllowsArbitraryLoads</key>')),
        reason:
            'That permits cleartext to every host. The review deployment '
            'needs one domain, which NSExceptionDomains gives it.',
      );
    });
  });

  /// The two platforms keep their cleartext exceptions in different files in
  /// different formats, and a reviewer testing on one phone would not discover
  /// that the other had been missed.
  test('both platforms allow cleartext to the same review host', () {
    final RegExpMatch? androidHost =
        RegExp(r'<domain includeSubdomains="true">([^<]+)</domain>').firstMatch(
          read('android/app/src/main/res/xml/network_security_config.xml'),
        );

    expect(
      androidHost,
      isNotNull,
      reason: 'Android names no public review host.',
    );

    expect(
      read('ios/Runner/Info.plist'),
      contains('<key>${androidHost!.group(1)!.trim()}</key>'),
      reason:
          'Android permits cleartext to ${androidHost.group(1)} and iOS does '
          'not, so the same build works on one phone and not the other.',
    );
  });
}

/// Walks up from the test file to the directory holding pubspec.yaml, so the
/// suite does not depend on which directory it was started from.
Directory _mobileRoot() {
  Directory directory = Directory.current;
  for (int i = 0; i < 6; i++) {
    if (File('${directory.path}/pubspec.yaml').existsSync() &&
        Directory('${directory.path}/android').existsSync()) {
      return directory;
    }
    directory = directory.parent;
  }
  throw StateError(
    'Could not find the mobile package root from ${Directory.current.path}',
  );
}
