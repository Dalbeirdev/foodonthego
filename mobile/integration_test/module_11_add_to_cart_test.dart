// Module 11 on a real device: configuring a dish and adding it to a cart.
//
// This is the run that closes M11-050 (Android) and M11-051 (iOS). It is not a
// widget test with a fake repository behind it — it builds the shipping app,
// installs it on a handset or emulator, taps the real controls with a real
// finger-sized hit test, and talks to a real Laravel server writing real rows
// to real MySQL tables.
//
// WHAT IT PROVES, AND WHAT IT DOES NOT
//
// It proves the Module 11 screens work on the platform: that the item detail
// loads over the device's own network stack, that the selection rules behave
// under real touch input, that the price on the button tracks the choices, and
// that the row the server writes carries the server's price rather than the
// phone's.
//
// It does not re-prove sign-in (Module 03), journey planning (Module 05) or
// discovery (Module 07). Those have their own verification, and re-driving them
// here would mean a failure in any of them arriving as a Module 11 failure.
// They are set up over HTTP instead, and the app is launched straight at the
// screen under test.
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
//   flutter test integration_test/module_11_add_to_cart_test.dart \
//     --dart-define=FOTG_API_BASE_URL=http://192.168.1.20:8000 \
//     --dart-define=FOTG_TEST_TOKEN=<the token step 1 printed>
//
// A device on cleartext HTTP needs the debug build's network-security config,
// which is what `flutter test` produces; a release build would refuse it, and
// should.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/core/network/api_client.dart';
import 'package:foodonthego/core/routing/routes.dart';
import 'package:foodonthego/data/repositories/api_discovery_repository.dart';
import 'package:foodonthego/data/repositories/api_menu_repository.dart';
import 'package:foodonthego/data/repositories/api_place_repository.dart';
import 'package:foodonthego/data/repositories/api_route_repository.dart';
import 'package:foodonthego/data/repositories/api_trip_repository.dart';
import 'package:foodonthego/domain/models/cart.dart';
import 'package:foodonthego/domain/models/customer.dart';
import 'package:foodonthego/domain/models/discovered_restaurant.dart';
import 'package:foodonthego/domain/models/place.dart';
import 'package:foodonthego/domain/models/restaurant_menu.dart';
import 'package:foodonthego/domain/models/trip.dart';
import 'package:foodonthego/domain/repositories/trip_repository.dart';
import 'package:integration_test/integration_test.dart';

import 'support/device_support.dart';

/// The restaurant and dish the whole module is documented against.
const String _spice = '[TEST] Highway Spice Kitchen';
const String _dish = 'Paneer Tikka';

/// What the server should charge for Large + Extra Cheese + Jalapeños, in
/// paise. ₹329 + ₹40 + ₹20.
///
/// Written here as the expectation rather than read from the response and
/// compared with itself: a test that asserts the server agrees with the server
/// passes no matter what either of them says.
const int _expectedUnitMinor = 38900;
const int _expectedLineMinor = 77800;

/// A cart's subtotal in paise, with an empty cart counting as nothing.
///
/// The assertions below are all differences — what a tap added — rather than
/// totals, because the run shares one cart (see `prepare`) and a total would
/// be an assertion about every test that ran before this one.
int _minor(CartSummary cart) => cart.subtotal?.amountMinor ?? 0;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late ApiClient api;
  late Customer customer;
  late Trip trip;
  late DiscoveredRestaurant restaurant;
  late MenuItemPreview item;

  setUpAll(() async {
    requireToken();
    api = apiAs();
    customer = await whoAmI(api);
  });

  tearDownAll(() => api.close());

  /// Everything up to the dish, over HTTP, as this customer.
  ///
  /// ONE journey for the whole run, reused rather than replaced.
  ///
  /// This used to discard every open journey and create a fresh one per test,
  /// so that a test which added to a cart could not change what the next one
  /// started from. That reasoning was right about the problem and wrong about
  /// the remedy, and the first device run that got as far as adding to a cart
  /// showed why: a cart belongs to a journey, and discarding the journey does
  /// not close the cart. The next test then arrives on a new journey holding
  /// an active cart on the old one, and Module 11 refuses the add —
  ///
  ///     CART_TRIP_CONFLICT
  ///     You have items in a cart for a different journey.
  ///
  /// — which is the correct answer to the question it was asked. The setup was
  /// manufacturing the conflict and then failing on it. (The state itself is a
  /// real dead end for a customer, not only for this run: see KI-014. Nothing
  /// in Module 11 can release that cart, which is why this cannot be fixed by
  /// cleaning up over HTTP.)
  ///
  /// So the journey is shared, the cart is shared, and the two tests that add
  /// to it assert what their own taps changed rather than what the whole cart
  /// contains. That is the stronger assertion anyway: "adding this
  /// configuration adds exactly this much" holds whatever else is in there.
  Future<void> prepare() async {
    final ApiTripRepository trips = ApiTripRepository(api);
    final ApiPlaceRepository places = ApiPlaceRepository(api);

    final Iterable<Trip> open = (await trips.trips(
      scope: TripScope.all,
    )).where((Trip journey) => journey.isDiscardable);

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
    // the cost Module 11 is not allowed to add.
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

    final ApiMenuRepository menus = ApiMenuRepository(api);

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

  Future<void> openTheDish(WidgetTester tester) async {
    await prepare();

    await launchSignedIn(
      tester,
      customer: customer,
      location: Routes.menuItemPath(trip.id, restaurant.id, item.item.id),
    );

    await waitFor(
      tester,
      find.text(_dish),
      describe: 'the dish to load from the server',
    );
  }

  // ---------------------------------------------------------------- the dish

  testWidgets('the dish arrives from the server with its sizes and questions', (
    WidgetTester tester,
  ) async {
    await openTheDish(tester);

    expect(find.text(_dish), findsWidgets);
    expect(find.text('Choose a size'), findsOneWidget);
    expect(find.text('Regular'), findsOneWidget);
    expect(find.text('Large'), findsOneWidget);

    // Shown rather than hidden: a customer who came for the family portion
    // should be told it is gone, not left wondering if they misremembered.
    expect(find.text('Family (serves 4)'), findsOneWidget);

    await scrollTo(tester, find.text('Spice level'));
    expect(find.text('Required · Choose 1'), findsOneWidget);

    await scrollTo(tester, find.text('Add extras'));
    expect(find.text('Optional · Choose up to 2'), findsOneWidget);
  });

  testWidgets('nothing that costs money is ticked for the customer', (
    WidgetTester tester,
  ) async {
    await openTheDish(tester);

    // Asserted with the option on screen, so a pass cannot mean "the widget was
    // never built".
    await scrollTo(tester, find.text('Extra Cheese'));

    expect(
      find.bySemanticsLabel('Extra Cheese. Adds 40 rupees. Not selected'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Extra Cheese. Adds 40 rupees. Selected'),
      findsNothing,
    );

    // The one thing that *is* preselected is the restaurant's configured
    // default, and it is free.
    expect(
      find.bySemanticsLabel('Mild. No extra charge. Selected'),
      findsOneWidget,
    );
  });

  testWidgets('a size is the price, not a surcharge on top of it', (
    WidgetTester tester,
  ) async {
    await openTheDish(tester);

    expect(find.textContaining('Add to cart · ₹249'), findsOneWidget);

    await tapAt(tester, find.text('Large'));

    // ₹329. If a variant were ever added to the base price this would be ₹578.
    await waitFor(
      tester,
      find.textContaining('Add to cart · ₹329'),
      describe: 'the button to quote the Large price',
    );
  });

  testWidgets('a sold-out size cannot be chosen', (WidgetTester tester) async {
    await openTheDish(tester);

    await tapAt(tester, find.text('Large'));
    await waitFor(tester, find.textContaining('Add to cart · ₹329'));

    await tapAt(tester, find.text('Family (serves 4)'));
    await settle(tester, duration: const Duration(seconds: 2));

    // Still Large. The tap did nothing, which is the point — and unlike every
    // other assertion here this one must NOT poll: waiting for a thing that is
    // already true would pass however long the price took to change.
    expect(find.textContaining('Add to cart · ₹329'), findsOneWidget);
  });

  // ------------------------------------------------------- the whole journey

  testWidgets('Rahul configures the dish and the server prices what he chose', (
    WidgetTester tester,
  ) async {
    await openTheDish(tester);

    final CartSummary before = await ApiMenuRepository(api).cart(
      tripId: trip.id,
    );

    // Size: ₹329.
    await tapAt(tester, find.text('Large'));

    // The required question, answered differently from its default. Choosing
    // in a single-select group replaces rather than adds.
    await tapAt(tester, find.text('Hot'));
    await waitFor(
      tester,
      find.bySemanticsLabel('Mild. No extra charge. Not selected'),
      describe: 'Mild to be deselected when Hot is chosen',
    );

    // Two paid extras: +₹40 and +₹20.
    await tapAt(tester, find.text('Extra Cheese'));
    await tapAt(tester, find.text('Jalapeños'));

    await waitFor(
      tester,
      find.textContaining('Add to cart · ₹389'),
      describe: 'the button to price both extras',
    );

    // The ceiling on that group is two, and it says so once reached.
    await waitFor(tester, find.text('You can choose up to 2.'));

    // Quantity.
    await tapAt(tester, find.bySemanticsLabel('Add one more'));
    await waitFor(tester, find.bySemanticsLabel('Quantity, 2'));
    await waitFor(
      tester,
      find.textContaining('Add to cart · ₹778'),
      describe: 'the line total for two',
    );

    // The note, and what it is careful not to promise.
    final Finder note = find.byType(TextField).last;
    await scrollTo(tester, note);
    await tester.enterText(note, 'Less spicy, no onion please');
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('will do what they can'), findsOneWidget);
    expect(find.textContaining('guarantee'), findsNothing);

    // Add it. This is the request the whole module exists to make — and it
    // carries no price.
    await tapAt(tester, find.textContaining('Add to cart · ₹778'));
    await waitFor(
      tester,
      find.text('Added to cart'),
      describe: 'the confirmation after adding',
    );

    // --- and now what the server actually stored ------------------------
    final CartSummary cart = await ApiMenuRepository(api).cart(tripId: trip.id);

    expect(cart.lineCount, before.lineCount + 1, reason: 'one new line');
    expect(cart.itemCount, before.itemCount + 2, reason: 'two of it');
    expect(cart.restaurantId, restaurant.id);
    expect(
      _minor(cart) - _minor(before),
      _expectedLineMinor,
      reason:
          'the server should charge $_expectedLineMinor paise for what was '
          'chosen — the phone sent no price at all',
    );
  });

  testWidgets('a second identical tap does not add a second line', (
    WidgetTester tester,
  ) async {
    await openTheDish(tester);

    await tapAt(tester, find.text('Large'));
    await tapAt(tester, find.text('Extra Cheese'));
    await tapAt(tester, find.text('Jalapeños'));

    final Finder add = find.textContaining('Add to cart · ₹389');
    final ApiMenuRepository carts = ApiMenuRepository(api);

    final CartSummary before = await carts.cart(tripId: trip.id);

    await tapAt(tester, add);
    await waitFor(tester, find.text('Added to cart'));

    final CartSummary once = await carts.cart(tripId: trip.id);
    expect(
      once.lineCount,
      before.lineCount + 1,
      reason: 'the first tap makes a line',
    );

    // The same configuration again. A cart line is a configuration, not a tap:
    // this must become a quantity, never a duplicate row.
    await settle(tester, duration: const Duration(seconds: 3));
    await tapAt(tester, add);
    await settle(tester, duration: const Duration(seconds: 4));

    final CartSummary twice = await carts.cart(tripId: trip.id);

    expect(
      twice.lineCount,
      once.lineCount,
      reason: 'the second tap makes no new line',
    );
    expect(
      twice.itemCount,
      once.itemCount + 1,
      reason: 'it makes a quantity instead',
    );
    expect(_minor(twice) - _minor(before), _expectedUnitMinor * 2);
  });

  // -------------------------------------------------------- the other shapes

  testWidgets('a dish with no default size asks before it prices', (
    WidgetTester tester,
  ) async {
    await prepare();

    final ApiMenuRepository menus = ApiMenuRepository(api);

    final RestaurantMenu menu = await menus.menu(
      tripId: trip.id,
      restaurantId: restaurant.id,
    );

    final MenuItem chaiCard = menu.allItems.firstWhere(
      (MenuItem i) => i.name == 'Masala Chai',
      orElse: () =>
          throw StateError('"Masala Chai" is not on the seeded menu.'),
    );

    await launchSignedIn(
      tester,
      customer: customer,
      location: Routes.menuItemPath(trip.id, restaurant.id, chaiCard.id),
    );

    await waitFor(tester, find.text('Masala Chai'));

    // No configured default, so the button asks rather than quoting a price for
    // a dish nobody has finished describing.
    expect(find.text('Choose required options'), findsOneWidget);

    await tapAt(tester, find.text('250 ml'));

    await waitFor(
      tester,
      find.textContaining('Add to cart · ₹69'),
      describe: 'the button to price the chosen size',
    );
  });

  testWidgets('a sold-out dish offers no way to add it', (
    WidgetTester tester,
  ) async {
    await prepare();

    final ApiMenuRepository menus = ApiMenuRepository(api);

    final RestaurantMenu menu = await menus.menu(
      tripId: trip.id,
      restaurantId: restaurant.id,
    );

    final MenuItem mushroom = menu.allItems.firstWhere(
      (MenuItem i) => i.name == 'Tandoori Mushroom',
      orElse: () =>
          throw StateError('"Tandoori Mushroom" is not on the seeded menu.'),
    );

    await launchSignedIn(
      tester,
      customer: customer,
      location: Routes.menuItemPath(trip.id, restaurant.id, mushroom.id),
    );

    await waitFor(tester, find.text('Tandoori Mushroom'));

    // A button that fails on tap would be worse than no button.
    expect(find.textContaining('Add to cart ·'), findsNothing);
    expect(find.textContaining('sold out'), findsWidgets);
  });
}
