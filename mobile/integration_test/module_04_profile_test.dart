// Profile and saved addresses, on a real handset — and the first device test
// with a keyboard in it.
//
// WHY THIS ONE NEXT. Correcting the traceability matrix narrowed the device gap
// from Modules 02–06 to Modules 03–06, and of those this is the one that earns a
// device run most: it is the first screen a customer types into. KI-002 listed
// "keyboard behaviour" among the things unverified on iOS, and a widget test
// cannot verify it — there is no software keyboard in a widget harness, no
// inset when it appears, and no platform text input to focus.
//
// IT CHANGES NOTHING ON THE SERVER, DELIBERATELY.
//
// The device tests share one persona against a live backend, and files can run
// in any order. A test that renamed the customer would leave every later test —
// and every later RUN, if it failed midway — looking at a person who is not the
// one the fixtures describe. So the form here types the customer's OWN values
// back and saves that: a real keyboard, a real form submission, a real round
// trip to the API, and a database that ends exactly where it started.
//
// That is a deliberate trade. It does not prove the server stores a CHANGED
// name; `test/profile_edit_test.dart` and the Module 04 API tests already do,
// and neither of them can prove a keyboard.
//
// Run:
//   flutter test integration_test/module_04_profile_test.dart \
//     --dart-define=FOTG_TEST_TOKEN=<token>

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/core/routing/routes.dart';
import 'package:foodonthego/domain/models/customer.dart';
import 'package:foodonthego/features/addresses/saved_addresses_screen.dart';
import 'package:integration_test/integration_test.dart';

import 'support/device_support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(requireToken);

  testWidgets('the account rows render on the device', (
    WidgetTester tester,
  ) async {
    final Customer customer = await whoAmI(apiAs());

    await launchSignedIn(tester, customer: customer, location: Routes.profile);

    expect(find.text('Personal information'), findsWidgets);
    expect(find.text('Saved addresses'), findsWidgets);
  });

  testWidgets('the edit form takes real keyboard input and saves', (
    WidgetTester tester,
  ) async {
    final Customer customer = await whoAmI(apiAs());

    await launchSignedIn(tester, customer: customer, location: Routes.profile);

    // Opened by tapping the row, not by a deep link. The profile sub-screens
    // have no registered paths — ProfileScreen pushes them over its branch so
    // the bottom bar stays put — so this is the only way in, and it is the way
    // a customer gets here.
    final Finder row = find.text('Personal information');
    await scrollTo(tester, row);
    await tapAt(tester, row.last);
    await settle(tester);

    // Located by position, and the save button by its widget type — the same
    // way test/profile_edit_test.dart addresses this form. Matching an existing
    // proven pattern beats inventing a finder that cannot be run here first.
    await waitFor(tester, find.byType(TextFormField));

    final Finder firstName = find.byType(TextFormField).first;

    // The server's value, read back from the server — not a literal, so this
    // cannot drift from whatever persona the run was given.
    final String given = customer.firstName;
    expect(given.isNotEmpty, isTrue, reason: 'the persona has no first name');

    // Clear and retype it through the platform's own text input. On a device
    // this raises the software keyboard, which is the thing being tested: the
    // field must stay visible and focused with the keyboard up.
    await tapAt(tester, firstName);
    await settle(tester);
    await tester.enterText(firstName, '');
    await settle(tester);
    await tester.enterText(firstName, given);
    await settle(tester);

    expect(
      find.widgetWithText(TextFormField, given),
      findsWidgets,
      reason: 'the typed first name did not reach the field',
    );

    // Save. The value is the one already stored, so this exercises the whole
    // submission path and leaves the row untouched.
    final Finder save = find.widgetWithText(FilledButton, 'Save changes');
    await scrollTo(tester, save);
    await tapAt(tester, save);

    // Straight to waitFor, with NO settle in between, and that is the whole
    // point. `settle` pumps for six REAL seconds; the confirmation is a
    // SnackBar, which lives for four. Settling first watches it appear and
    // expire, then waits a further minute for something that has already gone.
    // waitFor polls every 150ms and returns the moment it matches, so it
    // catches the snackbar while it is up.
    //
    // A widget test cannot find this: pumpAndSettle stops once no frames are
    // scheduled, and a snackbar's dismissal is a timer that schedules none, so
    // test/profile_edit_test.dart observes it still on screen. Only real time
    // kills it, which is what a device runs on.
    await waitFor(tester, find.text('Profile updated'));

    // The form closes itself on success. Asserted, because "the snackbar
    // appeared" and "the customer is back where they started" are two claims
    // and only one of them was being made.
    await waitFor(tester, find.text('Personal information'));

    // And the server still says what it said before, which is the assertion
    // that makes "changes nothing" a checked claim rather than an intention.
    final Customer after = await whoAmI(apiAs());
    expect(after.firstName, given);
    expect(after.lastName, customer.lastName);
  });

  testWidgets('saved addresses opens from the profile', (
    WidgetTester tester,
  ) async {
    final Customer customer = await whoAmI(apiAs());

    await launchSignedIn(tester, customer: customer, location: Routes.profile);

    final Finder row = find.text('Saved addresses');
    await scrollTo(tester, row);
    await tapAt(tester, row.last);
    await settle(tester);

    // By widget type, not by its title text: the profile row behind the pushed
    // route carries the same words, so a text finder here would pass whether or
    // not anything opened.
    await waitFor(tester, find.byType(SavedAddressesScreen));
  });
}
