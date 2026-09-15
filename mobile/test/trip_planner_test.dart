import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/core/network/api_error_code.dart';
import 'package:foodonthego/core/network/api_exception.dart';
import 'package:foodonthego/domain/models/customer_summary.dart';
import 'package:foodonthego/domain/models/home_dashboard.dart';
import 'package:foodonthego/domain/models/saved_address.dart';
import 'package:foodonthego/features/addresses/saved_addresses_screen.dart';
import 'package:foodonthego/features/trips/trip_planner_screen.dart';
import 'package:foodonthego/features/trips/widgets/location_picker_sheet.dart';

import 'support/harness.dart';

/// The planner: choose two places, create a journey, stop.
///
/// A recurring assertion throughout: no screen in this module renders a
/// distance, a duration or an arrival time, because no journey has one. Several
/// of these tests exist purely to fail if somebody adds a plausible-looking
/// placeholder.
void main() {
  SavedAddress home({
    double? latitude = 28.5494,
    double? longitude = 77.2001,
  }) => SavedAddress(
    id: 'addr-home',
    type: AddressType.home,
    label: 'Home',
    addressLine1: '12 Hauz Khas',
    city: 'New Delhi',
    state: 'Delhi',
    countryCode: 'IN',
    formattedAddress: '12 Hauz Khas, New Delhi, Delhi 110016',
    latitude: latitude,
    longitude: longitude,
    isDefault: true,
  );

  Future<void> openPlanner(
    WidgetTester tester, {
    FakeTripRepository? trips,
    FakePlaceRepository? places,
    FakeLocationService? location,
    FakeCustomerRepository? customer,
  }) async {
    usePhoneSurface(tester);

    await tester.pumpWidget(
      wrapApp(
        repository: StubHomeRepository.value(
          const HomeDashboard(
            customer: CustomerSummary(fullName: 'Rahul Sharma'),
          ),
        ),
        trips: trips,
        places: places,
        location: location,
        customer: customer,
        initialLocation: '/trips/plan',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TripPlannerScreen), findsOneWidget);
  }

  /// Inside the picker sheet only.
  ///
  /// Scoped because the bottom navigation bar behind the sheet has a tab called
  /// "Home", and a saved address called Home is exactly the case this module
  /// has to get right.
  Finder inSheet(String text) => find.descendant(
    of: find.byType(LocationPickerSheet),
    matching: find.text(text),
  );

  /// Picks a saved address for whichever end the label names.
  Future<void> chooseSaved(
    WidgetTester tester,
    String slotLabel,
    String addressLabel,
  ) async {
    await tester.tap(find.text(slotLabel));
    await tester.pumpAndSettle();
    await tester.tap(inSheet(addressLabel));
    await tester.pumpAndSettle();
  }

  /// Picks the Jaipur airport suggestion for whichever end the label names.
  Future<void> searchAndChoose(
    WidgetTester tester,
    String slotLabel, {
    String query = 'jaipur',
    String expect_ = 'Jaipur International Airport',
  }) async {
    await tester.tap(find.text(slotLabel));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, query);
    // Past the debounce, then let the answer land.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    await tester.tap(find.text(expect_).last);
    await tester.pumpAndSettle();
  }

  group('choosing the two ends', () {
    testWidgets('opens with both ends empty and nothing invented', (
      WidgetTester tester,
    ) async {
      await openPlanner(tester);

      expect(find.text('Choose your starting point'), findsOneWidget);
      expect(find.text('Choose your destination'), findsOneWidget);
      // Nothing has been assumed about where the customer is.
      expect(find.textContaining('km'), findsNothing);
    });

    testWidgets('a searched place becomes the destination', (
      WidgetTester tester,
    ) async {
      final FakePlaceRepository places = FakePlaceRepository();
      await openPlanner(tester, places: places);

      await searchAndChoose(tester, 'Going to');

      expect(find.text('Jaipur International Airport'), findsOneWidget);
      expect(find.text('Choose your destination'), findsNothing);
      // The suggestion had no position; the details call is what gave it one.
      expect(places.detailsCount, 1);
    });

    testWidgets('the details call carries the search session token', (
      WidgetTester tester,
    ) async {
      final FakePlaceRepository places = FakePlaceRepository();
      await openPlanner(tester, places: places);

      await searchAndChoose(tester, 'Going to');

      final Set<String?> tokens = places.sessionTokens.toSet();
      expect(tokens.length, 1);
      expect(tokens.single, isNotNull);
    });

    testWidgets('the current location becomes the origin', (
      WidgetTester tester,
    ) async {
      await openPlanner(tester);

      await chooseSaved(tester, 'Setting off from', 'Use my current location');

      expect(find.text('Choose your starting point'), findsNothing);
    });

    testWidgets('a saved address becomes an end', (WidgetTester tester) async {
      await openPlanner(
        tester,
        customer: FakeCustomerRepository(addresses: <SavedAddress>[home()]),
      );

      await chooseSaved(tester, 'Setting off from', 'Home');

      expect(find.bySemanticsLabel('Setting off from, Home'), findsOneWidget);
    });

    testWidgets(
      'a saved address with no location is explained, not silently placed',
      (WidgetTester tester) async {
        await openPlanner(
          tester,
          customer: FakeCustomerRepository(
            addresses: <SavedAddress>[home(latitude: null, longitude: null)],
          ),
        );

        await tester.tap(find.text('Setting off from'));
        await tester.pumpAndSettle();

        expect(inSheet('No location saved'), findsOneWidget);

        await tester.tap(inSheet('Home'));
        await tester.pumpAndSettle();

        // Not chosen, and not given a plausible coordinate. The sheet stays
        // open, says why, and points at the search box.
        expect(find.textContaining('Search for it instead'), findsOneWidget);
        expect(find.byType(LocationPickerSheet), findsOneWidget);
        expect(find.text('Choose your starting point'), findsOneWidget);
      },
    );
  });

  group('managing saved addresses from the sheet', () {
    testWidgets('the link opens saved addresses rather than Page Not Found', (
      WidgetTester tester,
    ) async {
      // FOUND BY A FAILING DEVICE TEST, WHICH IS THE ONLY REASON IT WAS FOUND.
      //
      // The link captured the router, popped the sheet and called
      // `router.push('/profile/addresses')`. GoRouter does not know that path:
      // the router registers `/profile` with no children, and both the profile
      // editor and the saved-addresses screen are reached with a plain
      // Navigator push from the profile screen. So the tap navigated the
      // customer to the Page Not Found screen.
      //
      // Nothing caught it. No test touched this link, and the constant it used
      // -- Routes.savedAddressesPath -- read exactly like a route that exists.
      // That constant, and the two beside it, have since been deleted: they
      // named paths the router never registered.
      await openPlanner(
        tester,
        customer: FakeCustomerRepository(addresses: <SavedAddress>[home()]),
      );

      await tester.tap(find.text('Setting off from'));
      await tester.pumpAndSettle();

      final Finder link = inSheet('Manage saved addresses');
      await tester.ensureVisible(link);
      await tester.pumpAndSettle();
      await tester.tap(link);
      await tester.pumpAndSettle();

      expect(
        find.text('Page Not Found'),
        findsNothing,
        reason: 'the link navigated to the router error screen',
      );
      expect(find.byType(SavedAddressesScreen), findsOneWidget);

      // And back returns to the planner. Not a bonus assertion: that screen's
      // back button asks GoRouter whether anything can be popped and falls back
      // to `go('/profile')` when the answer is no, so pushing onto the wrong
      // navigator would strand the customer on the profile tab instead of the
      // journey they were part-way through planning.
      await tester.tap(find.widgetWithIcon(IconButton, Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(find.text('Setting off from'), findsOneWidget);
    });
  });

  group('swap and clear', () {
    testWidgets('swap turns the journey round', (WidgetTester tester) async {
      await openPlanner(
        tester,
        customer: FakeCustomerRepository(addresses: <SavedAddress>[home()]),
      );

      await chooseSaved(tester, 'Setting off from', 'Home');
      await searchAndChoose(tester, 'Going to');

      await tester.tap(find.byIcon(Icons.swap_vert_rounded));
      await tester.pumpAndSettle();

      // Both are still chosen; they have changed places. Asserted through the
      // rows' own semantics so this cannot pass on text that happens to appear
      // twice.
      expect(
        find.bySemanticsLabel('Setting off from, Jaipur International Airport'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Going to, Home'), findsOneWidget);
    });

    testWidgets('swap works with one end chosen', (WidgetTester tester) async {
      await openPlanner(tester);

      await searchAndChoose(tester, 'Setting off from');
      await tester.tap(find.byIcon(Icons.swap_vert_rounded));
      await tester.pumpAndSettle();

      // Somebody who typed their destination into the wrong box gets what they
      // expect rather than nothing.
      expect(
        find.bySemanticsLabel('Going to, Jaipur International Airport'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Setting off from, Choose your starting point'),
        findsOneWidget,
      );
    });

    testWidgets('clear empties one end and leaves the other', (
      WidgetTester tester,
    ) async {
      await openPlanner(
        tester,
        customer: FakeCustomerRepository(addresses: <SavedAddress>[home()]),
      );

      await chooseSaved(tester, 'Setting off from', 'Home');
      await searchAndChoose(tester, 'Going to');

      await tester.tap(find.byTooltip('Clear Setting off from'));
      await tester.pumpAndSettle();

      expect(find.text('Choose your starting point'), findsOneWidget);
      expect(find.text('Jaipur International Airport'), findsOneWidget);
    });
  });

  group('validation', () {
    testWidgets('creating with nothing chosen names the missing end', (
      WidgetTester tester,
    ) async {
      final FakeTripRepository trips = FakeTripRepository();
      await openPlanner(tester, trips: trips);

      await tester.tap(find.widgetWithText(FilledButton, 'Create journey'));
      await tester.pumpAndSettle();

      expect(
        find.text('Choose where you are setting off from.'),
        findsOneWidget,
      );
      // Nothing was sent. A round trip to be told what the screen already knew
      // is a round trip a traveller in a dead zone does not get.
      expect(trips.createCount, 0);
    });

    testWidgets('with only an origin, it names the destination', (
      WidgetTester tester,
    ) async {
      final FakeTripRepository trips = FakeTripRepository();
      await openPlanner(tester, trips: trips);

      await searchAndChoose(tester, 'Setting off from');
      await tester.tap(find.widgetWithText(FilledButton, 'Create journey'));
      await tester.pumpAndSettle();

      expect(find.text('Choose where you are going.'), findsOneWidget);
      expect(trips.createCount, 0);
    });

    testWidgets('the same place at both ends is refused before sending', (
      WidgetTester tester,
    ) async {
      final FakeTripRepository trips = FakeTripRepository();
      await openPlanner(tester, trips: trips);

      await searchAndChoose(tester, 'Setting off from');
      await searchAndChoose(tester, 'Going to');

      await tester.tap(find.widgetWithText(FilledButton, 'Create journey'));
      await tester.pumpAndSettle();

      expect(
        find.text('Choose a destination different from your starting point.'),
        findsOneWidget,
      );
      expect(trips.createCount, 0);
    });

    testWidgets('the screen says nothing until an attempt is made', (
      WidgetTester tester,
    ) async {
      await openPlanner(tester);

      // Somebody who has just arrived is not scolded for not having filled in
      // a form they have not touched.
      expect(find.text('Choose where you are setting off from.'), findsNothing);
    });
  });

  group('creating', () {
    testWidgets('sends two places and nothing else', (
      WidgetTester tester,
    ) async {
      final FakeTripRepository trips = FakeTripRepository(
        addresses: <SavedAddress>[home()],
      );
      await openPlanner(
        tester,
        trips: trips,
        customer: FakeCustomerRepository(addresses: <SavedAddress>[home()]),
      );

      await chooseSaved(tester, 'Setting off from', 'Home');
      await searchAndChoose(tester, 'Going to');

      await tester.tap(find.widgetWithText(FilledButton, 'Create journey'));
      await tester.pumpAndSettle();

      final Map<String, dynamic> payload = trips.lastPayload!;

      expect(payload.keys, unorderedEquals(<String>['origin', 'destination']));

      final Map<String, dynamic> origin =
          payload['origin'] as Map<String, dynamic>;
      // A saved address travels as an id. The server resolves it inside this
      // customer's own scope; the client's opinion of where it is never enters
      // into it.
      expect(origin['saved_address_id'], 'addr-home');
      expect(origin.containsKey('latitude'), isFalse);

      // Nothing about the customer, the lifecycle or the route.
      expect(payload.toString().contains('customer_id'), isFalse);
      expect(payload.toString().contains('route_status'), isFalse);
    });

    testWidgets('lands on the journey, which shows no route', (
      WidgetTester tester,
    ) async {
      final FakeTripRepository trips = FakeTripRepository(
        addresses: <SavedAddress>[home()],
      );
      await openPlanner(tester, trips: trips);

      await chooseSaved(tester, 'Setting off from', 'Use my current location');

      await searchAndChoose(tester, 'Going to');

      await tester.tap(find.widgetWithText(FilledButton, 'Create journey'));
      await tester.pumpAndSettle();

      expect(trips.createCount, 1);
      expect(find.text('Route not calculated yet'), findsWidgets);

      // The assertions this module exists to make. Not "0 km", not "about 5
      // hours", not a progress bar at zero.
      expect(find.textContaining('km'), findsNothing);
      expect(find.textContaining('hr'), findsNothing);
      expect(find.textContaining('ETA'), findsNothing);
    });

    testWidgets('a refusal keeps both chosen places on screen', (
      WidgetTester tester,
    ) async {
      final FakeTripRepository trips = FakeTripRepository()
        ..nextWriteError = const ApiException(
          code: ApiErrorCode.tripLimitReached,
          message: 'too many',
          status: 422,
        );

      await openPlanner(tester, trips: trips);

      await chooseSaved(tester, 'Setting off from', 'Use my current location');

      await searchAndChoose(tester, 'Going to');

      await tester.tap(find.widgetWithText(FilledButton, 'Create journey'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Discard one to plan another'),
        findsOneWidget,
      );
      // Losing what somebody chose because the server said no is how a form
      // gets abandoned.
      expect(find.text('Jaipur International Airport'), findsOneWidget);
    });

    testWidgets('being offline says so, and keeps the plan', (
      WidgetTester tester,
    ) async {
      final FakeTripRepository trips = FakeTripRepository()
        ..nextWriteError = const ApiException(
          code: ApiErrorCode.network,
          message: 'offline',
          status: 0,
        );

      await openPlanner(tester, trips: trips);

      await chooseSaved(tester, 'Setting off from', 'Use my current location');

      await searchAndChoose(tester, 'Going to');

      await tester.tap(find.widgetWithText(FilledButton, 'Create journey'));
      await tester.pumpAndSettle();

      expect(find.byType(TripPlannerScreen), findsOneWidget);
      expect(find.text('Jaipur International Airport'), findsOneWidget);
    });
  });

  group('assistive technology', () {
    testWidgets('every labelled row can actually be activated', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await openPlanner(tester);

      // Found by driving the built app: the rows wrap their contents in
      // `Semantics(excludeSemantics: true)` to give the whole row one sensible
      // label, and that also removes the InkWell's tap action. A screen reader
      // announced "Setting off from, Choose your starting point, button" and
      // then had no way to press it.
      for (final String label in <String>[
        'Setting off from, Choose your starting point',
        'Going to, Choose your destination',
      ]) {
        final SemanticsNode node = tester.getSemantics(
          find.bySemanticsLabel(label),
        );
        expect(
          node.getSemanticsData().hasAction(SemanticsAction.tap),
          isTrue,
          reason: label,
        );
      }

      handle.dispose();
    });

    testWidgets('the picker rows can be activated too', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await openPlanner(tester);

      await tester.tap(find.text('Setting off from'));
      await tester.pumpAndSettle();

      final SemanticsNode node = tester.getSemantics(
        find.bySemanticsLabel(
          'Use my current location, We ask your device just once',
        ),
      );
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);

      handle.dispose();
    });
  });

  group('what the planner promises', () {
    testWidgets('says plainly that the route comes later', (
      WidgetTester tester,
    ) async {
      await openPlanner(tester);

      // Better than a map placeholder that looks like it is loading something.
      expect(
        find.textContaining('Route and travel time arrive with'),
        findsOneWidget,
      );
    });
  });
}
