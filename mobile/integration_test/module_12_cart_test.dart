// Module 12 on a real device: reading, correcting and emptying a cart.
//
// The companion to module_11_add_to_cart_test.dart, and the run that closes
// M12-050 (Android) and M12-051 (iOS). It builds the shipping app, installs it
// on a handset or emulator, taps the real controls with a real finger-sized hit
// test, and talks to a real Laravel server writing real rows to real MySQL
// tables.
//
// WHAT IT PROVES, AND WHAT IT DOES NOT
//
// It proves that the cart screen works on the platform: that it loads over the
// device's own network stack, that a stepper tapped by a finger changes a
// quantity the *server* then agrees with, that removing and emptying do what
// they say, and — the point of the module — that every figure on the screen is
// one the server sent rather than one the phone worked out.
//
// It does not re-prove sign-in (Module 03), journey planning (Module 05),
// discovery (Module 07) or adding to a cart (Module 11). Those have their own
// verification, and re-driving them here would mean a failure in any of them
// arriving as a Module 12 failure. They are set up over HTTP instead, and the
// app is launched straight at the screen under test.
//
// CART STATE
//
// Every test starts by emptying the cart over HTTP and adding one known line.
// Module 11's device test could not do that — there was no way to release a
// cart, which is exactly the dead end KI-014 recorded — and being able to reset
// deterministically here is itself the fix working.
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
//   flutter test integration_test/module_12_cart_test.dart \
//     --dart-define=FOTG_API_BASE_URL=http://192.168.1.20:8000 \
//     --dart-define=FOTG_TEST_TOKEN=<the token step 1 printed>

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/core/network/api_client.dart';
import 'package:foodonthego/core/routing/routes.dart';
import 'package:foodonthego/data/repositories/api_cart_repository.dart';
import 'package:foodonthego/data/repositories/api_discovery_repository.dart';
import 'package:foodonthego/data/repositories/api_menu_repository.dart';
import 'package:foodonthego/data/repositories/api_place_repository.dart';
import 'package:foodonthego/data/repositories/api_route_repository.dart';
import 'package:foodonthego/data/repositories/api_trip_repository.dart';
import 'package:foodonthego/domain/models/cart.dart';
import 'package:foodonthego/domain/models/customer.dart';
import 'package:foodonthego/domain/models/discovered_restaurant.dart';
import 'package:foodonthego/domain/models/menu_customization.dart';
import 'package:foodonthego/domain/models/place.dart';
import 'package:foodonthego/domain/models/restaurant_menu.dart';
import 'package:foodonthego/domain/models/trip.dart';
import 'package:foodonthego/domain/repositories/trip_repository.dart';
import 'package:integration_test/integration_test.dart';

import 'support/device_support.dart';

const String _spice = '[TEST] Highway Spice Kitchen';
const String _dish = 'Paneer Tikka';

/// One Large Paneer Tikka, mild, in paise. ₹329.
///
/// Written here as the expectation rather than read from the response and
/// compared with itself: a test that asserts the server agrees with the server
/// passes no matter what either of them says.
const int _unitMinor = 32900;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late ApiClient api;
  late Customer customer;
  late Trip trip;
  late DiscoveredRestaurant restaurant;
  late MenuItemPreview item;
  late ApiCartRepository carts;
  late ApiMenuRepository menus;

  setUpAll(() async {
    requireToken();
    api = apiAs();
    customer = await whoAmI(api);
    carts = ApiCartRepository(api);
    menus = ApiMenuRepository(api);
  });

  tearDownAll(() => api.close());

  /// Everything up to the dish, over HTTP, as this customer.
  ///
  /// One journey for the whole run, reused rather than replaced — for the
  /// reason module_11_add_to_cart_test.dart sets out at length: a cart belongs
  /// to a journey, and until Module 12 there was nothing that could release
  /// one.
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
  ///
  /// Deterministic on purpose. The screen's job is to show what the server
  /// holds, and a test that started from whatever the previous one left behind
  /// would be asserting about the wrong cart half the time.
  Future<void> seedOneLine({int quantity = 1}) async {
    await carts.empty(tripId: trip.id);

    await menus.addToCart(
      tripId: trip.id,
      restaurantId: restaurant.id,
      itemId: item.item.id,
      variantId: variantNamed('Large'),
      optionIds: <String>[optionNamed('Mild')],
      quantity: quantity,
    );
  }

  Future<void> openTheCart(WidgetTester tester) async {
    await launchSignedIn(
      tester,
      customer: customer,
      location: Routes.tripCartPath(trip.id),
    );

    await waitFor(
      tester,
      find.text(_dish),
      describe: 'the cart to load from the server',
    );
  }

  // ------------------------------------------------------------- reading it

  testWidgets('the cart arrives from the server with its lines and totals', (
    WidgetTester tester,
  ) async {
    await prepare();
    await seedOneLine(quantity: 2);
    await openTheCart(tester);

    expect(find.text(_dish), findsWidgets);

    // The configuration in full, so a customer can check that what they chose
    // three screens ago is what they are about to buy.
    expect(find.text('Large · Mild'), findsOneWidget);

    // ₹329 × 2, as the server computed it.
    expect(find.textContaining('₹658'), findsWidgets);
    expect(find.text('Subtotal'), findsOneWidget);
    expect(find.text('Total'), findsOneWidget);
  });

  testWidgets('the cart is reachable from the menu', (
    WidgetTester tester,
  ) async {
    await prepare();
    await seedOneLine();

    // Module 11 could fill a cart and had nowhere to send anybody afterwards.
    // This is the door, on the screen a customer adds from.
    await launchSignedIn(
      tester,
      customer: customer,
      location: Routes.restaurantMenuPath(trip.id, restaurant.id),
    );

    await waitFor(
      tester,
      find.byIcon(Icons.shopping_basket_outlined),
      describe: 'the cart button in the menu app bar',
    );

    await tapAt(tester, find.byIcon(Icons.shopping_basket_outlined));

    await waitFor(
      tester,
      find.text('Your cart'),
      describe: 'the cart screen to open',
    );
  });

  // ---------------------------------------------------------- changing it

  testWidgets('the plus changes the quantity the server holds', (
    WidgetTester tester,
  ) async {
    await prepare();
    await seedOneLine();
    await openTheCart(tester);

    await tapAt(tester, find.byIcon(Icons.add_rounded));

    await waitFor(
      tester,
      find.textContaining('₹658'),
      describe: 'the line total to double',
    );

    // --- and now what the server actually stored ------------------------
    final CartView view = await carts.cart(tripId: trip.id);

    expect(view.itemCount, 2);
    expect(view.cart!.lines.single.quantity, 2);
    expect(
      view.cart!.totals.subtotal.amountMinor,
      _unitMinor * 2,
      reason:
          'the server should hold $_unitMinor paise per unit — the phone sent '
          'a count and no price at all',
    );
  });

  testWidgets('the minus stops at one rather than removing the line', (
    WidgetTester tester,
  ) async {
    await prepare();
    await seedOneLine();
    await openTheCart(tester);

    // Tapped anyway. Turning the last decrement into a deletion is how a
    // mis-tap loses a customer's selection, so the control is disabled and the
    // tap does nothing — and unlike the polling assertions above this one must
    // NOT wait for a state that is already true.
    await tester.tap(find.byIcon(Icons.remove_rounded), warnIfMissed: false);
    await settle(tester, duration: const Duration(seconds: 2));

    final CartView view = await carts.cart(tripId: trip.id);

    expect(view.cart, isNotNull, reason: 'the cart is still there');
    expect(view.cart!.lines.single.quantity, 1);
  });

  testWidgets('removing the line empties the cart on the server', (
    WidgetTester tester,
  ) async {
    await prepare();
    await seedOneLine();
    await openTheCart(tester);

    await scrollTo(tester, find.text('Remove'));
    await tapAt(tester, find.text('Remove'));

    await waitFor(
      tester,
      find.text('Nothing in your cart yet'),
      describe: 'the empty state after removing the last line',
    );

    // An emptied cart is closed, and the server reports a closed cart as no
    // cart at all — which is what the empty screen is showing.
    final CartView view = await carts.cart(tripId: trip.id);

    expect(view.cart, isNull);
    expect(view.itemCount, 0);
  });

  // ---------------------------------------------------------- emptying it

  testWidgets('emptying asks first, and backing out changes nothing', (
    WidgetTester tester,
  ) async {
    await prepare();
    await seedOneLine(quantity: 3);
    await openTheCart(tester);

    await tapAt(tester, find.text('Empty cart'));

    await waitFor(
      tester,
      find.text('Empty your cart?'),
      describe: 'the confirmation before anything is destroyed',
    );

    await tapAt(tester, find.text('Keep it'));
    await settle(tester, duration: const Duration(seconds: 2));

    final CartView view = await carts.cart(tripId: trip.id);

    expect(view.itemCount, 3, reason: 'nothing was destroyed');
  });

  testWidgets('confirming empties it, and the journey is usable again', (
    WidgetTester tester,
  ) async {
    await prepare();
    await seedOneLine();
    await openTheCart(tester);

    await tapAt(tester, find.text('Empty cart'));
    await waitFor(tester, find.text('Empty your cart?'));

    // The dialogue's action, not the app bar's — both read "Empty cart".
    await tapAt(tester, find.widgetWithText(TextButton, 'Empty cart').last);

    await waitFor(
      tester,
      find.text('Nothing in your cart yet'),
      describe: 'the empty state after emptying',
    );

    expect((await carts.cart(tripId: trip.id)).cart, isNull);

    // KI-014's release, on a device. Before Module 12 an active cart could not
    // be let go of, and a customer who had discarded its journey could never
    // add to a cart again — on any journey. Adding here proves the slot is
    // free.
    await menus.addToCart(
      tripId: trip.id,
      restaurantId: restaurant.id,
      itemId: item.item.id,
      variantId: variantNamed('Large'),
      optionIds: <String>[optionNamed('Mild')],
      quantity: 1,
    );

    final CartView after = await carts.cart(tripId: trip.id);

    expect(after.itemCount, 1);
    expect(after.cart!.totals.subtotal.amountMinor, _unitMinor);
  });
}
