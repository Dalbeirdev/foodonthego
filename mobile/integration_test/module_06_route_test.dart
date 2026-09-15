// Working out a route, on a real handset.
//
// WHY THIS ONE. With Module 05 driven, the device gap is Modules 03 and 06.
// This is 06: the screen that turns two chosen places into a driving route and
// reports what the provider said about it.
//
// IT COSTS EXACTLY ONE ROUTE CALCULATION, AND THAT IS THE MODULE'S OWN DESIGN.
//
// A route is a billed provider call, and this screen is built around that fact:
// `RouteController.open` calculates once, only when there is nothing to show
// AND the server says asking again could help, and never re-asks a journey whose
// provider already answered "no route". So the first test below opens a routeless
// journey and spends one call; the second opens the same journey again and spends
// none, because by then it has a route to read. That ordering is deliberate — it
// is also, incidentally, a check that the screen does not re-bill on every visit.
//
// WHAT IT CANNOT PROVE, AND DOES NOT CLAIM
//
// Not the map. No Maps API key exists for this project and none was invented
// (KI-011), so the SDK render stays unverified — on a device as everywhere else.
// What a keyless build shows instead IS verifiable, and is what a customer of
// such a build would see: the documented map-unavailable fallback, with the
// journey and its figures still on screen. That is the honest claim available
// here, and the third test makes exactly it.
//
// IT LEAVES THE ACCOUNT AS IT FOUND IT. The journey is created in setUpAll and
// discarded in tearDownAll — the rule KI-039 cost two other tests to learn.
//
// Run:
//   flutter test integration_test/module_06_route_test.dart \
//     --dart-define=FOTG_API_BASE_URL=http://127.0.0.1:8000 \
//     --dart-define=FOTG_TEST_TOKEN=<token>

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/core/config/app_environment.dart';
import 'package:foodonthego/core/format/journey_measures.dart';
import 'package:foodonthego/core/network/api_client.dart';
import 'package:foodonthego/core/routing/routes.dart';
import 'package:foodonthego/data/repositories/api_place_repository.dart';
import 'package:foodonthego/data/repositories/api_route_repository.dart';
import 'package:foodonthego/data/repositories/api_trip_repository.dart';
import 'package:foodonthego/domain/models/customer.dart';
import 'package:foodonthego/domain/models/place.dart';
import 'package:foodonthego/domain/models/trip.dart';
import 'package:foodonthego/domain/models/trip_route.dart';
import 'package:foodonthego/domain/repositories/route_repository.dart';
import 'package:foodonthego/features/routes/route_screen.dart';
import 'package:foodonthego/features/routes/widgets/route_map_view.dart';
import 'package:integration_test/integration_test.dart';

import 'support/device_support.dart';

const String _originQuery = 'green park';
const String _destinationQuery = 'jaipur airport';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late ApiClient api;
  late Customer customer;
  late ApiTripRepository trips;
  late ApiRouteRepository routes;
  late Trip journey;

  setUpAll(() async {
    requireToken();
    api = apiAs();
    customer = await whoAmI(api);
    trips = ApiTripRepository(api);
    routes = ApiRouteRepository(api);

    final ApiPlaceRepository places = ApiPlaceRepository(api);

    Future<PlaceDetails> resolve(String query) async {
      final List<PlaceSuggestion> found = await places.search(query);
      expect(
        found,
        isNotEmpty,
        reason: 'the places provider returned nothing for "$query"',
      );
      return places.details(found.first.placeId);
    }

    // A journey of this file's own, rather than whichever one the account
    // happens to have. A shared journey might already carry a route — and then
    // the first test would verify nothing, because the calculation it exists to
    // drive would never run.
    journey = await trips.createTrip(
      TripDraft(
        origin: TripLocation.fromPlace(await resolve(_originQuery)),
        destination: TripLocation.fromPlace(await resolve(_destinationQuery)),
      ),
    );

    expect(
      journey.routeStatus.hasUsableRoute,
      isFalse,
      reason: 'a newly planned journey must start without a route',
    );
  });

  tearDownAll(() async {
    try {
      await trips.discardTrip(journey.id);
    } on Object catch (error) {
      debugPrint(
        'WARNING: could not discard the journey ${journey.id}: $error',
      );
    }
    api.close();
  });

  /// Opens the route screen for this file's journey.
  Future<void> openRoute(WidgetTester tester) async {
    await launchSignedIn(
      tester,
      customer: customer,
      location: Routes.tripRoutePath(journey.id),
    );
    await waitFor(tester, find.byType(RouteScreen));

    // The distance label appears only once there is a route to describe, so
    // waiting for it is waiting for the calculation to land — without a fixed
    // sleep, and without assuming how long a provider takes.
    await waitFor(
      tester,
      find.text('Distance'),
      describe: 'the route summary, once the server had worked one out',
    );
  }

  testWidgets('opening a routeless journey works one out, and the figures on '
      'screen are the server\'s', (WidgetTester tester) async {
    await openRoute(tester);

    // Read back separately, over HTTP. A screen that agreed with itself would
    // pass whatever the client had decided to draw.
    final TripRoutes stored = await routes.routes(journey.id);

    expect(
      stored.routes,
      isNotEmpty,
      reason: 'opening the screen should have asked the server for a route',
    );

    final TripRoute route = stored.routes.first;

    // Formatted with the app's own helper rather than compared to a literal:
    // the figures come from a live provider, so "278 km" would be asserting
    // whatever the fixture happened to return this week. What is being checked
    // is that THIS route's numbers reached the screen.
    expect(
      find.text(JourneyMeasures.distance(route.distanceMeters)),
      findsWidgets,
      reason: 'the distance on screen is not the one the server stored',
    );
    expect(
      find.text(
        JourneyMeasures.duration(
          route.trafficDurationSeconds ?? route.durationSeconds,
        ),
      ),
      findsWidgets,
      reason: 'the travel time on screen is not the one the server stored',
    );
  });

  testWidgets('a second visit reads the route rather than buying another', (
    WidgetTester tester,
  ) async {
    // The journey now has a route, courtesy of the test above. Opening the
    // screen again must not spend a second provider call — the whole reason
    // `open` is guarded.
    // Route IDS, not timestamps. `calculated_at` is nullable on both sides of
    // the wire — `$this->calculated_at?->toIso8601String()` in the backend — so
    // a run where the provider omits it would compare null to null and pass
    // having proved nothing. A route id is a non-null String, and a set of them
    // does not depend on ordering either.
    final Set<String> before = (await routes.routes(journey.id)).routes
        .map((TripRoute route) => route.id)
        .toSet();

    expect(
      before,
      isNotEmpty,
      reason:
          'the route from the previous test is missing, so this check '
          'cannot mean anything',
    );

    await openRoute(tester);

    // The module's standing distinction, and the one the product turns on: how
    // long the driving takes is not when somebody reaches a restaurant.
    expect(
      find.textContaining('Driving time from the route'),
      findsOneWidget,
      reason: 'the screen must not present this as a pickup time',
    );

    final Set<String> after = (await routes.routes(journey.id)).routes
        .map((TripRoute route) => route.id)
        .toSet();

    expect(
      after,
      equals(before),
      reason:
          'the stored routes changed on a second visit — a recalculation is a '
          'billed call for an answer the journey already had',
    );
  });

  testWidgets('a stand-in route says so, rather than passing as a road', (
    WidgetTester tester,
  ) async {
    // THE PROJECT'S NO-INVENTION RULE, ON A DEVICE.
    //
    // No routing API key exists here, so the server answers from a development
    // stand-in. `TripRoute.provider` carries which service produced a route for
    // exactly this reason — the model's own comment says "a synthetic line can
    // never be mistaken for a road" — and the screen is supposed to say so.
    //
    // One assertion covering both directions, and no branch that never runs:
    // the notice must be on screen precisely when the route is NOT from a real
    // provider AND this build is allowed to show development notices. If keys
    // are ever configured, this keeps holding and starts checking the opposite
    // — that a real route is not labelled as fake.
    await openRoute(tester);

    final TripRoutes stored = await routes.routes(journey.id);
    final bool shouldWarn =
        !stored.isFromRealProvider &&
        AppEnvironment.current.showsDevelopmentNotices;

    expect(
      find
          .text('Development data — this is not a real road route.')
          .evaluate()
          .isNotEmpty,
      shouldWarn,
      reason: shouldWarn
          ? 'this route came from a development stand-in and the screen did '
                'not say so'
          : 'the screen warned about a development route that is not one',
    );
  });

  testWidgets('with no Maps key, the fallback carries what the map would have', (
    WidgetTester tester,
  ) async {
    await openRoute(tester);

    // Stated rather than assumed: this build has no key, so this is the state a
    // customer of it sees. If a key is ever configured for CI, this expectation
    // is the thing that should fail and be rewritten — not quietly skipped.
    expect(
      find.byType(MapUnavailableView),
      findsOneWidget,
      reason: 'a keyless build should show the documented map fallback',
    );
    expect(find.text('Map unavailable'), findsOneWidget);

    // And the figures survive the map's absence, which is the claim that makes
    // the fallback acceptable rather than merely tidy.
    final TripRoute route = (await routes.routes(journey.id)).routes.first;
    expect(
      find.text(JourneyMeasures.distance(route.distanceMeters)),
      findsWidgets,
    );
  });
}
