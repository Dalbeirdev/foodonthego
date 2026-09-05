// The Module 10 end-to-end run: this app's own network layer against a running
// Laravel backend, real menu rows in MySQL, and the real route geometry Module
// 06 stored. No mocks, no fakes, no stubs.
//
// It walks the module's own example — Rahul plans Green Park -> Jaipur airport,
// discovers what is on the road, opens one of the results and reads its menu —
// then checks the things this module turns on: that money survives the round
// trip as integer minor units, that a withdrawn category or item is unreachable
// by any route, that one restaurant's item cannot be read through another, and
// that opening a menu calls no routing provider.
//
// Run it with the backend serving and OTP_PROVIDER=log:
//
//   php artisan serve --host=127.0.0.1 --port=8000
//   dart run --define=FOTG_API_BASE_URL=http://127.0.0.1:8000 \
//     tool/menu_smoke.dart
//
// WHAT THIS RUN CAN AND CANNOT ESTABLISH
//
// The menu projection, the money representation, the visibility rules, the
// time-limited category, the cross-restaurant refusal, the ownership boundary
// and the read-only surface are all real here — real rows, real HTTP, real
// authentication.
//
// Allergen information is not exercised, because there is no allergen field: no
// restaurant has declared any, and inventing a column to demonstrate would be
// the fabrication this module forbids. The honest behaviour is asserted
// instead — nothing on the wire claims an allergen.
//
// The item preview is read-only by construction: there is no write endpoint to
// call. The run proves that by calling the ones a modified client would try.

import 'dart:convert';
import 'dart:io';

import 'package:foodonthego/core/config/api_config.dart';
import 'package:foodonthego/core/network/api_error_code.dart';
import 'package:foodonthego/core/network/api_exception.dart';
import 'package:foodonthego/domain/models/discovered_restaurant.dart';
import 'package:foodonthego/domain/models/place.dart';
import 'package:foodonthego/domain/models/restaurant_detail.dart';
import 'package:foodonthego/domain/models/restaurant_menu.dart';
import 'package:foodonthego/domain/models/trip.dart';

import 'support/smoke_support.dart';

const String _rahulPhone = '9999900901';
const String _ananyaPhone = '9999900902';

const String _spice = '[TEST] Highway Spice Kitchen';
const String _bites = '[TEST] Rajasthan Highway Bites';
const String _bare = '[TEST] Bare Bones Stop';
const String _paused = '[TEST] Paused Highway Grill';
const String _closed = '[TEST] Closed Route Cafe';

void main(List<String> args) async {
  stdout.writeln('FoodOnTheGo — Module 10 integration run');
  stdout.writeln('Backend: ${ApiConfig.baseUrl}');
  stdout.writeln('');

  await _seedFixtures();

  final Session rahul = await signIn('Rahul', 'Sharma', _rahulPhone);
  final Session ananya = await signIn('Ananya', 'Mehta', _ananyaPhone);

  await discardEverything(rahul);
  await discardEverything(ananya);

  final Trip trip = await _greenParkToJaipur(rahul);
  await rahul.routes.calculate(trip.id);

  final RestaurantDiscovery found = await rahul.discovery.discover(trip.id);

  final Map<String, DiscoveredRestaurant> byName =
      <String, DiscoveredRestaurant>{
        for (final DiscoveredRestaurant r in found.restaurants) r.name: r,
      };

  check('the restaurants this module needs are on the route', () {
    for (final String name in <String>[_spice, _bites, _bare, _paused, _closed]) {
      expectValue(byName.containsKey(name), true);
    }
  });

  final DiscoveredRestaurant card = byName[_spice]!;

  // --- 1. the menu itself --------------------------------------------------
  final RestaurantMenu menu = await rahul.menus.menu(
    tripId: trip.id,
    restaurantId: card.id,
  );

  check('the menu belongs to the restaurant that was opened', () {
    expectValue(menu.restaurant.id, card.id);
    expectValue(menu.restaurant.name, _spice);
  });

  final Map<String, MenuCategory> sections = <String, MenuCategory>{
    for (final MenuCategory c in menu.categories) c.name: c,
  };

  final Map<String, MenuItem> items = <String, MenuItem>{
    for (final MenuItem i in menu.allItems) i.name: i,
  };

  check('the sections come back in the order the operator set', () {
    final List<String> names = menu.categories
        .map((MenuCategory c) => c.name)
        .toList();

    expectValue(names.contains('Starters'), true);
    expectValue(names.contains('Main Course'), true);
    expectValue(
      names.indexOf('Starters') < names.indexOf('Main Course'),
      true,
    );
  });

  check('a dish carries what the restaurant published', () {
    final MenuItem paneer = items['Paneer Tikka']!;

    expectValue(paneer.price.amountMinor, 24900);
    expectValue(paneer.price.currency, 'INR');
    expectValue(paneer.preparationMinutes, 15);
    expectValue(paneer.dietaryType, MenuItemDietaryType.vegetarian);
    expectValue(paneer.spiceLevel, 2);
    expectValue(paneer.hasDescription, true);
  });

  check('a dish with nothing optional carries nothing optional', () {
    // Papad. No description, no photograph, no preparation time, no declared
    // diet. Four parts of the card must omit themselves rather than fill in.
    final MenuItem papad = items['Papad']!;

    expectValue(papad.description, null);
    expectValue(papad.listImageUrl, null);
    expectValue(papad.preparationMinutes, null);
    expectValue(papad.dietaryType, MenuItemDietaryType.unknown);
    expectValue(papad.spiceLevel, null);
  });

  // --- 2. money ------------------------------------------------------------
  check('every price is integer minor units with its currency', () {
    for (final MenuItem item in menu.allItems) {
      expectValue(item.price.currency, 'INR');
      expectValue(item.price.amountMinor >= 0, true);
    }
  });

  check('a free item is zero, not missing', () {
    final MenuItem water = items['Table Water']!;

    expectValue(water.price.amountMinor, 0);
    expectValue(water.price.isZero, true);
    // A formatter that treated zero as "no price" would print nothing at all.
    expectValue(water.price.format(locale: 'en_IN'), '₹0');
  });

  check('a five-figure price groups the way the locale does', () {
    final MenuItem hamper = items['Celebration Hamper']!;

    expectValue(hamper.price.amountMinor, 1299900);
    // Indian grouping: 12,999 rather than 12999.
    expectValue(hamper.price.format(locale: 'en_IN'), '₹12,999');
  });

  await checkAsync('the wire carries no rendered price string', () async {
    final Map<String, dynamic> raw = await _raw(
      rahul,
      '/customer/trips/${trip.id}/restaurants/${card.id}/menu',
    );

    final String body = jsonEncode(raw);

    // A server-rendered "₹249" would decide the customer's locale for them.
    expectValue(body.contains('₹'), false);
    expectValue(body.contains('"amount_minor"'), true);
  });

  // --- 3. what is not on the menu ------------------------------------------
  check('a withdrawn item is absent', () {
    expectValue(items.containsKey('Discontinued Kebab'), false);
  });

  check('a withdrawn category takes its items with it', () {
    expectValue(sections.containsKey('Desserts'), false);
    // Live, and inside a category that is not. Unreachable either way.
    expectValue(items.containsKey('Gulab Jamun'), false);
  });

  check('a section outside its serving hours is absent', () {
    final DateTime now = DateTime.now();
    final bool breakfastTime = now.hour >= 6 && now.hour < 11;

    // Breakfast is served 06:00-11:00. Present or absent depending on the
    // clock, and never half-shown.
    expectValue(sections.containsKey('Breakfast'), breakfastTime);
  });

  check('a sold-out dish is present and marked', () {
    final MenuItem mushroom = items['Tandoori Mushroom']!;

    // Shown, so a traveller learns the kitchen has run out rather than
    // concluding they misremembered the menu.
    expectValue(mushroom.isSoldOut, true);
    expectValue(mushroom.isOrderable, false);
  });

  // --- 4. searching --------------------------------------------------------
  await checkAsync('a search narrows the menu', () async {
    final RestaurantMenu paneer = await rahul.menus.menu(
      tripId: trip.id,
      restaurantId: card.id,
      search: 'paneer',
    );

    expectValue(paneer.hasItems, true);
    expectValue(paneer.appliedSearch, 'paneer');

    for (final MenuItem item in paneer.allItems) {
      final bool matches =
          item.name.toLowerCase().contains('paneer') ||
          (item.description ?? '').toLowerCase().contains('paneer');

      expectValue(matches, true);
    }
  });

  await checkAsync('an empty search result is not an empty menu', () async {
    final RestaurantMenu none = await rahul.menus.menu(
      tripId: trip.id,
      restaurantId: card.id,
      search: 'sushi',
    );

    // Two different problems with two different answers: clear the box, or
    // go back to the list.
    expectValue(none.isSearchEmpty, true);
    expectValue(none.isMenuEmpty, false);
    expectValue(none.visibleItemCount > 0, true);
  });

  await checkAsync('a search cannot reach a withdrawn item', () async {
    final RestaurantMenu kebab = await rahul.menus.menu(
      tripId: trip.id,
      restaurantId: card.id,
      search: 'Discontinued',
    );

    expectValue(kebab.hasItems, false);
  });

  await checkAsync('an injection string is a search term and nothing more', () async {
    for (final String probe in <String>[
      "' OR '1'='1",
      "'; DROP TABLE menu_items; --",
      '<script>alert(1)</script>',
      'UNION SELECT uuid FROM menu_items',
    ]) {
      final RestaurantMenu result = await rahul.menus.menu(
        tripId: trip.id,
        restaurantId: card.id,
        search: probe,
      );

      // Matched against dish names in memory, where there is no query for it
      // to become part of. An injection that ran would return something
      // stranger than nothing.
      expectValue(result.hasItems, false);
      expectValue(result.appliedSearch, probe);
    }

    // And the table is still there.
    final RestaurantMenu after = await rahul.menus.menu(
      tripId: trip.id,
      restaurantId: card.id,
    );

    expectValue(after.hasItems, true);
  });

  await checkAsync('a punctuation-only search is not reported as a search', () async {
    for (final String probe in <String>['%%', '__', '...', '@@']) {
      final RestaurantMenu result = await rahul.menus.menu(
        tripId: trip.id,
        restaurantId: card.id,
        search: probe,
      );

      // The matcher folds punctuation away, so such a term matches everything.
      // Returning the whole menu is right; labelling it the result for "%%"
      // would be a claim the customer reads as "these all match".
      expectValue(result.hasItems, true);
      expectValue(result.appliedSearch, null);
      expectValue(result.isSearchEmpty, false);
    }
  });

  await expectRefused(
    'an oversized search is refused rather than truncated',
    () => rahul.menus.menu(
      tripId: trip.id,
      restaurantId: card.id,
      search: 'a' * 5000,
    ),
    ApiErrorCode.validationFailed,
  );

  // --- 5. one item ---------------------------------------------------------
  final MenuItem paneer = items['Paneer Tikka']!;

  await checkAsync('one item can be read on its own', () async {
    final MenuItemPreview preview = await rahul.menus.item(
      tripId: trip.id,
      restaurantId: card.id,
      itemId: paneer.id,
    );

    expectValue(preview.item.id, paneer.id);
    expectValue(preview.item.price.amountMinor, paneer.price.amountMinor);
    expectValue(preview.categoryName, 'Starters');
    expectValue(preview.restaurant.id, card.id);
  });

  await checkAsync('the preview reflects a price that has since changed', () async {
    await _setPrice('Paneer Tikka', 27_900);

    try {
      final MenuItemPreview preview = await rahul.menus.item(
        tripId: trip.id,
        restaurantId: card.id,
        itemId: paneer.id,
      );

      // The customer may have had the menu open for ten minutes. Echoing the
      // payload it was opened from would quote a price the kitchen has left.
      expectValue(preview.item.price.amountMinor, 27900);
    } finally {
      await _setPrice('Paneer Tikka', 24_900);
    }
  });

  // --- 6. what a known id does not buy -------------------------------------
  final RestaurantMenu bitesMenu = await rahul.menus.menu(
    tripId: trip.id,
    restaurantId: byName[_bites]!.id,
  );

  final MenuItem kachori = bitesMenu.allItems.firstWhere(
    (MenuItem i) => i.name == 'Pyaaz Kachori',
  );

  await expectRefused(
    "another restaurant's item cannot be read through this one",
    () => rahul.menus.item(
      tripId: trip.id,
      restaurantId: card.id,
      itemId: kachori.id,
    ),
    ApiErrorCode.itemNotFound,
  );

  await expectRefused(
    'an item in a withdrawn category is not reachable by id',
    () async {
      final String gulab = await _uuidOf('Gulab Jamun');

      return rahul.menus.item(
        tripId: trip.id,
        restaurantId: card.id,
        itemId: gulab,
      );
    },
    ApiErrorCode.itemNotFound,
  );

  await expectRefused(
    'a withdrawn item is not reachable by id',
    () async {
      final String kebab = await _uuidOf('Discontinued Kebab');

      return rahul.menus.item(
        tripId: trip.id,
        restaurantId: card.id,
        itemId: kebab,
      );
    },
    ApiErrorCode.itemNotFound,
  );

  await expectRefused(
    "another customer's trip does not open this menu",
    () => ananya.menus.menu(tripId: trip.id, restaurantId: card.id),
    ApiErrorCode.tripNotFound,
  );

  await checkAsync('a suspended restaurant will not serve a menu to a known id', () async {
    await _setStatus(_spice, 'SUSPENDED');
    await _flushCache();

    try {
      await rahul.menus.menu(tripId: trip.id, restaurantId: card.id);

      throw 'the menu was served';
    } on ApiException catch (error) {
      // 404, exactly as a restaurant that never existed answers. The status is
      // what a prober with a list of uuids sees, and it does not tell them
      // which businesses this platform has suspended.
      expectValue(error.status, 404);
      expectValue(error.code, ApiErrorCode.restaurantUnavailable);
    } finally {
      await _setStatus(_spice, 'APPROVED');
      // The corridor result was cached while the restaurant was suspended.
      // Left in place it would keep the rest of this run looking at a route
      // the restaurant is no longer on.
      await _flushCache();
    }
  });

  // --- 7. the empty menu ---------------------------------------------------
  await checkAsync('a restaurant with no menu says so, rather than failing', () async {
    final RestaurantMenu nothing = await rahul.menus.menu(
      tripId: trip.id,
      restaurantId: byName[_bare]!.id,
    );

    expectValue(nothing.isMenuEmpty, true);
    expectValue(nothing.categories.isEmpty, true);
  });

  // --- 8. a closed kitchen still has a menu --------------------------------
  await checkAsync('a closed restaurant still serves its menu', () async {
    final RestaurantDetail cafe = await rahul.restaurants.detail(
      tripId: trip.id,
      restaurantId: byName[_closed]!.id,
    );

    expectValue(cafe.canOrder, false);

    final RestaurantMenu closedMenu = await rahul.menus.menu(
      tripId: trip.id,
      restaurantId: byName[_closed]!.id,
    );

    // Browsing stays open: a customer planning tomorrow's drive has a good
    // reason to read tonight's menu.
    expectValue(closedMenu.restaurant.canOrder, false);
    expectValue(closedMenu.restaurant.canBrowseMenu, true);
  });

  // --- 9. what a customer must never see -----------------------------------
  await checkAsync('no operator-private field is on the wire', () async {
    final Map<String, dynamic> raw = await _raw(
      rahul,
      '/customer/trips/${trip.id}/restaurants/${card.id}/menu',
    );

    final String body = jsonEncode(raw).toLowerCase();

    for (final String forbidden in <String>[
      'cost_price',
      'margin',
      'vendor',
      'supplier',
      'recipe',
      'internal_note',
      'staff_note',
      'stock_quantity',
      'commission',
      'gst_number',
      'owner_',
      'created_by',
    ]) {
      expectValue(body.contains(forbidden), false);
    }

    // Nothing claims an allergen, because no restaurant has declared one.
    expectValue(body.contains('allergen'), false);
  });

  await checkAsync('no internal database key is exposed', () async {
    final Map<String, dynamic> raw = await _raw(
      rahul,
      '/customer/trips/${trip.id}/restaurants/${card.id}/menu',
    );

    final List<Object?> categories = raw['categories'] as List<Object?>;

    for (final Object? category in categories) {
      final Map<String, dynamic> c = category as Map<String, dynamic>;

      // The uuid, never the auto-increment key: a sequential id tells anybody
      // who asks how many menus this platform holds.
      expectValue(c['id'] is String, true);
      expectValue((c['id'] as String).length, 36);
      expectValue(c.containsKey('restaurant_id'), false);
      expectValue(c.containsKey('menu_category_id'), false);

      for (final Object? item in c['items'] as List<Object?>) {
        final Map<String, dynamic> i = item as Map<String, dynamic>;

        expectValue((i['id'] as String).length, 36);
        expectValue(i.containsKey('base_price_minor'), false);
      }
    }
  });

  // --- 10. read-only -------------------------------------------------------
  await checkAsync('a customer has no way to change a menu', () async {
    final String base =
        '/api/v1/customer/trips/${trip.id}/restaurants/${card.id}/menu';

    for (final (String method, String path) in <(String, String)>[
      ('POST', base),
      ('PATCH', '$base/items/${paneer.id}'),
      ('PUT', '$base/items/${paneer.id}'),
      ('DELETE', '$base/items/${paneer.id}'),
      ('POST', '$base/items'),
      ('POST', '$base/items/${paneer.id}/image'),
    ]) {
      final int status = await _statusOf(rahul, method, path);

      // 405 or 404 — never 2xx. There is no write endpoint to reach.
      expectValue(status >= 400, true);
    }
  });

  // --- 11. cost control ----------------------------------------------------
  await checkAsync('opening a menu asks no routing provider', () async {
    final int before = await _providerCalls();

    for (int i = 0; i < 5; i++) {
      await rahul.menus.menu(tripId: trip.id, restaurantId: card.id);
      await rahul.menus.menu(
        tripId: trip.id,
        restaurantId: card.id,
        search: 'paneer',
      );
      await rahul.menus.item(
        tripId: trip.id,
        restaurantId: card.id,
        itemId: paneer.id,
      );
    }

    // The mandatory one. A menu is opened, searched and backed out of dozens
    // of times in a single journey; a billed call on any of those would make
    // the screen cost more than the order.
    expectValue(await _providerCalls(), before);
  });

  rahul.close();
  ananya.close();

  stdout.writeln('');
  stdout.writeln('$passed passed, $failed failed');

  exit(failed == 0 ? 0 : 1);
}

// --- fixtures and plumbing --------------------------------------------------

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

/// Empties the discovery cache.
///
/// Needed only because this run changes rows behind the API's back: a corridor
/// result computed while a restaurant was suspended outlives the suspension.
Future<void> _flushCache() async {
  final ProcessResult result = await Process.run('php', <String>[
    'artisan',
    'cache:clear',
  ], workingDirectory: '../backend');

  if (result.exitCode != 0) {
    throw StateError('could not clear the cache: ${result.stderr}');
  }
}

Future<Map<String, dynamic>> _raw(Session session, String path) =>
    session.client.get(path, authenticated: true);

/// The status of a request the customer API should not accept at all.
///
/// Sent with a body a modified client would send, so a route that existed but
/// ignored the payload would still be caught.
Future<int> _statusOf(Session session, String method, String path) async {
  final HttpClient client = HttpClient();

  try {
    final HttpClientRequest request = await client.openUrl(
      method,
      Uri.parse('${ApiConfig.baseUrl}$path'),
    );

    request.headers.set('Authorization', 'Bearer ${session.token}');
    request.headers.set('Accept', 'application/json');
    request.headers.contentType = ContentType.json;
    request.write(
      jsonEncode(<String, Object>{
        'name': 'Renamed By A Customer',
        'base_price_minor': 1,
        'stock_status': 'IN_STOCK',
      }),
    );

    final HttpClientResponse response = await request.close();
    await response.drain<void>();

    return response.statusCode;
  } finally {
    client.close();
  }
}

Future<void> _seedFixtures() async {
  for (final String seeder in <String>[
    'DiscoveryTestRestaurantSeeder',
    'MenuTestDataSeeder',
  ]) {
    final ProcessResult result = await Process.run('php', <String>[
      'artisan',
      'db:seed',
      '--class=$seeder',
      '--force',
    ], workingDirectory: '../backend');

    if (result.exitCode != 0) {
      throw StateError('could not seed $seeder: ${result.stderr}');
    }
  }
}

/// How many times the routing provider has been called.
///
/// Read from the log the development provider writes, which is the only
/// honest count available without an operator API.
Future<int> _providerCalls() async {
  final File log = File('../backend/storage/logs/laravel.log');

  if (!log.existsSync()) return 0;

  return 'route.provider.called'.allMatches(log.readAsStringSync()).length;
}

Future<String> _uuidOf(String itemName) async {
  final String uuid = await _query(
    "SELECT uuid FROM menu_items WHERE name = '$itemName' LIMIT 1;",
  );

  if (uuid.isEmpty) throw StateError('no menu item named $itemName');

  return uuid;
}

Future<void> _setPrice(String itemName, int minor) => _update(
  "UPDATE menu_items SET base_price_minor = $minor WHERE name = '$itemName';",
);

/// Changes a restaurant behind the API's back.
///
/// There is no operator API yet — that is a later module — so the only honest
/// way to exercise "a suspension takes effect immediately" is to change the row
/// the way the restaurant dashboard eventually will.
Future<void> _setStatus(String name, String status) =>
    _update("UPDATE restaurants SET status = '$status' WHERE name = '$name';");

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

Future<String> _query(String sql) async {
  final ProcessResult result = await Process.run('mysql', <String>[
    '-N',
    '-B',
    'foodonthego_local',
    '-e',
    sql,
  ]);

  if (result.exitCode != 0) {
    throw StateError('could not read the fixture: ${result.stderr}');
  }

  return (result.stdout as String).trim();
}
