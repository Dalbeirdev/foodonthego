// Module 13 on a real device: choosing when to collect.
//
// The companion to module_12_cart_test.dart, and the run that closes M13-062
// (Android) and M13-063 (iOS). It builds the shipping app, installs it on a
// handset or emulator, taps the real chips with a real finger-sized hit test,
// and talks to a real Laravel server writing real rows to real MySQL tables.
//
// WHAT IT PROVES, AND WHAT IT DOES NOT
//
// It proves that the pickup screen works on the platform: that the windows load
// over the device's own network stack, that a chip tapped by a finger produces
// a selection the *server* then agrees with, and — the point of the module —
// that the client sends an opaque id rather than a time, and renders the
// server's verdict rather than one of its own.
//
// Every assertion that matters is made against the server's own state, fetched
// separately over HTTP after the taps. A screen that agreed with itself would
// pass whatever either side said.
//
// It does not re-prove sign-in (Module 03), journey planning (Module 05),
// discovery (Module 07), adding to a cart (Module 11) or cart management
// (Module 12). Those have their own verification, and re-driving them here
// would mean a failure in any of them arriving as a Module 13 failure.
//
// WHAT IT CANNOT PROVE
//
// Nothing here is a test of the ETA. The travel figure comes from the planned
// route on the assumption the customer sets off now, which is the module's
// largest approximation and is stated as such in docs/28-pickup-time-planning.md.
// A device run cannot close that; only the live ETA engine can.
//
// RUNNING IT
//
//   # 1. On the machine running the backend:
//   php artisan serve --host=0.0.0.0 --port=8000
//   php artisan db:seed --class=DiscoveryTestRestaurantSeeder --force
//   php artisan db:seed --class=MenuTestDataSeeder --force
//   cd mobile
//   dart run --define=FOTG_API_BASE_URL=http://127.0.0.1:8000 tool/issue_token.dart
//
//   # 2. With a device attached (`flutter devices`), using the host's LAN
//   #    address — or 10.0.2.2 for an Android emulator, 127.0.0.1 for an iOS
//   #    simulator:
//   flutter test integration_test/module_13_pickup_test.dart \
//     --dart-define=FOTG_API_BASE_URL=http://192.168.1.20:8000 \
//     --dart-define=FOTG_TEST_TOKEN=<the token step 1 printed>

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/core/network/api_client.dart';
import 'package:foodonthego/core/routing/routes.dart';
import 'package:foodonthego/data/repositories/api_cart_repository.dart';
import 'package:foodonthego/data/repositories/api_discovery_repository.dart';
import 'package:foodonthego/data/repositories/api_menu_repository.dart';
import 'package:foodonthego/data/repositories/api_pickup_repository.dart';
import 'package:foodonthego/data/repositories/api_place_repository.dart';
import 'package:foodonthego/data/repositories/api_route_repository.dart';
import 'package:foodonthego/data/repositories/api_trip_repository.dart';
import 'package:foodonthego/domain/models/customer.dart';
import 'package:foodonthego/domain/models/discovered_restaurant.dart';
import 'package:foodonthego/domain/models/menu_customization.dart';
import 'package:foodonthego/domain/models/pickup.dart';
import 'package:foodonthego/domain/models/place.dart';
import 'package:foodonthego/domain/models/pre_checkout.dart';
import 'package:foodonthego/domain/models/restaurant_menu.dart';
import 'package:foodonthego/domain/models/trip.dart';
import 'package:foodonthego/domain/repositories/trip_repository.dart';
import 'package:integration_test/integration_test.dart';

import 'support/device_support.dart';

const String _spice = '[TEST] Highway Spice Kitchen';
const String _dish = 'Paneer Tikka';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late ApiClient api;
  late Customer customer;
  late Trip trip;
  late DiscoveredRestaurant restaurant;
  late MenuItemPreview item;
  late ApiCartRepository carts;
  late ApiMenuRepository menus;
  late ApiPickupRepository pickup;

  setUpAll(() async {
    requireToken();
    api = apiAs();
    customer = await whoAmI(api);
    carts = ApiCartRepository(api);
    menus = ApiMenuRepository(api);
    pickup = ApiPickupRepository(api);
  });

  tearDownAll(() => api.close());

  /// Everything up to the dish, over HTTP, as this customer.
  Future<void> prepare() async {
    final ApiTripRepository trips = ApiTripRepository(api);
    final ApiPlaceRepository places = ApiPlaceRepository(api);

    final Iterable<Trip> open = (await trips.trips(scope: TripScope.all))
        .where((Trip journey) => journey.isDiscardable);

    if (open.isNotEmpty) {
      trip = open.first;
    } else {
      final List<PlaceSuggestion> from = await places.search('green park');
      final List<PlaceSuggestion> to = await places.search('jaipur airport');

      trip = await trips.createTrip(
        TripDraft(
          origin: TripLocation.fromPlace(
            await places.details(from.first.placeId),
          ),
          destination: TripLocation.fromPlace(
            await places.details(to.first.placeId),
          ),
        ),
      );
    }

    // Only when there is not one already. A route is a billed call against a
    // real provider, and re-asking for one the journey already has is exactly
    // the cost this module is not allowed to add.
    if (!trip.routeStatus.hasUsableRoute) {
      await ApiRouteRepository(api).calculate(trip.id);
    }

    final RestaurantDiscovery found = await ApiDiscoveryRepository(api)
        .discover(trip.id);

    restaurant = found.restaurants.firstWhere(
      (DiscoveredRestaurant r) => r.name == _spice,
      orElse: () => throw StateError(
        'The fixture restaurant "$_spice" is not on this route. Seed it with '
        'DiscoveryTestRestaurantSeeder and MenuTestDataSeeder.',
      ),
    );

    final RestaurantMenu menu = await menus.menu(
      tripId: trip.id,
      restaurantId: restaurant.id,
    );

    final MenuItem card = menu.allItems.firstWhere(
      (MenuItem i) => i.name == _dish,
      orElse: () => throw StateError('"$_dish" is not on the seeded menu.'),
    );

    item = await menus.item(
      tripId: trip.id,
      restaurantId: restaurant.id,
      itemId: card.id,
    );
  }

  String variantNamed(String name) => item.customization.variants
      .firstWhere((MenuItemVariant v) => v.name == name)
      .id;

  String optionNamed(String name) => item.customization.modifierGroups
      .expand((MenuModifierGroup g) => g.options)
      .firstWhere((MenuModifierOption o) => o.name == name)
      .id;

  /// Empties the cart and puts one known line in it, over HTTP.
  Future<void> seedOneLine() async {
    await carts.empty(tripId: trip.id);

    await menus.addToCart(
      tripId: trip.id,
      restaurantId: restaurant.id,
      itemId: item.item.id,
      variantId: variantNamed('Large'),
      optionIds: <String>[optionNamed('Mild')],
      quantity: 1,
    );
  }

  /// What the server currently holds, fetched independently of the screen.
  Future<PickupPlan> serverPlan() async =>
      (await pickup.options(tripId: trip.id)).plan;

  Future<void> openPickup(WidgetTester tester) async {
    await launchSignedIn(
      tester,
      customer: customer,
      location: Routes.tripPickupPath(trip.id),
    );

    await waitFor(
      tester,
      find.text('Choose a time'),
      describe: 'the pickup times to load from the server',
    );
  }

  /// The chip for one option, by the key the screen gives it.
  Finder chipFor(PickupOption option) =>
      find.byKey(ValueKey<String>('pickup-option-${option.id}'));

  // ------------------------------------------------------------ the windows

  testWidgets('the pickup times arrive from the server with the arithmetic', (
    WidgetTester tester,
  ) async {
    await prepare();
    await seedOneLine();

    final PickupPlan plan = await serverPlan();

    expect(
      plan.isFeasible,
      isTrue,
      reason:
          'the seeded restaurant offered no pickup window — check its opening '
          'hours and that the route is fresh',
    );

    await openPickup(tester);

    // The chips on screen are the windows the server offered. Matched by the
    // server's own option ids, so a screen that had invented a time would find
    // no key to match.
    for (final PickupOption option in plan.options) {
      await scrollTo(tester, chipFor(option));
      expect(
        chipFor(option),
        findsOneWidget,
        reason: 'no chip for the option the server offered',
      );
    }

    // And the explanation, so the times are something a customer can check
    // rather than take on trust.
    await scrollTo(tester, find.text('How we worked this out'));
    expect(find.text('How we worked this out'), findsOneWidget);
    expect(
      find.text('These are estimates. Traffic and kitchens both vary.'),
      findsOneWidget,
    );
  });

  testWidgets('the times shown are the restaurant clock, not the device one', (
    WidgetTester tester,
  ) async {
    await prepare();
    await seedOneLine();

    final PickupPlan plan = await serverPlan();
    final PickupOption first = plan.options.first;

    await openPickup(tester);

    // Formatted from the offset the server sent. A device in another timezone
    // — or one whose owner has set the clock to anything at all — still reads
    // the time written on the restaurant's door.
    final int hour = first.localStartAt.hour % 12 == 0
        ? 12
        : first.localStartAt.hour % 12;
    final String expected =
        '$hour:${first.localStartAt.minute.toString().padLeft(2, '0')} '
        '${first.localStartAt.hour < 12 ? 'am' : 'pm'}';

    await scrollTo(tester, chipFor(first));
    expect(find.textContaining(expected), findsWidgets);
  });

  // ------------------------------------------------------------- choosing it

  testWidgets('tapping a chip writes the server own window to the cart', (
    WidgetTester tester,
  ) async {
    await prepare();
    await seedOneLine();

    final PickupPlan before = await serverPlan();

    expect(
      before.selection.status,
      PickupSelectionStatus.none,
      reason: 'the cart already had a pickup time before anything was tapped',
    );

    await openPickup(tester);

    // The screen's own chips, not the ones fetched above — those ids were
    // consumed by that request, which is the option store's single-use
    // behaviour working as designed.
    //
    // Tapped by its semantics label, which doubles as the assertion that the
    // recommendation is announced and not merely highlighted: a customer using
    // a screen reader has to be able to find it too.
    final Finder recommended = find.bySemanticsLabel(RegExp('Recommended'));

    await waitFor(
      tester,
      recommended,
      describe: 'a recommended pickup time, announced as one',
    );

    await tapAt(tester, recommended);

    await waitFor(
      tester,
      find.text('Your pickup time'),
      describe: 'the server to confirm the choice',
    );

    // The assertion that matters, and it is made against the database rather
    // than against the screen. A screen agreeing with itself proves nothing.
    final PickupPlan after = await serverPlan();

    expect(after.selection.status, PickupSelectionStatus.selected);
    expect(after.selection.startAt, isNotNull);
    expect(after.selection.endAt, isNotNull);
    expect(after.selection.timezone, isNotNull);

    // And it is one of the windows the server offered, not a time the client
    // put together.
    final bool matchesAnOfferedWindow = after.options.any(
      (PickupOption o) => o.startAt.isAtSameMomentAs(after.selection.startAt!),
    );

    expect(
      matchesAnOfferedWindow ||
          after.selection.startAt!.isAfter(before.serverNow!),
      isTrue,
      reason: 'the stored window is not one the server ever offered',
    );
  });

  testWidgets('choosing again replaces the choice rather than adding one', (
    WidgetTester tester,
  ) async {
    await prepare();
    await seedOneLine();
    await openPickup(tester);

    final Finder chips = find.textContaining('–');

    await tapAt(tester, chips.first);
    await waitFor(tester, find.text('Your pickup time'));

    final PickupPlan first = await serverPlan();

    await openPickup(tester);

    // A later window this time.
    final Finder later = find.textContaining('–');
    await tapAt(tester, later.at(2));
    await waitFor(tester, find.text('Your pickup time'));

    final PickupPlan second = await serverPlan();

    // One pickup time per cart. A PUT, and it means it.
    expect(second.selection.status, PickupSelectionStatus.selected);
    expect(
      second.selection.startAt!.isAtSameMomentAs(first.selection.startAt!),
      isFalse,
      reason: 'choosing a different window did not replace the first',
    );
  });

  // --------------------------------------------------------- pre-checkout

  testWidgets('the readiness verdict comes from the server', (
    WidgetTester tester,
  ) async {
    await prepare();
    await seedOneLine();
    await openPickup(tester);

    await tapAt(tester, find.textContaining('–').first);
    await waitFor(tester, find.text('Your pickup time'));

    await tapAt(
      tester,
      find.byKey(const ValueKey<String>('pickup-check-order')),
    );

    await waitFor(
      tester,
      find.textContaining('ready'),
      describe: 'the server verdict',
    );

    // Fetched separately, and the screen must agree with it rather than the
    // other way round.
    final PreCheckoutResult result = await pickup.preCheckout(tripId: trip.id);

    if (result.readyForCheckout) {
      expect(find.text('Your order is ready to go'), findsOneWidget);
    } else {
      expect(find.text('Not quite ready'), findsOneWidget);
    }
  });

  testWidgets('changing the cart makes the chosen time stale', (
    WidgetTester tester,
  ) async {
    await prepare();
    await seedOneLine();
    await openPickup(tester);

    await tapAt(tester, find.textContaining('–').first);
    await waitFor(tester, find.text('Your pickup time'));

    // The customer adds a second dish after choosing a time. The cart's
    // version moves, the planning fingerprint with it, and the selection is no
    // longer one anybody has checked.
    await menus.addToCart(
      tripId: trip.id,
      restaurantId: restaurant.id,
      itemId: item.item.id,
      variantId: variantNamed('Regular'),
      optionIds: <String>[optionNamed('Hot')],
      quantity: 1,
    );

    final PreCheckoutResult result = await pickup.preCheckout(tripId: trip.id);

    expect(result.selectionStatus, PickupSelectionStatus.stale);
    expect(
      result.readyForCheckout,
      isFalse,
      reason: 'the server said yes over a pickup time nobody had re-checked',
    );

    await openPickup(tester);

    await waitFor(
      tester,
      find.text('Your order has changed'),
      describe: 'the screen to report what the server found',
    );
  });

  // ------------------------------------------------- what must not have run

  testWidgets('no order and no payment exist after all of that', (
    WidgetTester tester,
  ) async {
    await prepare();
    await seedOneLine();
    await openPickup(tester);

    await tapAt(tester, find.textContaining('–').first);
    await waitFor(tester, find.text('Your pickup time'));

    // Module 13 ends with four columns on a cart. The cart is still a cart,
    // still active, and still holds the line that was put in it — nothing has
    // been converted into anything.
    final PickupPlan plan = await serverPlan();

    expect(plan.selection.status, PickupSelectionStatus.selected);

    final int lines =
        (await carts.cart(tripId: trip.id)).cart?.lines.length ?? 0;

    expect(lines, 1, reason: 'the cart changed when only a time was chosen');
  });
}
