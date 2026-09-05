// The Module 08 end-to-end run: search, filters, sorting and pagination
// against a running Laravel backend, real restaurant rows in MySQL, and the
// real route geometry Module 06 stored. No mocks, no fakes, no stubs.
//
// It picks up where the Module 07 run leaves off. That run proves which
// restaurants are on the route; this one proves that nothing a customer can
// type into a filter changes that set — only which part of it they see.
//
// Run it with the backend serving and OTP_PROVIDER=log:
//
//   php artisan serve --host=127.0.0.1 --port=8000
//   dart run --define=FOTG_API_BASE_URL=http://127.0.0.1:8000 \
//     tool/discovery_filters_smoke.dart
//
// WHAT THIS RUN CAN AND CANNOT ESTABLISH
//
// The search, every filter, the ordering, the facets, the validation, the
// pagination and the cost guarantee are all real here.
//
// The rating filter is not exercised against real data, because no restaurant
// has a rating: there is no reviews module. The run checks the honest
// behaviour instead — the server advertises the filter as unavailable and
// returns nothing rather than inventing a score to match against.
//
// The *detour* filter is only as discriminating as the configured routing
// provider. Against `ROUTE_PROVIDER=development` the road network is a
// straight line, so every in-corridor detour is a few seconds and a detour
// ceiling cannot exclude anything. The run says so rather than letting a
// reader assume it was tested; DiscoveryRefinerTest covers it with detours the
// test controls.

import 'dart:convert';
import 'dart:io';

import 'package:foodonthego/core/config/api_config.dart';
import 'package:foodonthego/core/network/api_error_code.dart';
import 'package:foodonthego/domain/models/discovered_restaurant.dart';
import 'package:foodonthego/domain/models/discovery_facets.dart';
import 'package:foodonthego/domain/models/discovery_query.dart';
import 'package:foodonthego/domain/models/place.dart';
import 'package:foodonthego/domain/models/trip.dart';

import 'support/smoke_support.dart';

const String _rahulPhone = '9999900801';

const String _near = '[TEST] Highway Spice Kitchen';
const String _further = '[TEST] Rajasthan Highway Bites';
const String _suspended = '[TEST] Suspended Dhaba';
const String _pending = '[TEST] Pending Restaurant';
const String _far = '[TEST] Far Away Kitchen';
const String _closed = '[TEST] Closed Route Cafe';
const String _behind = '[TEST] Behind You Diner';
const String _paused = '[TEST] Paused Highway Grill';

/// Everything Module 07 says is on this road. Nothing Module 08 does may add
/// to this list or subtract from it other than by hiding part of it.
const List<String> _eligible = <String>[
  _near,
  _further,
  _closed,
  _behind,
  _paused,
];

void main(List<String> args) async {
  stdout.writeln('FoodOnTheGo — Module 08 integration run');
  stdout.writeln('Backend: ${ApiConfig.baseUrl}');
  stdout.writeln('');

  await _seedFixtures();

  final Session rahul = await signIn('Rahul', 'Sharma', _rahulPhone);
  await discardEverything(rahul);

  final Trip trip = await _greenParkToJaipur(rahul);
  await rahul.routes.calculate(trip.id);

  Future<RestaurantDiscovery> ask([
    DiscoveryQuery query = DiscoveryQuery.unfiltered,
  ]) => rahul.discovery.discover(trip.id, query: query);

  Future<List<String>> names([
    DiscoveryQuery query = DiscoveryQuery.unfiltered,
  ]) async =>
      (await ask(query)).restaurants
          .map((DiscoveredRestaurant r) => r.name)
          .toList();

  // --- 1. the unfiltered baseline ------------------------------------------
  final RestaurantDiscovery all = await ask();
  final List<String> baseline = all.restaurants
      .map((DiscoveredRestaurant r) => r.name)
      .toList();

  check('Module 07 still returns the stops on this route', () {
    for (final String name in _eligible) {
      expectValue(baseline.contains(name), true);
    }
    expectValue(baseline.contains(_far), false);
  });

  check('the unfiltered page reports itself as unfiltered', () {
    expectValue(all.total, baseline.length);
    expectValue(all.eligibleTotal, baseline.length);
    expectValue(all.isFilteredEmpty, false);
  });

  // --- 2. eligibility is not negotiable ------------------------------------
  await checkAsync(
    'searching for a suspended restaurant finds nothing',
    () async {
      final RestaurantDiscovery found = await ask(
        const DiscoveryQuery(search: 'Suspended Dhaba'),
      );

      expectValue(found.restaurants.isEmpty, true);
      expectValue(found.total, 0);
    },
  );

  await checkAsync(
    'searching for an unverified restaurant finds nothing',
    () async {
      expectValue(
        (await names(const DiscoveryQuery(search: 'Pending Restaurant')))
            .isEmpty,
        true,
      );
    },
  );

  await checkAsync('searching beyond the corridor finds nothing', () async {
    expectValue(
      (await names(const DiscoveryQuery(search: 'Far Away Kitchen'))).isEmpty,
      true,
    );
  });

  await checkAsync(
    'no filter combination reaches an ineligible restaurant',
    () async {
      for (final DiscoveryQuery query in <DiscoveryQuery>[
        const DiscoveryQuery(cuisines: <String>{'north_indian'}),
        const DiscoveryQuery(cuisines: <String>{'south_indian'}),
        const DiscoveryQuery(facilities: <String>{'parking'}),
        const DiscoveryQuery(facilities: <String>{'restroom'}),
        const DiscoveryQuery(priceLevels: <int>{1, 2, 3, 4}),
        const DiscoveryQuery(availability: AvailabilityFilter.openNow),
        const DiscoveryQuery(sort: DiscoverySort.lowestDetour),
        const DiscoveryQuery(sort: DiscoverySort.priceLowToHigh),
        const DiscoveryQuery(search: 'restaurant'),
        const DiscoveryQuery(search: 'dhaba'),
        const DiscoveryQuery(search: 'kitchen', cuisines: <String>{'cafe'}),
      ]) {
        final List<String> found = await names(query);

        for (final String name in found) {
          // The set can only shrink. Anything in an answer that was not in the
          // unfiltered answer came from somewhere it should not have.
          expectValue(baseline.contains(name), true);
        }

        expectValue(found.contains(_suspended), false);
        expectValue(found.contains(_pending), false);
        expectValue(found.contains(_far), false);
      }
    },
  );

  await _resetRateLimiter();

  // --- 3. search ------------------------------------------------------------
  await checkAsync('a search by name finds the restaurant', () async {
    expectValue(
      _joined(await names(const DiscoveryQuery(search: 'spice'))),
      _near,
    );
  });

  await checkAsync('a search by cuisine finds what serves it', () async {
    final List<String> found = await names(
      const DiscoveryQuery(search: 'rajasthani'),
    );

    expectValue(found.contains(_further), true);
  });

  await checkAsync(
    'a search that matches nothing is an empty page, not an error',
    () async {
      final RestaurantDiscovery found = await ask(
        const DiscoveryQuery(search: 'sushi'),
      );

      expectValue(found.restaurants.isEmpty, true);
      expectValue(found.total, 0);
      // The distinction the empty screen turns on.
      expectValue(found.eligibleTotal, baseline.length);
      expectValue(found.isFilteredEmpty, true);
    },
  );

  await checkAsync('a search ignores case and punctuation', () async {
    expectValue(
      _joined(await names(const DiscoveryQuery(search: 'HIGHWAY  spice'))),
      _near,
    );
  });

  await _resetRateLimiter();

  // --- 4. filters -----------------------------------------------------------
  await checkAsync('a cuisine filter uses the slug', () async {
    final List<String> found = await names(
      const DiscoveryQuery(cuisines: <String>{'north_indian'}),
    );

    expectValue(found.contains(_near), true);
    expectValue(found.contains(_further), false);
  });

  await checkAsync('several cuisines are an OR', () async {
    final List<String> found = await names(
      const DiscoveryQuery(cuisines: <String>{'rajasthani', 'chinese'}),
    );

    expectValue(found.contains(_further), true);
    expectValue(found.contains(_paused), true);
    expectValue(found.contains(_near), false);
  });

  await checkAsync('several facilities are an AND', () async {
    final List<String> both = await names(
      const DiscoveryQuery(facilities: <String>{'parking', 'restroom'}),
    );
    final List<String> one = await names(
      const DiscoveryQuery(facilities: <String>{'parking'}),
    );

    // Rajasthan Highway Bites has parking and no restroom, so it is in the
    // second answer and must not be in the first.
    expectValue(one.contains(_further), true);
    expectValue(both.contains(_further), false);
    expectValue(both.contains(_near), true);
  });

  await checkAsync('filters of different kinds are an AND', () async {
    final List<String> found = await names(
      const DiscoveryQuery(
        cuisines: <String>{'north_indian'},
        facilities: <String>{'seating'},
      ),
    );

    expectValue(_joined(found), _near);
  });

  await checkAsync('open now and taking orders are different questions', () async {
    final List<String> open = await names(
      const DiscoveryQuery(availability: AvailabilityFilter.openNow),
    );
    final List<String> ordering = await names(
      const DiscoveryQuery(availability: AvailabilityFilter.acceptingOrders),
    );

    // The paused grill is open — the lights are on — and cannot take an order.
    // Collapsing the two would send somebody to a counter that cannot serve.
    expectValue(open.contains(_paused), true);
    expectValue(ordering.contains(_paused), false);
    expectValue(open.contains(_closed), false);
  });

  await checkAsync('a price filter keeps only the levels asked for', () async {
    expectValue(
      _joined(await names(const DiscoveryQuery(priceLevels: <int>{1}))),
      _further,
    );
    expectValue(
      (await names(const DiscoveryQuery(priceLevels: <int>{3})))
          .contains(_closed),
      true,
    );
  });

  await checkAsync(
    'a rating filter matches nothing while nothing is rated',
    () async {
      final RestaurantDiscovery found = await ask(
        const DiscoveryQuery(minRating: 4),
      );

      // Honest rather than convenient. Inventing a 4.5 to make the filter look
      // functional is the exact fabrication this module forbids.
      expectValue(found.restaurants.isEmpty, true);
      expectValue(found.facets.ratingAvailable, false);
    },
  );

  await _resetRateLimiter();

  // --- 5. sorting -----------------------------------------------------------
  await checkAsync('journey order is journey order', () async {
    final List<DiscoveredRestaurant> found = (await ask(
      const DiscoveryQuery(sort: DiscoverySort.soonestAlongRoute),
    )).restaurants;

    final List<int> ahead = found
        .where((DiscoveredRestaurant r) => !r.route.requiresBacktracking)
        .map((DiscoveredRestaurant r) => r.route.distanceAheadMetres)
        .toList();

    for (int i = 1; i < ahead.length; i++) {
      expectValue(ahead[i] >= ahead[i - 1], true);
    }
  });

  await checkAsync('price low to high is exactly that', () async {
    final List<DiscoveredRestaurant> found = (await ask(
      const DiscoveryQuery(sort: DiscoverySort.priceLowToHigh),
    )).restaurants;

    final List<int> levels = found
        .where((DiscoveredRestaurant r) => !r.route.requiresBacktracking)
        .map((DiscoveredRestaurant r) => r.priceLevel ?? 5)
        .toList();

    for (int i = 1; i < levels.length; i++) {
      expectValue(levels[i] >= levels[i - 1], true);
    }
  });

  await checkAsync(
    'a stop behind the customer is never first, in any order',
    () async {
      // Backtracking is a tie-break, not an override. A customer who asked
      // for cheapest-first gets cheapest-first, so a cheap stop behind them
      // can sit above a pricier one ahead — labelled "Behind you" on its own
      // card. What it must never be is the answer to "where should I stop?",
      // which is the top of the list.
      for (final DiscoverySort sort in <DiscoverySort>[
        DiscoverySort.recommended,
        DiscoverySort.lowestDetour,
        DiscoverySort.soonestAlongRoute,
        DiscoverySort.priceLowToHigh,
      ]) {
        expectValue(
          (await names(DiscoveryQuery(sort: sort))).first == _behind,
          false,
        );
      }

      // In the orders that are about the journey rather than the menu, it
      // goes last outright.
      for (final DiscoverySort sort in <DiscoverySort>[
        DiscoverySort.recommended,
        DiscoverySort.lowestDetour,
        DiscoverySort.soonestAlongRoute,
      ]) {
        expectValue((await names(DiscoveryQuery(sort: sort))).last, _behind);
      }
    },
  );

  await _resetRateLimiter();

  // --- 6. facets ------------------------------------------------------------
  await checkAsync('the options offered are the ones this route has', () async {
    final DiscoveryFacets facets = (await ask()).facets;

    final List<String> cuisines = facets.cuisines
        .map((FilterOption o) => o.slug)
        .toList();

    expectValue(cuisines.contains('north_indian'), true);
    expectValue(cuisines.contains('rajasthani'), true);
    // On the road but suspended, so its cuisine is not on offer either.
    expectValue(cuisines.contains('south_indian'), false);

    expectValue(facets.ratingAvailable, false);

    final SortOption? rated = facets.optionFor(DiscoverySort.highestRated);
    expectValue(rated != null, true);
    expectValue(rated!.isAvailable, false);
    expectValue(rated.unavailableReason != null, true);
  });

  await _resetRateLimiter();

  // --- 7. pagination --------------------------------------------------------
  await checkAsync('a page is a page, and it says where it is', () async {
    final RestaurantDiscovery first = await ask(
      const DiscoveryQuery(sort: DiscoverySort.soonestAlongRoute),
    );

    expectValue(first.page, 1);
    expectValue(first.total, baseline.length);

    // Asked for one at a time through the raw query, since the client's own
    // per-page is fixed by configuration.
    final Map<String, dynamic> page2 = await _rawJson(
      rahul,
      trip.id,
      'per_page=2&page=2&sort=soonest_along_route',
    );

    final Map<String, dynamic> meta =
        (page2['data'] as Map<String, dynamic>)['meta'] as Map<String, dynamic>;

    expectValue(meta['page'], 2);
    expectValue(meta['per_page'], 2);
    expectValue(meta['total'], baseline.length);
    expectValue(meta['has_more'], baseline.length > 4);
  });

  await _resetRateLimiter();

  // --- 8. validation --------------------------------------------------------
  await checkAsync(
    'a malformed filter is refused, and says which one',
    () async {
      for (final MapEntry<String, String> bad in <String, String>{
        'cuisines': 'North Indian',
        'facilities': "parking'; DROP TABLE restaurants; --",
        'price_levels': '9',
        'availability': 'whenever',
        'min_rating': '11',
        'sort': 'commission_rate desc',
        'per_page': '0',
        'max_detour_seconds': '-500',
      }.entries) {
        final Map<String, dynamic> body = await _rawJson(
          rahul,
          trip.id,
          '${bad.key}=${Uri.encodeQueryComponent(bad.value)}',
        );

        final Map<String, dynamic> error =
            body['error'] as Map<String, dynamic>;

        expectValue(error['code'], 'VALIDATION_FAILED');

        final Map<String, dynamic> fields =
            (error['details'] as Map<String, dynamic>)['fields']
                as Map<String, dynamic>;

        // Named, so a client bug is findable rather than presenting as an
        // inexplicably unfiltered list.
        expectValue(fields.containsKey(bad.key), true);
      }
    },
  );

  await checkAsync(
    'a sort that exists but cannot work yet is refused',
    () async {
      final Map<String, dynamic> body = await _rawJson(
        rahul,
        trip.id,
        'sort=highest_rated',
      );

      // Not silently downgraded to recommended: a client asking to sort by a
      // rating nothing has needs to know it did not happen.
      expectValue(
        (body['error'] as Map<String, dynamic>)['code'],
        'VALIDATION_FAILED',
      );
    },
  );

  await checkAsync('an injection string changes nothing', () async {
    final Map<String, dynamic> body = await _rawJson(
      rahul,
      trip.id,
      'search=${Uri.encodeQueryComponent("'; DROP TABLE restaurants; --")}',
    );

    final Map<String, dynamic> data = body['data'] as Map<String, dynamic>;

    expectValue((data['restaurants'] as List<dynamic>).isEmpty, true);

    // And the table is still there, because the next call still works.
    expectValue((await names()).length, baseline.length);
  });

  await _resetRateLimiter();

  // --- 9. cost --------------------------------------------------------------
  await checkAsync(
    'changing a filter never re-runs the expensive search',
    () async {
      // The first call warms the corridor; every one after it must be served
      // from that cache however the customer refines it.
      await ask();

      for (final DiscoveryQuery query in <DiscoveryQuery>[
        const DiscoveryQuery(cuisines: <String>{'north_indian'}),
        const DiscoveryQuery(facilities: <String>{'parking'}),
        const DiscoveryQuery(priceLevels: <int>{1}),
        const DiscoveryQuery(availability: AvailabilityFilter.openNow),
        const DiscoveryQuery(sort: DiscoverySort.lowestDetour),
        const DiscoveryQuery(search: 'spice'),
        const DiscoveryQuery(page: 2),
      ]) {
        expectValue((await ask(query)).fromCache, true);
      }
    },
  );

  await checkAsync(
    'a filter cannot keep a suspended restaurant visible',
    () async {
      await _setStatus(_near, 'SUSPENDED');

      try {
        // Even with a warm cache, and even with a filter that names it exactly.
        expectValue(
          (await names(const DiscoveryQuery(search: 'Highway Spice'))).isEmpty,
          true,
        );
        expectValue(
          (await names(
            const DiscoveryQuery(cuisines: <String>{'north_indian'}),
          )).contains(_near),
          false,
        );
      } finally {
        await _setStatus(_near, 'APPROVED');
      }
    },
  );

  await _resetRateLimiter();

  // --- 10. ownership --------------------------------------------------------
  await expectRefused(
    'a filtered call on a foreign trip is still not found',
    () => rahul.discovery.discover(
      '00000000-0000-4000-8000-000000000000',
      query: const DiscoveryQuery(search: 'spice'),
    ),
    ApiErrorCode.tripNotFound,
  );

  // --- what this run actually produced --------------------------------------
  stdout.writeln('');
  stdout.writeln('  ── what this route offered ──');
  stdout.writeln('     eligible stops : ${baseline.length}');
  stdout.writeln(
    '     cuisines       : '
    '${all.facets.cuisines.map((FilterOption o) => "${o.slug}(${o.count})").join(", ")}',
  );
  stdout.writeln(
    '     facilities     : '
    '${all.facets.facilities.map((FilterOption o) => "${o.slug}(${o.count})").join(", ")}',
  );
  stdout.writeln(
    '     price levels   : '
    '${all.facets.priceLevels.map((PriceOption o) => "${o.level}(${o.count})").join(", ")}',
  );
  stdout.writeln('     rating filter  : ${all.facets.ratingAvailable}');
  stdout.writeln('     detour ceiling : ${all.facets.maxDetourSeconds}s');

  if (!all.isFromRealProvider) {
    stdout.writeln('');
    stdout.writeln(
      '  NOTE  Detour-ceiling exclusion = NOT APPLICABLE for this run — the\n'
      '        configured provider models the road network as a straight line,\n'
      '        so no in-corridor stop can exceed any ceiling this filter can\n'
      '        set. Covered by DiscoveryRefinerTest with controlled detours.',
    );
    stdout.writeln(
      '  NOTE  Rating filter = NOT APPLICABLE — no restaurant has a rating,\n'
      '        because there is no reviews module. The server advertises the\n'
      '        filter as unavailable rather than matching against nothing.',
    );
  }

  rahul.close();

  stdout.writeln('');
  stdout.writeln('$passed passed, $failed failed');

  exit(failed == 0 ? 0 : 1);
}

/// A list as one comparable string, because `expectValue` compares by identity
/// and two equal lists are not the same object.
String _joined(List<String> values) => values.join(' | ');

/// Clears the per-minute request buckets, without clearing the discovery cache.
///
/// This run deliberately makes far more discovery calls in a minute than any
/// customer would — it is walking every filter, every sort and every rejection
/// in one pass — so it would meet the rate limit part way through and stop
/// testing what it came to test. The limiter itself is not skipped: it is
/// asserted directly, at its configured value, by
/// `TripRestaurantApiTest::test_the_endpoint_is_rate_limited` and by
/// `TripRestaurantFilterApiTest::test_a_filtered_call_is_rate_limited_like_any_other`.
///
/// Only the limiter's own buckets go — the hashed keys Laravel's RateLimiter
/// writes. The named `discovery:result:` and `discovery:detour:` entries stay,
/// which is what lets the cost assertions below still mean something.
Future<void> _resetRateLimiter() async {
  const String prefix = 'foodonthego-database-foodonthego-cache-';

  final ProcessResult keys = await Process.run('redis-cli', <String>[
    '-n',
    '1',
    'KEYS',
    '$prefix*',
  ]);

  final RegExp bucket = RegExp('^$prefix[0-9a-f]{32}(:timer)?\$');

  final List<String> doomed = (keys.stdout as String)
      .split('\n')
      .map((String line) => line.trim())
      .where(bucket.hasMatch)
      .toList();

  if (doomed.isEmpty) return;

  await Process.run('redis-cli', <String>['-n', '1', 'DEL', ...doomed]);
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

/// The raw decoded body, for assertions the typed client cannot make — a
/// validation envelope, or a page size the client does not expose.
Future<Map<String, dynamic>> _rawJson(
  Session session,
  String tripId,
  String query,
) async {
  final HttpClient client = HttpClient();

  try {
    final HttpClientRequest request = await client.getUrl(
      Uri.parse(
        '${ApiConfig.baseUrl}/api/v1/customer/trips/$tripId/restaurants?$query',
      ),
    );

    request.headers.set('Authorization', 'Bearer ${session.token}');
    request.headers.set('Accept', 'application/json');

    final HttpClientResponse response = await request.close();
    final String body = await response
        .transform(const SystemEncoding().decoder)
        .join();

    return jsonDecode(body) as Map<String, dynamic>;
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
