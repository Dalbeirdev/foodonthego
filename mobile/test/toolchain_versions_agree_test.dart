// The review build is made with the toolchain the tests were run on.
//
// WHY THIS FILE EXISTS. `deploy/web.Dockerfile` said, in a comment, "the same
// Flutter version CI pins. A review build produced by a different toolchain than
// the tested one is not the tested app." The claim was true and nothing checked
// it — and the line it described, `FROM ghcr.io/cirruslabs/flutter:3.47.2`,
// pointed at a tag that does not exist. The build died with "failed to resolve
// source metadata … not found" the first time it was ever run, twenty minutes
// into a deploy.
//
// The repair — installing the pinned SDK from Google's own archive — removes the
// dependency on somebody else's tag. What it does not remove is the drift this
// comment was worried about: CI bumps to a new Flutter, the Dockerfile keeps the
// old one, and the review site is quietly built with a toolchain no test has
// ever used. This asserts the two agree, and fails naming both.
//
// A NOTE ON WHY THE PRESSURE IS REAL. When a pinned base image disappears, the
// quickest repair is to slacken the pin — `:stable`, `:latest`, whatever
// resolves — and that is precisely the thing the original comment forbade. A
// test makes the slack version fail rather than ship.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The version in every `flutter-version:` line of the CI workflow.
Set<String> _ciPins(String workflow) =>
    RegExp(r"flutter-version:\s*'([^']+)'")
        .allMatches(workflow)
        .map((RegExpMatch m) => m.group(1)!)
        .toSet();

/// The default of the Dockerfile's `FLUTTER_VERSION` build argument.
String? _dockerPin(String dockerfile) => RegExp(
  r'^ARG\s+FLUTTER_VERSION=(\S+)',
  multiLine: true,
).firstMatch(dockerfile)?.group(1);

void main() {
  final File workflow = File('../.github/workflows/ci.yml');
  final File dockerfile = File('../deploy/web.Dockerfile');

  test('the files this test reads are where it thinks they are', () {
    // A missing file read as an empty string would make every assertion below
    // pass over nothing at all.
    expect(
      workflow.existsSync(),
      isTrue,
      reason: '${workflow.path} is missing',
    );
    expect(
      dockerfile.existsSync(),
      isTrue,
      reason: '${dockerfile.path} is missing',
    );
  });

  test('CI pins exactly one Flutter version across all its jobs', () {
    final Set<String> pins = _ciPins(workflow.readAsStringSync());

    expect(
      pins,
      isNotEmpty,
      reason:
          'No flutter-version: line was found in ci.yml. Either the workflow '
          'stopped pinning one — which would make every device run a different '
          'app — or this regex no longer matches how it is written.',
    );
    expect(
      pins,
      hasLength(1),
      reason:
          'CI pins more than one Flutter version: $pins. The device suites '
          'would then be testing different builds of the same commit.',
    );
  });

  test('the review image is built with the version CI tested', () {
    final String ci = _ciPins(workflow.readAsStringSync()).single;
    final String? image = _dockerPin(dockerfile.readAsStringSync());

    expect(
      image,
      isNotNull,
      reason:
          'web.Dockerfile has no `ARG FLUTTER_VERSION=`. If the Flutter stage '
          'went back to a prebuilt base image, this check no longer covers it '
          'and the comment in that file is claiming more than is enforced.',
    );
    expect(
      image,
      ci,
      reason:
          'The review site would be built with Flutter $image while the tests '
          'ran on $ci. Bring them together — and if the Dockerfile version is '
          'changed, its FLUTTER_SHA256 must change with it, because the '
          'checksum belongs to the archive rather than to the pin.',
    );
  });

  test('a pinned version carries a pinned checksum', () {
    final String source = dockerfile.readAsStringSync();

    // The point of downloading rather than pulling an image is that nobody
    // else controls the bytes. That only holds if the bytes are checked.
    expect(
      RegExp(
        r'^ARG\s+FLUTTER_SHA256=[0-9a-f]{64}$',
        multiLine: true,
      ).hasMatch(source),
      isTrue,
      reason:
          'web.Dockerfile downloads the Flutter SDK without a 64-character '
          'FLUTTER_SHA256 to check it against, so a corrupted or substituted '
          'archive would build a review app from an unknown toolchain.',
    );
    expect(
      source.contains('sha256sum -c -'),
      isTrue,
      reason:
          'FLUTTER_SHA256 is declared but never verified. A checksum nothing '
          'compares against is decoration.',
    );
  });
}
