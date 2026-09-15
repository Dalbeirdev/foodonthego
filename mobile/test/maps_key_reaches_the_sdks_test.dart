// A Maps key supplied at build time reaches the native SDKs that need it.
//
// WHY THIS FILE EXISTS. `MapsConfig.canRenderMap` turns the map on when
// `FOTG_MAPS_API_KEY` is defined — and until Restart Module 06 that was the only
// place the key went. The Android Maps SDK reads its key from a manifest
// meta-data element; the iOS SDK requires `GMSServices.provideAPIKey` before the
// first map view. Neither existed. A --dart-define reaches neither of them.
//
// So the app was arranged to switch its map on the day a key arrived, and both
// native SDKs were arranged to have nothing to authenticate with. Android would
// have rendered a blank grey map with an authorization failure in logcat; iOS
// would have thrown. Nothing would have caught it here: there is no key in this
// repository, so `canRenderMap` is false, the map is never attempted, and every
// test passes.
//
// That is the shape of defect this project keeps finding — correct-looking code
// whose failure is scheduled for a day nobody is testing. This file reads the
// build files themselves rather than a list somebody maintains, because the
// build files are where the wiring actually lives.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/core/config/maps_config.dart';

File _file(String path) {
  final file = File(path);
  expect(
    file.existsSync(),
    isTrue,
    reason: '$path is missing; the map cannot be configured without it.',
  );
  return file;
}

void main() {
  /*
   * This came second, and it is the one that would have caught the mistake the
   * others did not.
   *
   * The original version of this file read both files as strings and searched
   * them for substrings. That passes on a file Android cannot parse — and it
   * did: the comment explaining the Android key contained a Dart define flag
   * written with its leading dashes, and **XML forbids a double hyphen inside a
   * comment**. `flutter test`, `flutter analyze` and `dart format` all passed,
   * because none of them parses XML. CI's `assembleDebug` failed with
   * "Error parsing AndroidManifest.xml" three minutes into an Android build
   * this environment cannot run.
   *
   * The first attempt at a fix was to parse both files with the `xml` package.
   * That check could not fail: reintroducing the exact double hyphen left it
   * green, because that parser is more lenient than Android's manifest merger.
   * A control is the only reason that was noticed instead of shipped, and the
   * dependency was removed again rather than left in looking useful.
   *
   * So this checks the rule that actually broke, lexically and exactly.
   */
  group('the XML files Android and iOS parse', () {
    for (final path in const [
      'android/app/src/main/AndroidManifest.xml',
      'ios/Runner/Info.plist',
    ]) {
      test('$path has no double hyphen inside a comment', () {
        final source = _file(path).readAsStringSync();
        final comments = RegExp(
          r'<!--(.*?)-->',
          dotAll: true,
        ).allMatches(source);

        expect(
          comments,
          isNotEmpty,
          reason:
              'If this file has no comments the check below proves '
              'nothing, and something has gone wrong with the extraction.',
        );

        for (final comment in comments) {
          final body = comment.group(1)!;

          expect(
            body.contains('--'),
            isFalse,
            reason:
                'XML forbids "--" inside a comment, and Android\'s manifest '
                'merger enforces it. Write flag names without their leading '
                'dashes, or put them in the documentation instead.\n'
                'Offending comment: ${body.trim()}',
          );
        }
      });
    }
  });

  group('the Android Maps key', () {
    test('has a manifest element for the SDK to read', () {
      final manifest = _file('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();

      expect(
        manifest,
        contains('com.google.android.geo.API_KEY'),
        reason:
            'The Android Maps SDK reads its key from this meta-data name '
            'and from nowhere else. Without the element, a supplied key is '
            'never seen and the map renders blank.',
      );
    });

    test('takes its value from a build-time placeholder, never a literal', () {
      final manifest = _file('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();

      expect(
        manifest,
        contains(r'${mapsApiKey}'),
        reason:
            'The value must be a manifest placeholder so the key is '
            'supplied at build time.',
      );

      // A committed key is a published key: the APK is a zip anybody can open.
      expect(
        RegExp(r'android:value="AIza').hasMatch(manifest),
        isFalse,
        reason: 'A Google API key literal must never be committed.',
      );
    });

    test('has a Gradle placeholder that can be fed without editing a file', () {
      final gradle = _file('android/app/build.gradle.kts').readAsStringSync();

      expect(gradle, contains('manifestPlaceholders'));
      expect(gradle, contains('mapsApiKey'));
      expect(
        gradle,
        contains('FOTG_MAPS_API_KEY'),
        reason:
            'The same name the Dart define uses, so one value drives both '
            'halves and they cannot disagree.',
      );
    });
  });

  group('the iOS Maps key', () {
    test('is provided to the SDK before any map view exists', () {
      final delegate = _file('ios/Runner/AppDelegate.swift').readAsStringSync();

      expect(
        delegate,
        contains('GMSServices.provideAPIKey'),
        reason:
            'The iOS Maps SDK offers no other way in, and requires this '
            'before the first GMSMapView.',
      );

      expect(
        delegate,
        contains('didFinishLaunchingWithOptions'),
        reason: 'It has to happen at launch, not lazily from a widget.',
      );
    });

    test('reads the key from Info.plist rather than a literal', () {
      final delegate = _file('ios/Runner/AppDelegate.swift').readAsStringSync();
      final plist = _file('ios/Runner/Info.plist').readAsStringSync();

      expect(delegate, contains('GMSApiKey'));
      expect(plist, contains('<key>GMSApiKey</key>'));
      expect(
        plist,
        contains(r'$(GMS_API_KEY)'),
        reason: 'A build setting, so the value is supplied at build time.',
      );
      expect(
        delegate.contains('AIza'),
        isFalse,
        reason: 'A Google API key literal must never be committed.',
      );
    });

    test('does not hand the SDK an empty key', () {
      final delegate = _file('ios/Runner/AppDelegate.swift').readAsStringSync();

      // Providing "" is not the same as not providing one: the SDK throws on an
      // empty key, which turns "no map configured" into a crash at launch.
      expect(
        delegate.contains('isEmpty'),
        isTrue,
        reason: 'An empty key must be treated as no key.',
      );
    });
  });

  group('MapsConfig', () {
    test('will not attempt a map without a key', () {
      // True of this repository as it stands: no key exists (MF-08), so the
      // route screen renders its map-unavailable state rather than a blank one.
      expect(MapsConfig.hasKey, isFalse);
      expect(MapsConfig.canRenderMap, isFalse);
    });
  });
}
