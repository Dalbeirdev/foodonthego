// The Module 09 end-to-end run: this app's own network layer against a running
// Laravel backend, real restaurant rows in MySQL, and the real route geometry
// Module 06 stored. No mocks, no fakes, no stubs.
//
// It walks the module's own example — Rahul plans Green Park -> Jaipur airport,
// discovers what is on the road, opens one of the results, and reads it — then
// checks the two things this module turns on: that a restaurant's uuid buys
// nothing eligibility did not already allow, and that opening the page calls no
// routing provider.
//
// Run it with the backend serving and OTP_PROVIDER=log:
//
//   php artisan serve --host=127.0.0.1 --port=8000
//   dart run --define=FOTG_API_BASE_URL=http://127.0.0.1:8000 \
//     tool/restaurant_detail_smoke.dart
//
// WHAT THIS RUN CAN AND CANNOT ESTABLISH
//
// Eligibility, the direct-id refusals, the customer-safe projection, the
// availability states, the opening-hours arithmetic, the route-context reuse
// and the ownership boundary are all real here.
//
// Ratings are not exercised against real data, because no restaurant has one:
// there is no reviews module. The run checks the honest behaviour instead — the
// field is null and the client shows "New" rather than a score nobody earned.
//
// The detour figures are only as real as the configured routing provider.
// Against ROUTE_PROVIDER=development the road network is a straight line, so
// every in-corridor detour is trivially small. What this run *does* establish
// about detour is the part that matters here: whatever the figure is, the
// detail screen shows the same one the list did, and produced it without
// asking a provider again.

import 'dart:convert';
import 'dart:io';

import 'package:foodonthego/core/config/api_config.dart';
import 'package:foodonthego/core/network/api_error_code.dart';
import 'package:foodonthego/domain/models/discovered_restaurant.dart';
import 'package:foodonthego/domain/models/place.dart';
import 'package:foodonthego/domain/models/restaurant_detail.dart';
import 'package:foodonthego/domain/models/trip.dart';

import 'support/smoke_support.dart';

const String _rahulPhone = '9999900901';
const String _ananyaPhone = '9999900902';

const String _spice = '[TEST] Highway Spice Kitchen';
const String _nightOwl = '[TEST] Night Owl Dhaba';
const String _split = '[TEST] Midday Break Kitchen';
const String _bare = '[TEST] Bare Bones Stop';
const String _paused = '[TEST] Paused Highway Grill';
const String _closed = '[TEST] Closed Route Cafe';
const String _suspended = '[TEST] Suspended Dhaba';
const String _pending = '[TEST] Pending Restaurant';
const String _far = '[TEST] Far Away Kitchen';

void main(List<String> args) async {
  stdout.writeln('FoodOnTheGo — Module 09 integration run');
  stdout.writeln('Backend: ${ApiConfig.baseUrl}');
  stdout.writeln('');

  await _seedFixtures();

  final Session rahul = await signIn('Rahul', 'Sharma', _rahulPhone);
  final Session ananya = await signIn('Ananya', 'Mehta', _ananyaPhone);

  await discardEverything(rahul);
  await discardEverything(ananya);

  final Trip trip = await _greenParkToJaipur(rahul);
  await rahul.routes.calculate(trip.id);

  // --- 1. discovery, then one of its results -------------------------------
  final RestaurantDiscovery found = await rahul.discovery.discover(trip.id);

  final Map<String, DiscoveredRestaurant> byName =
      <String, DiscoveredRestaurant>{
        for (final DiscoveredRestaurant r in found.restaurants) r.name: r,
      };

  check('Module 07 still finds the fixtures this module needs', () {
    for (final String name in <String>[
      _spice,
      _nightOwl,
      _split,
      _bare,
      _paused,
      _closed,
    ]) {
      expectValue(byName.containsKey(name), true);
    }
  });

  final DiscoveredRestaurant card = byName[_spice]!;

  final RestaurantDetail detail = await rahul.restaurants.detail(
    tripId: trip.id,
    restaurantId: card.id,
  );

  check('the detail is the restaurant that was tapped', () {
    expectValue(detail.id, card.id);
    expectValue(detail.name, _spice);
  });

  check('the route figures are the ones the card showed', () {
    // A card saying "4 min detour" and a page saying "9 min" is the kind of
    // disagreement a customer does not forgive.
    expectValue(
      detail.restaurant.route.distanceAheadMetres,
      card.route.distanceAheadMetres,
    );
    expectValue(
      detail.restaurant.route.detourDurationSeconds,
      card.route.detourDurationSeconds,
    );
    expectValue(
      detail.restaurant.route.proximityMetres,
      card.route.proximityMetres,
    );
  });

  check('the profile the list did not carry is here', () {
    expectValue(detail.hasDescription, true);
    expectValue(detail.publicPhone != null, true);
    expectValue(detail.media.length, 3);
    expectValue(detail.restaurant.cuisines.contains('North Indian'), true);
    expectValue(detail.restaurant.facilities.contains('Parking'), true);
  });

  check('a photograph carries the operator caption where there is one', () {
    expectValue(detail.media.first.altText != null, true);
    // The third fixture image has no caption, and gets none invented.
    expectValue(detail.media.last.altText, null);
  });

  check('no rating is invented where there is no reviews module', () {
    expectValue(detail.restaurant.rating, null);
    expectValue(detail.restaurant.reviewCount, null);
  });

  // --- 2. availability -----------------------------------------------------
  await checkAsync('an open restaurant may be ordered from', () async {
    expectValue(detail.ordering, RestaurantOrderingState.openAccepting);
    expectValue(detail.canOrder, true);
  });

  await checkAsync('a paused kitchen is open and not orderable', () async {
    final RestaurantDetail grill = await rahul.restaurants.detail(
      tripId: trip.id,
      restaurantId: byName[_paused]!.id,
    );

    expectValue(grill.ordering, RestaurantOrderingState.openPaused);
    expectValue(grill.canOrder, false);
    // Still worth reading the menu: the pause may lift before arrival.
    expectValue(grill.hours.isOpenNow, true);
  });

  await checkAsync('a closed restaurant says when it opens again', () async {
    final RestaurantDetail cafe = await rahul.restaurants.detail(
      tripId: trip.id,
      restaurantId: byName[_closed]!.id,
    );

    expectValue(cafe.ordering, RestaurantOrderingState.closed);
    expectValue(cafe.canOrder, false);
    expectValue(cafe.hours.isOpenNow, false);
    expectValue(cafe.hours.nextOpenAt != null, true);
  });

  // --- 3. opening hours ----------------------------------------------------
  await checkAsync('an overnight kitchen is described as one', () async {
    final RestaurantDetail owl = await rahul.restaurants.detail(
      tripId: trip.id,
      restaurantId: byName[_nightOwl]!.id,
    );

    final DayHours anyDay = owl.hours.week.first;

    expectValue(anyDay.windows.length, 1);
    expectValue(anyDay.windows.single.opensAt, '18:00:00');
    expectValue(anyDay.windows.single.closesAt, '02:00:00');
    // The flag the screen renders as "(overnight)", because "18:00 - 02:00"
    // read quickly looks like a typo.
    expectValue(anyDay.windows.single.isOvernight, true);
  });

  await checkAsync('a split service is two windows and a shut day', () async {
    final RestaurantDetail kitchen = await rahul.restaurants.detail(
      tripId: trip.id,
      restaurantId: byName[_split]!.id,
    );

    expectValue(kitchen.hours.week.length, 7);

    // Monday, which this kitchen takes off. A closed day is a row that says
    // Closed, not a gap in the list.
    expectValue(kitchen.hours.week.first.isClosed, true);

    final DayHours tuesday = kitchen.hours.week[1];
    expectValue(tuesday.windows.length, 2);
    expectValue(tuesday.windows.first.opensAt, '11:00:00');
    expectValue(tuesday.windows.last.opensAt, '18:00:00');
  });

  await checkAsync(
    'the times are the restaurants own, not the servers',
    () async {
      expectValue(detail.hours.timezone, 'Asia/Kolkata');
    },
  );

  // --- 4. what a restaurant did not tell us --------------------------------
  await checkAsync('missing metadata is omitted, never invented', () async {
    final RestaurantDetail bare = await rahul.restaurants.detail(
      tripId: trip.id,
      restaurantId: byName[_bare]!.id,
    );

    expectValue(bare.description, null);
    expectValue(bare.publicPhone, null);
    expectValue(bare.media.isEmpty, true);
    expectValue(bare.restaurant.facilities.isEmpty, true);
    expectValue(bare.restaurant.priceLevel, null);
    expectValue(bare.restaurant.rating, null);
  });

  // --- 5. a uuid unlocks nothing -------------------------------------------
  await expectRefused(
    'a suspended restaurant cannot be opened by its uuid',
    () => rahul.restaurants.detail(
      tripId: trip.id,
      restaurantId: _uuidOf(_suspended),
    ),
    ApiErrorCode.restaurantUnavailable,
  );

  await expectRefused(
    'an unverified restaurant cannot be opened by its uuid',
    () => rahul.restaurants.detail(
      tripId: trip.id,
      restaurantId: _uuidOf(_pending),
    ),
    ApiErrorCode.restaurantUnavailable,
  );

  await expectRefused(
    'a restaurant outside the corridor says which problem it is',
    () =>
        rahul.restaurants.detail(tripId: trip.id, restaurantId: _uuidOf(_far)),
    ApiErrorCode.restaurantOutsideRoute,
  );

  await expectRefused(
    'an unknown uuid is not found',
    () => rahul.restaurants.detail(
      tripId: trip.id,
      restaurantId: '00000000-0000-4000-8000-000000000000',
    ),
    ApiErrorCode.restaurantNotFound,
  );

  await checkAsync('a refusal says nothing about the business', () async {
    final String body = await _rawDetailBody(
      rahul,
      trip.id,
      _uuidOf(_suspended),
    );

    expectValue(body.contains('Suspended Dhaba'), false);
    expectValue(body.contains('SUSPENDED'), false);
  });

  // --- 6. privacy -----------------------------------------------------------
  await checkAsync('the response carries no private restaurant data', () async {
    final String body = await _rawDetailBody(rahul, trip.id, card.id);

    for (final String secret in <String>[
      'owner_name',
      'owner_phone',
      'owner_email',
      'tax_identifier',
      'bank_account_reference',
      'commission_rate',
      'internal_notes',
      'verification_status',
      'is_discoverable',
      'Not a real business',
      '+910000000000',
    ]) {
      expectValue(body.contains(secret), false);
    }

    // The published business number is a different column, and is allowed.
    expectValue(body.contains('+911412345678'), true);
  });

  // --- 7. read-only ---------------------------------------------------------
  await checkAsync('a customer has no way to change a restaurant', () async {
    for (final String method in <String>['PUT', 'PATCH', 'DELETE', 'POST']) {
      final int status = await _statusOf(rahul, trip.id, card.id, method);

      expectValue(status == 404 || status == 405, true);
    }
  });

  // --- 8. cost --------------------------------------------------------------
  await checkAsync(
    'opening a restaurant reuses the discovery search',
    () async {
      // Warm, from the discovery call at the top of this run.
      for (int i = 0; i < 4; i++) {
        final RestaurantDetail again = await rahul.restaurants.detail(
          tripId: trip.id,
          restaurantId: card.id,
        );

        expectValue(again.routeFromCache, true);
      }
    },
  );

  // --- 9. the operational state is read again, not remembered --------------
  await checkAsync(
    'a pause after discovery is reflected on the page',
    () async {
      await _setAccepting(_spice, false);

      try {
        final RestaurantDetail paused = await rahul.restaurants.detail(
          tripId: trip.id,
          restaurantId: card.id,
        );

        // The discovery result may be five minutes old. The page reads the row
        // again rather than presenting a stale "accepting orders".
        expectValue(paused.ordering, RestaurantOrderingState.openPaused);
      } finally {
        await _setAccepting(_spice, true);
      }
    },
  );

  await checkAsync('a suspension after discovery withdraws the page', () async {
    await _setStatus(_spice, 'SUSPENDED');

    try {
      await rahul.restaurants.detail(tripId: trip.id, restaurantId: card.id);
      expectValue('no refusal', 'a refusal');
    } on Object catch (error) {
      expectValue(error.toString().contains('RESTAURANT_UNAVAILABLE'), true);
    } finally {
      await _setStatus(_spice, 'APPROVED');
    }
  });

  // --- 10. ownership --------------------------------------------------------
  final Trip hers = await _greenParkToJaipur(ananya);
  await ananya.routes.calculate(hers.id);

  await expectRefused(
    "Rahul cannot open a restaurant on Ananya's trip",
    () => rahul.restaurants.detail(tripId: hers.id, restaurantId: card.id),
    ApiErrorCode.tripNotFound,
  );

  await expectRefused(
    'an unauthenticated call reaches no restaurant',
    () async {
      final Session anonymous = Session('nobody', 'not-a-token');
      try {
        return await anonymous.restaurants.detail(
          tripId: trip.id,
          restaurantId: card.id,
        );
      } finally {
        anonymous.close();
      }
    },
    ApiErrorCode.unauthenticated,
  );

  // --- what the run actually produced --------------------------------------
  stdout.writeln('');
  stdout.writeln('  ── the restaurant this run opened ──');
  stdout.writeln('     name          : ${detail.name}');
  stdout.writeln(
    '     cuisines      : ${detail.restaurant.cuisines.join(", ")}',
  );
  stdout.writeln(
    '     facilities    : ${detail.restaurant.facilities.join(", ")}',
  );
  stdout.writeln('     price level   : ${detail.restaurant.priceLevel ?? "-"}');
  stdout.writeln('     rating        : ${detail.restaurant.rating ?? "none"}');
  stdout.writeln('     photographs   : ${detail.media.length}');
  stdout.writeln('     ordering      : ${detail.ordering.wire}');
  stdout.writeln('     timezone      : ${detail.hours.timezone}');
  stdout.writeln(
    '     distance ahead: ${detail.restaurant.route.distanceAheadMetres} m',
  );
  stdout.writeln(
    '     detour        : ${detail.restaurant.route.detourDurationSeconds ?? "-"} s',
  );
  stdout.writeln(
    '     off route     : ${detail.restaurant.route.proximityMetres} m',
  );
  stdout.writeln('     route cached  : ${detail.routeFromCache}');

  if (!found.isFromRealProvider) {
    stdout.writeln('');
    stdout.writeln(
      '  NOTE  Rating = NOT APPLICABLE — no restaurant has one, because there\n'
      '        is no reviews module. The field is null and the client shows\n'
      '        "New" rather than a score nobody earned.\n'
      '  NOTE  Detour magnitude = NOT MEANINGFUL for this run — the configured\n'
      '        provider models the road network as a straight line. What this\n'
      '        run does establish is that the page shows the same figure the\n'
      '        list did, and reached it without calling a provider again.',
    );
  }

  rahul.close();
  ananya.close();

  stdout.writeln('');
  stdout.writeln('$passed passed, $failed failed');

  exit(failed == 0 ? 0 : 1);
}

/// A fixture's uuid, read straight from the database.
///
/// The point of the direct-id tests is that a customer who has somehow
/// obtained an identifier gains nothing by it, so the identifier has to come
/// from outside the API rather than from a response the API decided to send.
String _uuidOf(String name) {
  final ProcessResult result = Process.runSync('mysql', <String>[
    '-N',
    '-B',
    'foodonthego_local',
    '-e',
    "SELECT uuid FROM restaurants WHERE name = '$name' LIMIT 1;",
  ]);

  final String uuid = (result.stdout as String).trim();

  if (uuid.isEmpty) {
    throw StateError('no fixture called $name');
  }

  return uuid;
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

/// The raw body, for assertions about what is *not* in it.
Future<String> _rawDetailBody(
  Session session,
  String tripId,
  String restaurantId,
) async {
  final HttpClient client = HttpClient();

  try {
    final HttpClientRequest request = await client.getUrl(
      Uri.parse(
        '${ApiConfig.baseUrl}/api/v1/customer/trips/$tripId'
        '/restaurants/$restaurantId',
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

/// The status of a request the customer API should not accept at all.
Future<int> _statusOf(
  Session session,
  String tripId,
  String restaurantId,
  String method,
) async {
  final HttpClient client = HttpClient();

  try {
    final HttpClientRequest request = await client.openUrl(
      method,
      Uri.parse(
        '${ApiConfig.baseUrl}/api/v1/customer/trips/$tripId'
        '/restaurants/$restaurantId',
      ),
    );

    request.headers.set('Authorization', 'Bearer ${session.token}');
    request.headers.set('Accept', 'application/json');
    request.headers.contentType = ContentType.json;
    request.write(
      jsonEncode(<String, String>{'name': 'Renamed By A Customer'}),
    );

    final HttpClientResponse response = await request.close();
    await response.drain<void>();

    return response.statusCode;
  } finally {
    client.close();
  }
}

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

/// Changes a restaurant behind the API's back.
///
/// There is no operator API yet — that is a later module — so the only honest
/// way to exercise "a suspension takes effect immediately" is to change the row
/// the way the restaurant dashboard eventually will.
Future<void> _setStatus(String name, String status) =>
    _update("UPDATE restaurants SET status = '$status' WHERE name = '$name';");

Future<void> _setAccepting(String name, bool accepting) => _update(
  'UPDATE restaurants SET is_accepting_orders = ${accepting ? 1 : 0} '
  "WHERE name = '$name';",
);

Future<void> _update(String sql) async {
  final ProcessResult result = await Process.run('mysql', <String>[
    '-N',
    '-B',
    'foodonthego_local',
    '-e',
    sql,
  ]);

  if (result.exitCode != 0) {
    throw StateError('could not update the fixture: ${result.stderr}');
  }
}
