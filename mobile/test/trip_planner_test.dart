import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/core/network/api_error_code.dart';
import 'package:foodonthego/core/network/api_exception.dart';
import 'package:foodonthego/domain/models/customer_summary.dart';
import 'package:foodonthego/domain/models/home_dashboard.dart';
import 'package:foodonthego/domain/models/saved_address.dart';
import 'package:foodonthego/domain/models/trip.dart';
import 'package:foodonthego/features/trips/trip_form_screen.dart';
import 'package:foodonthego/features/trips/trips_screen.dart';

import 'support/harness.dart';

void main() {
  const HomeDashboard dashboard = HomeDashboard(
    customer: CustomerSummary(fullName: 'Rahul Sharma'),
  );

  /// Opens the planner from the Trips tab, the way a customer reaches it.
  Future<FakeTripRepository> openPlanner(
    WidgetTester tester, {
    FakeTripRepository? repository,
    List<SavedAddress> addresses = const <SavedAddress>[],
    Size size = const Size(390, 844),
  }) async {
    final FakeTripRepository trips = repository ?? FakeTripRepository();

    usePhoneSurface(tester, size: size);
    await tester.pumpWidget(
      wrapApp(
        repository: StubHomeRepository.value(dashboard),
        trips: trips,
        customer: FakeCustomerRepository(addresses: addresses),
        initialLocation: '/trips',
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Plan your first journey'));
    await tester.pumpAndSettle();

    return trips;
  }

  /// Fills one end of the journey through the picker's typed branch.
  Future<void> choosePlace(
    WidgetTester tester, {
    required String field,
    required String city,
    String? label,
  }) async {
    await tester.tap(find.text(field));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'City'), city);

    if (label != null) {
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Name this place (optional)'),
        label,
      );
    }

    await tester.tap(find.text('Use this place'));
    await tester.pumpAndSettle();
  }

  group('the form', () {
    testWidgets('opens with both ends empty and a departure suggested', (
      WidgetTester tester,
    ) async {
      await openPlanner(tester);

      expect(find.text('Choose your starting point'), findsOneWidget);
      expect(find.text('Choose your destination'), findsOneWidget);
      // A departure is pre-filled to the next quarter hour: most journeys are
      // planned for soon, and an empty field is one more thing to fill in.
      expect(
        find.text('Not set'),
        findsOneWidget,
      ); // the arrival, not departure
    });

    testWidgets('says plainly that arrival is not computed yet', (
      WidgetTester tester,
    ) async {
      await openPlanner(tester);

      expect(
        find.textContaining('FoodOnTheGo will work it out for you'),
        findsOneWidget,
      );
    });

    testWidgets('refuses to save without a starting point or destination', (
      WidgetTester tester,
    ) async {
      final FakeTripRepository trips = await openPlanner(tester);

      await tester.tap(find.text('Save journey'));
      await tester.pumpAndSettle();

      expect(
        find.text('Choose where you are setting off from.'),
        findsOneWidget,
      );
      expect(find.text('Choose where you are going.'), findsOneWidget);
      // Nothing was sent. A form that fires a request it knows will fail wastes
      // a round trip and a traveller's data.
      expect(trips.planCount, 0);
    });

    testWidgets(
      'refuses the same place at both ends before asking the server',
      (WidgetTester tester) async {
        final FakeTripRepository trips = await openPlanner(tester);

        await choosePlace(tester, field: 'Setting off from', city: 'Jaipur');
        await choosePlace(tester, field: 'Going to', city: 'Jaipur');

        await tester.tap(find.text('Save journey'));
        await tester.pumpAndSettle();

        expect(
          find.text('Choose a destination different from your starting point.'),
          findsOneWidget,
        );
        expect(trips.planCount, 0);
      },
    );

    testWidgets('a complete journey is saved and reported once', (
      WidgetTester tester,
    ) async {
      final FakeTripRepository trips = await openPlanner(tester);

      await choosePlace(
        tester,
        field: 'Setting off from',
        city: 'New Delhi',
        label: 'Home',
      );
      await choosePlace(tester, field: 'Going to', city: 'Jaipur');

      await tester.tap(find.text('Save journey'));
      await tester.pumpAndSettle();

      expect(trips.planCount, 1);
      // Back on the list, with the confirmation — and only after the server said
      // so, which is what the fake's own rules enforce.
      expect(find.byType(TripsScreen), findsOneWidget);
      expect(find.text('Journey saved'), findsOneWidget);
    });

    testWidgets('the draft carries what the customer chose', (
      WidgetTester tester,
    ) async {
      final FakeTripRepository trips = await openPlanner(tester);

      await choosePlace(
        tester,
        field: 'Setting off from',
        city: 'New Delhi',
        label: 'Home',
      );
      await choosePlace(tester, field: 'Going to', city: 'Jaipur');

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Note (optional)'),
        'Collecting my sister',
      );
      await tester.tap(find.byTooltip('One more traveller'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save journey'));
      await tester.pumpAndSettle();

      final Map<String, dynamic> json = trips.lastDraft!.toJson();

      expect(json['traveller_count'], 2);
      expect(json['note'], 'Collecting my sister');
      expect((json['origin'] as Map<String, dynamic>)['city'], 'New Delhi');
    });

    testWidgets('no coordinates are invented for a typed place', (
      WidgetTester tester,
    ) async {
      final FakeTripRepository trips = await openPlanner(tester);

      await choosePlace(tester, field: 'Setting off from', city: 'New Delhi');
      await choosePlace(tester, field: 'Going to', city: 'Jaipur');

      await tester.tap(find.text('Save journey'));
      await tester.pumpAndSettle();

      final Map<String, dynamic> origin =
          trips.lastDraft!.toJson()['origin'] as Map<String, dynamic>;

      // Nothing on this screen geocoded anything, so nothing pretends to have.
      expect(origin.containsKey('latitude'), isFalse);
      expect(origin.containsKey('longitude'), isFalse);
      expect(origin.containsKey('place_id'), isFalse);
    });

    testWidgets('a second tap cannot plan the journey twice', (
      WidgetTester tester,
    ) async {
      final FakeTripRepository trips = await openPlanner(tester);

      await choosePlace(tester, field: 'Setting off from', city: 'New Delhi');
      await choosePlace(tester, field: 'Going to', city: 'Jaipur');

      await tester.tap(find.text('Save journey'));
      // Deliberately not settled: the save is still in flight.
      await tester.pump();
      await tester.tap(find.text('Save journey'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(trips.planCount, 1);
    });
  });

  group('the two layout rules Module 04 learned', () {
    testWidgets('every field validates even on a screen too short to show it', (
      WidgetTester tester,
    ) async {
      // The Module 04 defect: a ListView builds lazily, so a field scrolled out
      // of view is never registered with the Form and validate() skips it in
      // silence. On a 320x568 surface most of this form is off screen.
      final FakeTripRepository trips = await openPlanner(
        tester,
        size: const Size(320, 568),
      );

      await tester.tap(find.text('Save journey'));
      await tester.pumpAndSettle();

      expect(
        find.text('Choose where you are setting off from.'),
        findsOneWidget,
      );
      expect(trips.planCount, 0);
    });

    testWidgets('the action is reachable on the shortest supported screen', (
      WidgetTester tester,
    ) async {
      await openPlanner(tester, size: const Size(320, 568));

      // Pinned above the keyboard rather than placed after the last field,
      // where it sat under the bottom navigation bar and the tap went to the
      // wrong widget.
      expect(find.text('Save journey'), findsOneWidget);
      expect(tester.getSize(find.text('Save journey')).height, greaterThan(0));
      expect(tester.takeException(), isNull);
    });
  });

  group('saved addresses in the picker', () {
    testWidgets("a customer's saved places are offered first", (
      WidgetTester tester,
    ) async {
      await openPlanner(
        tester,
        addresses: <SavedAddress>[
          sampleAddress(id: 'a1', label: 'Home'),
          sampleAddress(id: 'a2', label: 'Work', type: AddressType.work),
        ],
      );

      await tester.tap(find.text('Setting off from'));
      await tester.pumpAndSettle();

      expect(find.text('Your saved addresses'), findsOneWidget);
      // Scoped to the sheet's rows: the bottom navigation bar also says "Home".
      expect(
        find.descendant(of: find.byType(ListTile), matching: find.text('Home')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byType(ListTile), matching: find.text('Work')),
        findsOneWidget,
      );
    });

    testWidgets('picking one sends its id, not a copy of its text', (
      WidgetTester tester,
    ) async {
      final FakeTripRepository trips = await openPlanner(
        tester,
        addresses: <SavedAddress>[sampleAddress(id: 'a1', label: 'Home')],
      );

      await tester.tap(find.text('Setting off from'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: find.byType(ListTile), matching: find.text('Home')),
      );
      await tester.pumpAndSettle();

      await choosePlace(tester, field: 'Going to', city: 'Jaipur');

      await tester.tap(find.text('Save journey'));
      await tester.pumpAndSettle();

      final Map<String, dynamic> origin =
          trips.lastDraft!.toJson()['origin'] as Map<String, dynamic>;

      // The id alone. The server resolves it through its own ownership check and
      // snapshots it — a client-side copy would skip that check entirely.
      expect(origin, <String, dynamic>{'address_id': 'a1'});
    });

    testWidgets('an account with none is told so, not shown an empty list', (
      WidgetTester tester,
    ) async {
      await openPlanner(tester);

      await tester.tap(find.text('Setting off from'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('You have no saved addresses yet'),
        findsOneWidget,
      );
    });
  });

  group('when the server refuses', () {
    testWidgets('a field error lands on its field, not in a snackbar', (
      WidgetTester tester,
    ) async {
      final FakeTripRepository trips = await openPlanner(tester);

      trips.nextWriteError = const ApiException(
        code: ApiErrorCode.validationFailed,
        message: 'server prose the app never shows',
        status: 422,
        details: <String, dynamic>{
          'fields': <String, dynamic>{
            'departure_at': <String>['Choose a departure time in the future.'],
          },
        },
      );

      await choosePlace(tester, field: 'Setting off from', city: 'New Delhi');
      await choosePlace(tester, field: 'Going to', city: 'Jaipur');

      await tester.tap(find.text('Save journey'));
      await tester.pumpAndSettle();

      expect(
        find.text('Choose a departure time in the future.'),
        findsOneWidget,
      );
      // Still on the form, with what the customer typed intact.
      expect(find.byType(TripFormScreen), findsOneWidget);
      expect(find.text('server prose the app never shows'), findsNothing);
    });

    testWidgets('the journey limit is reported in the app\'s own words', (
      WidgetTester tester,
    ) async {
      final FakeTripRepository trips = await openPlanner(tester);

      trips.nextWriteError = const ApiException(
        code: ApiErrorCode.tripLimitReached,
        message: 'server wording',
        status: 422,
      );

      await choosePlace(tester, field: 'Setting off from', city: 'New Delhi');
      await choosePlace(tester, field: 'Going to', city: 'Jaipur');

      await tester.tap(find.text('Save journey'));
      await tester.pumpAndSettle();

      expect(find.textContaining('upcoming journeys'), findsOneWidget);
      expect(find.byType(TripFormScreen), findsOneWidget);
    });

    testWidgets('losing the network never claims the journey was saved', (
      WidgetTester tester,
    ) async {
      final FakeTripRepository trips = await openPlanner(tester);

      trips.nextWriteError = const ApiException.network();

      await choosePlace(tester, field: 'Setting off from', city: 'New Delhi');
      await choosePlace(tester, field: 'Going to', city: 'Jaipur');

      await tester.tap(find.text('Save journey'));
      await tester.pumpAndSettle();

      expect(find.text('Journey saved'), findsNothing);
      expect(find.byType(TripFormScreen), findsOneWidget);
      expect(trips.snapshot, isEmpty);
    });
  });

  group('editing', () {
    Future<FakeTripRepository> openEditor(WidgetTester tester) async {
      final FakeTripRepository trips = FakeTripRepository(
        trips: <Trip>[sampleTrip(note: 'Collecting my sister')],
      );

      usePhoneSurface(tester);
      await tester.pumpWidget(
        wrapApp(
          repository: StubHomeRepository.value(dashboard),
          trips: trips,
          initialLocation: '/trips',
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit journey').last);
      await tester.pumpAndSettle();

      return trips;
    }

    testWidgets('opens with the journey already in it', (
      WidgetTester tester,
    ) async {
      await openEditor(tester);

      expect(find.text('Edit journey'), findsOneWidget);
      expect(find.text('Collecting my sister'), findsOneWidget);
      expect(find.text('Save changes'), findsOneWidget);
    });

    testWidgets('clearing the note sends an explicit null, not an omission', (
      WidgetTester tester,
    ) async {
      final FakeTripRepository trips = await openEditor(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Note (optional)'),
        '',
      );
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      final Map<String, dynamic> json = trips.lastDraft!.toJson();

      // An omitted key means "leave it", so a client that could not send null
      // would make removing a note impossible.
      expect(json.containsKey('note'), isTrue);
      expect(json['note'], isNull);
    });
  });
}
