// Planning a journey on a real handset.
//
// WHY THIS ONE. Correcting the traceability matrix narrowed the device gap to
// Modules 03, 05 and 06, and Module 05 is the one that had been quietly
// exercised all along without ever being *driven*. Every later device test —
// cart, pickup, checkout — needs a journey, and each one builds it the same
// way: over HTTP, in a `prepare()` helper, as a fixture. module_13's own header
// says so in as many words: "It does not re-prove ... journey planning
// (Module 05)".
//
// So the planner screen, the place picker and the search field have never been
// touched by a finger on a device. That gap is not theoretical: the last defect
// found in this area (KI-036) was a link in the picker that put the customer on
// Page Not Found, and it was found by a *different* module's device test
// failing.
//
// NOTHING HERE IS A LITERAL THE SERVER DID NOT SUPPLY.
//
// The search queries are the only strings this file chooses. What the picker is
// expected to *show* — the suggestion's primary text, and the resolved place's
// display name — is read from the API first and then looked for on screen. A
// test that hardcoded "Jaipur International Airport" would pass or fail on what
// the provider happened to be returning that week, and would be asserting the
// fixture rather than the app.
//
// WHAT IT LEAVES BEHIND, DELIBERATELY
//
// One journey, created the way a customer creates one. That is not litter: the
// later device tests reuse an open discardable journey when they find one and
// only create their own when they do not, so this run gives the suite the
// fixture it would otherwise build for itself. No route is calculated here —
// that is Module 06, and a route is a billed provider call.
//
// Run:
//   flutter test integration_test/module_05_trip_planner_test.dart \
//     --dart-define=FOTG_API_BASE_URL=http://127.0.0.1:8000 \
//     --dart-define=FOTG_TEST_TOKEN=<token>

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/core/network/api_client.dart';
import 'package:foodonthego/core/routing/routes.dart';
import 'package:foodonthego/data/repositories/api_place_repository.dart';
import 'package:foodonthego/data/repositories/api_trip_repository.dart';
import 'package:foodonthego/domain/models/customer.dart';
import 'package:foodonthego/domain/models/place.dart';
import 'package:foodonthego/domain/models/trip.dart';
import 'package:foodonthego/domain/repositories/trip_repository.dart';
import 'package:foodonthego/features/addresses/saved_addresses_screen.dart';
import 'package:foodonthego/features/trips/trip_planner_screen.dart';
import 'package:foodonthego/features/trips/widgets/location_picker_sheet.dart';
import 'package:integration_test/integration_test.dart';

import 'support/device_support.dart';

/// The two queries, and the only strings here this file chooses itself.
const String _originQuery = 'green park';
const String _destinationQuery = 'jaipur airport';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late ApiClient api;
  late Customer customer;
  late ApiPlaceRepository places;
  late ApiTripRepository trips;

  setUpAll(() async {
    requireToken();
    api = apiAs();
    customer = await whoAmI(api);
    places = ApiPlaceRepository(api);
    trips = ApiTripRepository(api);
  });

  tearDownAll(() => api.close());

  /// What the provider actually returns for [query], as the picker will show it.
  ///
  /// Two values, because the picker shows two different ones: the suggestion row
  /// carries `primaryText`, and the slot — after the details call resolves the
  /// suggestion into a position — carries the resolved `displayName`. Asserting
  /// one against the other is how "the tap resolved the place" gets checked
  /// rather than assumed.
  Future<(PlaceSuggestion, PlaceDetails)> lookUp(String query) async {
    final List<PlaceSuggestion> found = await places.search(query);

    expect(
      found,
      isNotEmpty,
      reason: 'the places provider returned nothing for "$query"',
    );

    return (found.first, await places.details(found.first.placeId));
  }

  /// Inside the picker sheet only.
  ///
  /// Scoped for the reason test/trip_planner_test.dart records: the bottom
  /// navigation bar behind the sheet has a tab called "Home", and so can a saved
  /// address.
  Finder inSheet(String text) => find.descendant(
    of: find.byType(LocationPickerSheet),
    matching: find.text(text),
  );

  /// Opens one end, types the query on the device's own keyboard, and picks the
  /// suggestion the server said would be first.
  Future<void> choose(
    WidgetTester tester,
    String slotLabel,
    String query,
    PlaceSuggestion suggestion,
    PlaceDetails details,
  ) async {
    await tapAt(tester, find.text(slotLabel));
    await waitFor(tester, find.byType(LocationPickerSheet));

    // The real software keyboard, through the platform's text input. This is
    // the part a widget test cannot do.
    await tester.enterText(
      find.descendant(
        of: find.byType(LocationPickerSheet),
        matching: find.byType(TextField),
      ),
      query,
    );

    // No fixed wait for the debounce: waitFor polls in real time and returns as
    // soon as the results land, which is both faster and sound.
    await waitFor(
      tester,
      inSheet(suggestion.primaryText),
      describe: 'the suggestion "${suggestion.primaryText}" for "$query"',
    );
    await tapAt(tester, inSheet(suggestion.primaryText));

    // The sheet closes first, and waiting for that is not politeness. While it
    // is still on screen it is showing the very suggestion it just resolved, so
    // an unscoped wait for the resolved name could be satisfied by the SHEET and
    // return before the slot had been filled at all — passing for the wrong
    // reason whenever a provider's primary text equals its display name.
    await waitUntilGone(
      tester,
      find.byType(LocationPickerSheet),
      describe: 'the picker sheet, after choosing "${suggestion.primaryText}"',
    );

    // Then the slot, scoped to the planner. It shows the RESOLVED name, which
    // is the details call having happened — a suggestion has no position, and
    // the picker is not allowed to invent one.
    await waitFor(
      tester,
      find.descendant(
        of: find.byType(TripPlannerScreen),
        matching: find.text(details.displayName),
      ),
      describe:
          'the resolved place "${details.displayName}" in the $slotLabel slot',
    );
  }

  testWidgets('the planner opens with both ends empty and invents nothing', (
    WidgetTester tester,
  ) async {
    await launchSignedIn(
      tester,
      customer: customer,
      location: Routes.tripPlanPath,
    );

    await waitFor(tester, find.byType(TripPlannerScreen));

    expect(find.text('Choose your starting point'), findsOneWidget);
    expect(find.text('Choose your destination'), findsOneWidget);

    // The module's standing assertion, and the reason several of its widget
    // tests exist: nothing on this screen knows a distance or a duration,
    // because no journey has one yet. A plausible-looking placeholder is the
    // failure this guards.
    expect(find.textContaining('km'), findsNothing);
    expect(find.textContaining('min'), findsNothing);
  });

  testWidgets('two places chosen on the device become the journey the server '
      'stores', (WidgetTester tester) async {
    final (PlaceSuggestion originSuggestion, PlaceDetails origin) =
        await lookUp(_originQuery);
    final (PlaceSuggestion destinationSuggestion, PlaceDetails destination) =
        await lookUp(_destinationQuery);

    // Every journey this account already has, so the one created below can be
    // identified by difference rather than by "the newest", which two runs
    // starting together could disagree about.
    final Set<String> before = (await trips.trips(scope: TripScope.all))
        .map((Trip trip) => trip.id)
        .toSet();

    await launchSignedIn(
      tester,
      customer: customer,
      location: Routes.tripPlanPath,
    );
    await waitFor(tester, find.byType(TripPlannerScreen));

    await choose(
      tester,
      'Setting off from',
      _originQuery,
      originSuggestion,
      origin,
    );
    await choose(
      tester,
      'Going to',
      _destinationQuery,
      destinationSuggestion,
      destination,
    );

    final Finder create = find.widgetWithText(FilledButton, 'Create journey');
    await scrollTo(tester, create);
    await tapAt(tester, create);

    // The planner leaves for the journey it just made. Waiting for the planner
    // to GO is the signal, rather than for whatever replaces it: the journey
    // screen is Module 05's own and the assertion that matters is the server's.
    await waitUntilGone(
      tester,
      find.byType(TripPlannerScreen),
      describe: 'the planner, after Create journey',
    );

    // THE ASSERTION THAT COUNTS, and it is made against the server rather than
    // the screen. A planner that agreed with itself would pass whatever it sent.
    final List<Trip> after = await trips.trips(scope: TripScope.all);
    final Iterable<Trip> created = after.where(
      (Trip trip) => !before.contains(trip.id),
    );

    expect(
      created,
      hasLength(1),
      reason: 'creating one journey should add exactly one to the account',
    );

    final Trip journey = created.first;
    expect(journey.origin.displayName, origin.displayName);
    expect(journey.destination.displayName, destination.displayName);

    // Both ends carry a position. The client never sends one — it sends a place
    // id and the server resolves it — so this is the round trip, not an echo.
    expect(journey.origin.latitude, isNotNull);
    expect(journey.destination.latitude, isNotNull);

    // And no route was asked for. Planning ends here; Module 06 owns routing,
    // and a route is a billed provider call this module must not make.
    expect(
      journey.routeStatus.hasUsableRoute,
      isFalse,
      reason: 'planning a journey must not calculate a route',
    );
  });

  testWidgets('managing saved addresses opens from the picker, on the device', (
    WidgetTester tester,
  ) async {
    // KI-036 ON REAL HARDWARE. This link captured the router, closed the sheet
    // and pushed an unregistered path, landing the customer on Page Not Found
    // one tap from a half-planned journey. A widget test now covers the fix;
    // this is the same tap on a device, where the navigator stack is real.
    await launchSignedIn(
      tester,
      customer: customer,
      location: Routes.tripPlanPath,
    );
    await waitFor(tester, find.byType(TripPlannerScreen));

    await tapAt(tester, find.text('Setting off from'));
    await waitFor(tester, find.byType(LocationPickerSheet));

    final Finder link = inSheet('Manage saved addresses');
    await scrollTo(tester, link);
    await tapAt(tester, link);

    await waitFor(
      tester,
      find.byType(SavedAddressesScreen),
      describe: 'the saved addresses screen, opened from the picker',
    );

    // Named explicitly as well as by type, because the failure this replaces
    // rendered a screen that was perfectly real — just the wrong one.
    expect(find.text('Page Not Found'), findsNothing);
  });
}
