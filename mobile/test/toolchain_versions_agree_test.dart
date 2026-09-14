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

void main() {
  final File workflow = File('../.github/workflows/ci.yml');

  test('the files this test reads are where it thinks they are', () {
    // A missing file read as an empty string would make every assertion below
    // pass over nothing at all.
    expect(
      workflow.existsSync(),
      isTrue,
      reason: '${workflow.path} is missing',
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

  /*
   * The Dockerfile half of this file is gone, and deliberately not replaced
   * with nothing.
   *
   * deploy/web.Dockerfile used to build the customer app with Flutter for the
   * web, so it pinned and checksummed its own copy of the SDK and this file
   * checked that pin against CI's. Restart Module 02 replaced that build with a
   * React application, so the Dockerfile installs no Flutter at all and there
   * is no second pin to disagree with.
   *
   * What remains worth guarding is that CI names exactly one version — asserted
   * above. Flutter still builds Android and iOS, and two workflow jobs drifting
   * apart would mean the tested app and the shipped app were compiled by
   * different toolchains, which is the same failure this file was written for.
   *
   * If a Flutter build ever returns to a Dockerfile, restore the archive
   * checksum assertions with it: downloading the SDK instead of pulling an
   * image is only safer while the bytes are actually checked.
   */
}
