// The Module 07 end-to-end run: this app's own network layer against a running
// Laravel backend, real restaurant rows in MySQL, and the real route geometry
// Module 06 stored. No mocks, no fakes, no stubs.
//
// It walks the module's own example — Rahul plans Green Park → Jaipur airport,
// calculates a route, and asks what he could stop at — then checks that the
// ineligible fixtures are absent, that the figures are consistent with the
// geometry, that a second call is cheaper than the first, that suspending a
// restaurant removes it immediately, and that Ananya's journey is unreachable
// from Rahul's session.
//
// Run it with the backend serving and OTP_PROVIDER=log:
//
//   php artisan serve --host=127.0.0.1 --port=8000
//   dart run --define=FOTG_API_BASE_URL=http://127.0.0.1:8000 tool/discovery_smoke.dart
//
// WHAT THIS RUN CAN AND CANNOT ESTABLISH
//
// The eligibility rules, the corridor filter, the ordering, the availability
// logic, the privacy of the response and the ownership boundary are all real
// here and are genuinely exercised.
//
// The *detour* figures are only as real as the configured routing provider.
// Against `ROUTE_PROVIDER=development` the road network is a straight line, so
// every in-corridor detour is trivially small and the detour threshold can never
// exclude anything — the run says so rather than letting a reader assume the
// threshold was tested. That case is covered by automated tests with a provider
// the test controls; see `RestaurantDiscoveryServiceTest`.

import 'dart:io';

import 'package:foodonthego/core/config/api_config.dart';
import 'package:foodonthego/core/network/api_error_code.dart';
import 'package:foodonthego/domain/models/discovered_restaurant.dart';
import 'package:foodonthego/domain/models/place.dart';
import 'package:foodonthego/domain/models/trip.dart';
import 'package:foodonthego/domain/models/trip_route.dart';
import 'package:foodonthego/domain/repositories/route_repository.dart';

import 'support/smoke_support.dart';

/// Numbers from the Indian range reserved for testing and documentation.
const String _rahulPhone = '9999900701';
const String _ananyaPhone = '9999900702';

/// The fixtures the seeder creates, and what each one is for.
const String _near = '[TEST] Highway Spice Kitchen';
const String _further = '[TEST] Rajasthan Highway Bites';
const String _far = '[TEST] Far Away Kitchen';
const String _suspended = '[TEST] Suspended Dhaba';
const String _pending = '[TEST] Pending Restaurant';
const String _closed = '[TEST] Closed Route Cafe';
const String _behind = '[TEST] Behind You Diner';
const String _paused = '[TEST] Paused Highway Grill';

void main(List<String> args) async {
  stdout.writeln('FoodOnTheGo — Module 07 integration run');
  stdout.writeln('Backend: ${ApiConfig.baseUrl}');
  stdout.writeln('');

  await _seedFixtures();

  final Session rahul = await signIn('Rahul', 'Sharma', _rahulPhone);
  final Session ananya = await signIn('Ananya', 'Mehta', _ananyaPhone);

  await discardEverything(rahul);
  await discardEverything(ananya);

  // --- 1. a trip with no route yet -----------------------------------------
  final Trip trip = await _greenParkToJaipur(rahul);

  await expectRefused(
    'discovery is refused before a route exists',
    () => rahul.discovery.discover(trip.id),
    ApiErrorCode.routeNotReady,
  );

  // --- 2. the real Module 06 route -----------------------------------------
  final TripRoutes calculated = await rahul.routes.calculate(trip.id);
  final TripRoute route = calculated.selected!;

  check('Module 06 produced a usable selected route', () {
    expectValue(calculated.trip.routeStatus, RouteStatus.ready);
    expectValue(route.distanceMeters > 0, true);
  });

  // --- 3. discovery along it -----------------------------------------------
  final RestaurantDiscovery found = await rahul.discovery.discover(trip.id);

  final List<String> names = found.restaurants
      .map((DiscoveredRestaurant r) => r.name)
      .toList();

  check('the eligible fixtures on the route are discovered', () {
    expectValue(names.contains(_near), true);
    expectValue(names.contains(_further), true);
  });

  check('a restaurant outside the corridor is not discovered', () {
    expectValue(names.contains(_far), false);
  });

  check('a suspended restaurant is never discovered', () {
    expectValue(names.contains(_suspended), false);
  });

  check('a restaurant whose onboarding never finished is never discovered', () {
    expectValue(names.contains(_pending), false);
  });

  check('a closed restaurant is discovered, and marked closed', () {
    final DiscoveredRestaurant? cafe = _byName(found, _closed);

    expectValue(cafe != null, true);
    expectValue(cafe!.availability, RestaurantAvailability.closed);
  });

  check('a paused restaurant is discovered, and never marked open', () {
    final DiscoveredRestaurant? grill = _byName(found, _paused);

    expectValue(grill != null, true);
    expectValue(grill!.availability, RestaurantAvailability.notAcceptingOrders);
    expectValue(grill.isAcceptingOrders, false);
  });

  check('a restaurant behind the origin is flagged and listed last', () {
    final DiscoveredRestaurant? diner = _byName(found, _behind);

    expectValue(diner != null, true);
    expectValue(diner!.route.requiresBacktracking, true);
    expectValue(names.last, _behind);
  });

  check('the stops ahead are listed in journey order', () {
    final List<int> ahead = found.restaurants
        .where((DiscoveredRestaurant r) => !r.route.requiresBacktracking)
        .map((DiscoveredRestaurant r) => r.route.distanceAheadMetres)
        .toList();

    for (int i = 1; i < ahead.length; i++) {
      expectValue(ahead[i] >= ahead[i - 1], true);
    }
  });

  check('every distance ahead falls inside the route', () {
    for (final DiscoveredRestaurant r in found.restaurants) {
      expectValue(r.route.distanceAheadMetres >= 0, true);
      expectValue(r.route.distanceAheadMetres <= route.distanceMeters, true);
    }
  });

  check('every proximity is inside the configured corridor', () {
    for (final DiscoveredRestaurant r in found.restaurants) {
      expectValue(r.route.proximityMetres <= found.corridorMetres, true);
    }
  });

  check('time ahead is consistent with the route duration', () {
    for (final DiscoveredRestaurant r in found.restaurants) {
      expectValue(r.route.timeAheadSeconds != null, true);
      expectValue(r.route.timeAheadSeconds! <= route.durationSeconds, true);
    }
  });

  check('no rating is invented where there is no reviews module', () {
    for (final DiscoveredRestaurant r in found.restaurants) {
      expectValue(r.rating, null);
      expectValue(r.reviewCount, null);
    }
  });

  // What the run actually produced. Recorded rather than asserted: this run does
  // not decide what a detour between two places is.
  stdout.writeln('');
  stdout.writeln('  ── what this route actually returned ──');
  stdout.writeln('     route provider    : ${found.provider}');
  stdout.writeln('     real provider     : ${found.isFromRealProvider}');
  stdout.writeln('     corridor (metres) : ${found.corridorMetres}');
  stdout.writeln('     candidates        : ${found.candidatesConsidered}');
  stdout.writeln('     returned          : ${found.restaurants.length}');
  stdout.writeln('');
  stdout.writeln(
    '     ${'restaurant'.padRight(32)}'
    '${'availability'.padRight(22)}'
    '${'prox m'.padLeft(8)}'
    '${'detour m'.padLeft(10)}'
    '${'det s'.padLeft(7)}'
    '${'ahead m'.padLeft(10)}',
  );

  for (final DiscoveredRestaurant r in found.restaurants) {
    stdout.writeln(
      '     ${r.name.padRight(32)}'
      '${r.availability.wire.padRight(22)}'
      '${r.route.proximityMetres.toString().padLeft(8)}'
      '${(r.route.detourDistanceMetres?.toString() ?? '-').padLeft(10)}'
      '${(r.route.detourDurationSeconds?.toString() ?? '-').padLeft(7)}'
      '${r.route.distanceAheadMetres.toString().padLeft(10)}',
    );
  }

  if (!found.isFromRealProvider) {
    stdout.writeln('');
    stdout.writeln(
      '  NOTE  Detour-threshold exclusion = NOT APPLICABLE for this run — the\n'
      '        configured provider models the road network as a straight line,\n'
      '        so no in-corridor stop can exceed the detour limit. Covered by\n'
      '        RestaurantDiscoveryServiceTest with a controlled provider.',
    );
  }

  stdout.writeln('');

  // --- 4. privacy -----------------------------------------------------------
  await checkAsync('the response carries no private restaurant data', () async {
    final String body = await _rawDiscoveryBody(rahul, trip.id);

    for (final String secret in <String>[
      'owner_name',
      'owner_phone',
      'owner_email',
      'tax_identifier',
      'bank_account_reference',
      'commission_rate',
      'internal_notes',
      'Not a real business',
    ]) {
      expectValue(body.contains(secret), false);
    }
  });

  // --- 5. cost --------------------------------------------------------------
  await checkAsync('a second search reuses the first', () async {
    final RestaurantDiscovery again = await rahul.discovery.discover(trip.id);

    expectValue(again.fromCache, true);
    expectValue(again.restaurants.length, found.restaurants.length);
  });

  // --- 6. cache invalidation on a status change ----------------------------
  await checkAsync('suspending a restaurant removes it immediately', () async {
    await _setStatus(_near, 'SUSPENDED');

    final RestaurantDiscovery after = await rahul.discovery.discover(trip.id);

    expectValue(
      after.restaurants.any((DiscoveredRestaurant r) => r.name == _near),
      false,
    );

    await _setStatus(_near, 'APPROVED');
  });

  // --- 7. a different route finds different stops --------------------------
  await checkAsync(
    'a different journey does not reuse these results',
    () async {
      final Trip other = await _tripToChandigarh(rahul);
      await rahul.routes.calculate(other.id);

      final RestaurantDiscovery elsewhere = await rahul.discovery.discover(
        other.id,
      );

      // The fixtures are placed along the Jaipur road, not the Chandigarh one.
      expectValue(
        elsewhere.restaurants.any((DiscoveredRestaurant r) => r.name == _near),
        false,
      );
    },
  );

  // --- 8. ownership ---------------------------------------------------------
  final Trip hers = await _greenParkToJaipur(ananya);
  await ananya.routes.calculate(hers.id);

  await expectRefused(
    "Rahul cannot discover restaurants on Ananya's trip",
    () => rahul.discovery.discover(hers.id),
    ApiErrorCode.tripNotFound,
  );

  await checkAsync('no refusal leaks a word about her journey', () async {
    final String body = await _rawDiscoveryBody(rahul, hers.id);

    expectValue(body.contains(_near), false);
    expectValue(body.contains('Jaipur'), false);
  });

  await checkAsync('her own discovery still works', () async {
    final RestaurantDiscovery herResults = await ananya.discovery.discover(
      hers.id,
    );

    expectValue(herResults.restaurants.isNotEmpty, true);
  });

  await expectRefused(
    'an unauthenticated call reaches no restaurants',
    () async {
      final Session anonymous = Session('nobody', 'not-a-token');
      try {
        return await anonymous.discovery.discover(trip.id);
      } finally {
        anonymous.close();
      }
    },
    ApiErrorCode.unauthenticated,
  );

  rahul.close();
  ananya.close();

  stdout.writeln('');
  stdout.writeln('$passed passed, $failed failed');

  exit(failed == 0 ? 0 : 1);
}

DiscoveredRestaurant? _byName(RestaurantDiscovery found, String name) {
  for (final DiscoveredRestaurant r in found.restaurants) {
    if (r.name == name) return r;
  }
  return null;
}

Future<Trip> _greenParkToJaipur(Session session) async {
  final List<PlaceSuggestion> origin = await session.places.search(
    'green park',
  );
  final List<PlaceSuggestion> destination = await session.places.search(
    'jaipur airport',
  );

  return session.trips.createTrip(
    TripDraft(
      origin: TripLocation.fromPlace(
        await session.places.details(origin.first.placeId),
      ),
      destination: TripLocation.fromPlace(
        await session.places.details(destination.first.placeId),
      ),
    ),
  );
}

Future<Trip> _tripToChandigarh(Session session) async {
  final List<PlaceSuggestion> origin = await session.places.search(
    'connaught place',
  );
  final List<PlaceSuggestion> destination = await session.places.search(
    'sector 17',
  );

  return session.trips.createTrip(
    TripDraft(
      origin: TripLocation.fromPlace(
        await session.places.details(origin.first.placeId),
      ),
      destination: TripLocation.fromPlace(
        await session.places.details(destination.first.placeId),
      ),
    ),
  );
}

/// The raw response body, for assertions about what is *not* in it.
///
/// A parsed model cannot prove the absence of a field it does not know about,
/// and a leak three levels down inside a relation is exactly the sort a
/// structural assertion misses.
Future<String> _rawDiscoveryBody(Session session, String tripId) async {
  final HttpClient client = HttpClient();

  try {
    final HttpClientRequest request = await client.getUrl(
      Uri.parse(
        '${ApiConfig.baseUrl}/api/v1/customer/trips/$tripId/restaurants',
      ),
    );

    request.headers.set('Authorization', 'Bearer ${session.token}');
    request.headers.set('Accept', 'application/json');

    final HttpClientResponse response = await request.close();

    return await response.transform(const SystemEncoding().decoder).join();
  } finally {
    client.close();
  }
}

/// Seeds the documented discovery fixtures.
///
/// Through the seeder rather than through SQL here, so the run exercises the
/// same development-only path a developer would use — including its refusal to
/// run in production.
Future<void> _seedFixtures() async {
  final ProcessResult result = await Process.run('php', <String>[
    'artisan',
    'db:seed',
    '--class=DiscoveryTestRestaurantSeeder',
    '--force',
  ], workingDirectory: '../backend');

  if (result.exitCode != 0) {
    throw StateError('could not seed discovery fixtures: ${result.stderr}');
  }
}

/// Changes a restaurant's status behind the API's back.
///
/// There is no operator API yet — that is a later module — so the only honest
/// way to exercise "a suspension takes effect immediately" is to change the row
/// the way the restaurant dashboard eventually will.
Future<void> _setStatus(String name, String status) async {
  final ProcessResult result = await Process.run('mysql', <String>[
    '-N',
    '-B',
    'foodonthego_local',
    '-e',
    "UPDATE restaurants SET status = '$status' WHERE name = '$name';",
  ]);

  if (result.exitCode != 0) {
    throw StateError('could not change the status: ${result.stderr}');
  }
}
