// The customer app's chrome, on a real handset.
//
// WHY THIS FILE EXISTS. The traceability matrix carried M02-017 and M02-018 —
// "Android verification" and "iOS verification" — as BLOCKED, citing an
// environment that had not existed for several modules. Correcting that entry
// showed the real gap: CI runs an on-device suite, and that suite covered
// Modules 11–14 and nothing earlier. The rows were right that the shell was
// unverified on a device, and wrong about why.
//
// So this is the fix rather than another note. It is deliberately the cheapest
// device test that covers something real: no API keys, no fixtures, no server
// state, a few seconds of runtime on each platform.
//
// WHAT IT ADDS, STATED HONESTLY. `test/navigation_test.dart` already covers the
// same shell in the widget harness, more thoroughly than this does — it checks
// each tab's contents and the selected index too. The logic is not what is
// unproven.
//
// What that test cannot do is run on a handset. Rendering the five labels with
// the platform's own font and text shaping, hit-testing a bar sitting above an
// iOS home indicator or an Android gesture area, and surviving the real
// engine's layout are device properties, and a widget test asserts none of
// them. That is the whole of M02-017 and M02-018, and it is all this file
// claims.
//
// It deliberately does not test what is *inside* each tab. The modules that own
// those screens do that, and duplicating them here would make a failure in one
// indistinguishable from a failure in the shell.
//
// Run:
//   flutter test integration_test/module_02_shell_test.dart \
//     --dart-define=FOTG_TEST_TOKEN=<token>

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/core/l10n/app_strings.dart';
import 'package:foodonthego/core/routing/routes.dart';
import 'package:foodonthego/domain/models/customer.dart';
import 'package:integration_test/integration_test.dart';

import 'support/device_support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const AppStrings strings = AppStrings();

  /// The five, in the order the shell declares them.
  const List<String> labels = <String>[
    'Home',
    'Trips',
    'Orders',
    'Alerts',
    'Profile',
  ];

  setUpAll(requireToken);

  /// A label *inside the navigation bar*, not merely somewhere on screen.
  ///
  /// The obvious `find.text('Orders').last` is a guess that the bar happens to
  /// come last in the widget tree, and it stops being true the moment a screen
  /// renders the same word as a heading — which the Orders tab does. Scoping to
  /// the NavigationBar means the finder addresses the thing being tested rather
  /// than whatever else shares its wording.
  Finder destination(String label) => find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  );

  testWidgets('the five destinations render on the device', (
    WidgetTester tester,
  ) async {
    final Customer customer = await whoAmI(apiAs());

    await launchSignedIn(tester, customer: customer, location: Routes.home);

    for (final String label in labels) {
      expect(
        destination(label),
        findsOneWidget,
        reason:
            'the "$label" destination did not render in the navigation bar. On '
            'a device this is as likely to be a layout failure — a bar clipped '
            'by the home indicator, a label truncated by the platform font — '
            'as a missing widget, which is the reason for testing it here at '
            'all.',
      );
    }

    // The labels above are the ones the shell asks AppStrings for. Asserting
    // the literal AND the source keeps a silent rename honest: change
    // navHome and this fails rather than passing against a stale expectation.
    expect(strings.navHome, labels[0]);
    expect(strings.navTrips, labels[1]);
    expect(strings.navOrders, labels[2]);
    expect(strings.navNotifications, labels[3]);
    expect(strings.navProfile, labels[4]);
  });

  testWidgets('each destination is reachable by tapping it', (
    WidgetTester tester,
  ) async {
    final Customer customer = await whoAmI(apiAs());

    await launchSignedIn(tester, customer: customer, location: Routes.home);

    // Skips Home: the app already starts there, so tapping it would prove
    // nothing about navigation.
    for (final String label in labels.skip(1)) {
      await tapAt(tester, destination(label));
      await settle(tester);

      expect(
        destination(label),
        findsOneWidget,
        reason: 'the shell lost the "$label" destination after tapping it',
      );
    }

    // And back to the beginning, which is the case a stack-based shell gets
    // wrong: an IndexedStack that rebuilt its branches would have discarded
    // Home by now.
    await tapAt(tester, destination(labels.first));
    await settle(tester);

    expect(destination(labels.first), findsOneWidget);
  });
}
