// Module 14 on a real device: the last screen before money.
//
// The companion to module_13_pickup_test.dart, and the run that closes M14-069
// (Android) and M14-070 (iOS). It builds the shipping app, installs it on a
// handset or emulator, taps the real controls with a real finger-sized hit
// test, and talks to a real Laravel server writing real rows to real MySQL
// tables.
//
// WHAT IT PROVES, AND WHAT IT DOES NOT
//
// It proves that the checkout screen works on the platform: that a quote is
// prepared over the device's own network stack, that the payable figure on
// screen is the one the *server* wrote to `checkout_quotes`, and — the point of
// the module — that the client renders the server's arithmetic and the server's
// verdict rather than any of its own.
//
// Every assertion that matters is made against the server's own state, fetched
// separately over HTTP after the taps. A screen that agreed with itself would
// pass whatever either side said.
//
// It does not re-prove sign-in (Module 03), journey planning (Module 05),
// discovery (Module 07), adding to a cart (Module 11), cart management (Module
// 12) or pickup planning (Module 13). Those have their own verification, and
// re-driving them here would mean a failure in any of them arriving as a
// Module 14 failure.
//
// WHAT IT CANNOT PROVE
//
// **Nothing here is a payment.** Since Module 15, Proceed does place an order —
// but no money moves: no Razorpay credentials exist in this project, so no
// provider checkout can open and nothing is ever marked paid. A run of this
// file that produced a *payment* would be a bug in the file. An order awaiting
// one is the correct outcome and is asserted as such.
//
// It also proves nothing about commercial policy. Whether tax, a packaging fee
// or a platform fee *should* apply is a client decision that has not been made
// — see docs/29-checkout-and-payment-readiness.md. What this checks is that
// whatever is configured is what is charged, and that what is not configured
// does not appear.
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
//   flutter test integration_test/module_14_checkout_test.dart \
//     --dart-define=FOTG_API_BASE_URL=http://192.168.1.20:8000 \
//     --dart-define=FOTG_TEST_TOKEN=<the token step 1 printed>

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/core/network/api_client.dart';
import 'package:foodonthego/core/routing/routes.dart';
import 'package:foodonthego/data/repositories/api_cart_repository.dart';
import 'package:foodonthego/data/repositories/api_checkout_repository.dart';
import 'package:foodonthego/data/repositories/api_discovery_repository.dart';
import 'package:foodonthego/data/repositories/api_menu_repository.dart';
import 'package:foodonthego/data/repositories/api_order_repository.dart';
import 'package:foodonthego/data/repositories/api_pickup_repository.dart';
import 'package:foodonthego/data/repositories/api_place_repository.dart';
import 'package:foodonthego/data/repositories/api_route_repository.dart';
import 'package:foodonthego/data/repositories/api_trip_repository.dart';
import 'package:foodonthego/domain/models/checkout.dart';
import 'package:foodonthego/domain/models/customer.dart';
import 'package:foodonthego/domain/models/discovered_restaurant.dart';
import 'package:foodonthego/domain/models/menu_customization.dart';
import 'package:foodonthego/domain/models/pickup.dart';
import 'package:foodonthego/domain/models/place.dart';
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
  late ApiCheckoutRepository checkouts;
  late ApiOrderRepository orderApi;

  setUpAll(() async {
    requireToken();
    api = apiAs();
    customer = await whoAmI(api);
    carts = ApiCartRepository(api);
    menus = ApiMenuRepository(api);
    pickup = ApiPickupRepository(api);
    checkouts = ApiCheckoutRepository(api);
    orderApi = ApiOrderRepository(api);
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

  /// One known line in the cart, with a pickup time chosen. Over HTTP, so a
  /// failure in Module 12 or 13 fails there rather than arriving here.
  Future<void> seedOrderReadyToCheckOut() async {
    await carts.empty(tripId: trip.id);

    await menus.addToCart(
      tripId: trip.id,
      restaurantId: restaurant.id,
      itemId: item.item.id,
      variantId: variantNamed('Large'),
      optionIds: <String>[optionNamed('Mild')],
      quantity: 1,
    );

    final PickupView view = await pickup.options(tripId: trip.id);

    final String? recommended = view.plan.recommendedOptionId;

    if (recommended == null) {
      throw StateError(
        'the seeded restaurant offered no pickup window — check its opening '
        'hours and that the route is fresh',
      );
    }

    await pickup.selectOption(tripId: trip.id, optionId: recommended);
  }

  /// What the server currently holds, fetched independently of the screen.
  Future<Checkout> serverCheckout() => checkouts.prepare(tripId: trip.id);

  /// The price as a customer reads it, from a figure in minor units.
  String rupees(int minor) => minor % 100 == 0
      ? '₹${minor ~/ 100}'
      : '₹${minor ~/ 100}.${(minor % 100).toString().padLeft(2, '0')}';

  Future<void> openCheckout(WidgetTester tester) async {
    await launchSignedIn(
      tester,
      customer: customer,
      location: Routes.tripCheckoutPath(trip.id),
    );

    await waitFor(
      tester,
      find.text('Order summary'),
      describe: 'the checkout to be prepared by the server',
    );
  }

  // -------------------------------------------------------------- the figure

  testWidgets('the payable amount on screen is the one the server wrote', (
    WidgetTester tester,
  ) async {
    await prepare();
    await seedOrderReadyToCheckOut();

    final Checkout server = await serverCheckout();

    await openCheckout(tester);
    await scrollTo(tester, find.text('Total to pay'));

    // Not "a plausible total" and not "the sum of the rows on screen" — the
    // exact figure the server put in the quote, fetched over a separate
    // connection. A screen that computed its own would differ the moment a
    // rule the client has never heard of applies.
    expect(
      find.text(rupees(server.commercial.payableTotal.amountMinor)),
      findsWidgets,
      reason: 'the payable shown is not the payable the server quoted',
    );
  });

  testWidgets('only the configured components appear, with their real figures', (
    WidgetTester tester,
  ) async {
    await prepare();
    await seedOrderReadyToCheckOut();

    final Checkout server = await serverCheckout();

    await openCheckout(tester);
    await scrollTo(tester, find.text('Total to pay'));

    // Whatever the server sent, and nothing else. This deliberately asserts
    // against the response rather than against an expected list of charges:
    // the module's rule is that configuration decides, and a test naming the
    // charges would be a second place that decides.
    for (final CommercialLine line in server.commercial.charges) {
      expect(
        find.text(rupees(line.amount.amountMinor)),
        findsWidgets,
        reason: 'the configured ${line.code} did not reach the screen',
      );
    }

    if (!server.commercial.hasConfiguredAdjustments) {
      // Said in words rather than left as a gap. And said about configuration,
      // never about tax law.
      expect(
        find.text('No additional charges are currently configured.'),
        findsOneWidget,
      );

      // And nothing invented a row for a rule nobody has set.
      expect(find.text('Tax'), findsNothing);
      expect(find.text('Service fee'), findsNothing);
      expect(find.text('Packaging'), findsNothing);
    }
  });

  testWidgets('the pickup window reads on the counter clock, not the device', (
    WidgetTester tester,
  ) async {
    await prepare();
    await seedOrderReadyToCheckOut();

    final Checkout server = await serverCheckout();
    final DateTime start = server.pickup.localStartAt!;

    await openCheckout(tester);

    final int hour = start.hour % 12 == 0 ? 12 : start.hour % 12;
    final String expected =
        '$hour:${start.minute.toString().padLeft(2, '0')} '
        '${start.hour < 12 ? 'am' : 'pm'}';

    // Formatted from the offset the server sent. A device in another timezone —
    // or one whose owner has set the clock to anything at all — still reads the
    // time written on the restaurant's door.
    expect(find.textContaining(expected), findsWidgets);
  });

  // ----------------------------------------------------- as far as it may go

  /// The boundary moved in Module 15, and this test moved with it.
  ///
  /// It used to assert that Proceed stopped dead and no order existed. Proceed
  /// now asks the server, and on a yes goes to payment, which places the order.
  /// So the assertion is no longer "nothing was bought" but "exactly one order
  /// exists and no money moved" — which is the boundary that is actually true
  /// of this build, and still read from the server rather than the screen.
  testWidgets('Proceed places the order and stops short of taking money', (
    WidgetTester tester,
  ) async {
    await prepare();
    await seedOrderReadyToCheckOut();

    await openCheckout(tester);
    await scrollTo(
      tester,
      find.byKey(const ValueKey<String>('checkout-proceed')),
    );

    await tapAt(tester, find.byKey(const ValueKey<String>('checkout-proceed')));

    // `waitFor`, not `settle`. This tap is followed by three sequential round
    // trips — validate the quote, place the order, open a payment — and
    // `settle` pumps for a fixed six seconds without knowing about any of them.
    // device_support.dart says exactly this about `tapAt`: it is a courtesy,
    // not a guarantee, and callers that assert on the result must wait for the
    // condition. The first version of this test ignored that and failed on both
    // platforms.
    await waitFor(
      tester,
      // The order CARD, not the order number.
      //
      // Since Module 16 the number is minted when the money is captured, and
      // no money has been captured here — this journey stops deliberately short
      // of paying. Waiting for a number the server has correctly not issued
      // would be waiting forever, and the failure would look like a hung
      // screen rather than a wrong expectation.
      find.byKey(const ValueKey<String>('payment-order-card')),
      describe: 'the payment screen showing the order the server created',
    );

    // Read from the server, not from the screen: a client cannot know what a
    // backend did, and this is the assertion the boundary rests on.
    final List<Map<String, dynamic>> orders = await ordersFor(api);

    /*
     * ZERO, and this is the Module 16 boundary rather than a weakened test.
     *
     * /customer/orders lists placed orders. Reaching the payment screen creates
     * a payment target — a row a payment can be attached to — and no money has
     * been captured, so no order has been placed and the customer's Orders tab
     * is correctly empty. Asserting one here would be asserting that an unpaid
     * basket shows up as a purchase.
     */
    expect(
      orders,
      isEmpty,
      reason: 'nothing was paid for, so nothing may appear as an order',
    );
  });

  // ------------------------------------------- Module 16, as far as it reaches

  /*
   | The confirmation screen on a real device, for an order nobody has paid for.
   |
   | WHAT THIS CAN AND CANNOT REACH. The screen's main job — showing an order
   | number and a pickup code — needs a CAPTURED payment, and no payment can be
   | captured in this project because no provider credentials exist. So the
   | phase reachable here is the honest one: money has not been taken, and the
   | screen says so.
   |
   | That is still worth a device run rather than only a widget test. It proves
   | the route exists on the platform, that a cold start straight into
   | /orders/<id>/confirmation works — which is the crash-recovery case the
   | route was placed under Orders to support — and that the screen renders
   | against a real server's answer rather than a fake repository's.
   |
   | The paid phases are covered by widget tests against the real screen with a
   | scripted repository. That is a weaker claim and is recorded as one.
   */
  testWidgets('the confirmation screen opens cold on a real order id', (
    WidgetTester tester,
  ) async {
    await prepare();
    await seedOrderReadyToCheckOut();

    // Straight through the API rather than through the screen: this test is
    // about the confirmation screen, and driving checkout again would make a
    // Module 14 failure arrive as a Module 16 one.
    final Checkout checkout = await serverCheckout();
    final String? checkoutId = checkout.checkoutId;

    if (checkoutId == null) {
      fail('the server prepared no quote, so there is nothing to pay for');
    }

    final String orderId = (await orderApi.place(
      tripId: trip.id,
      checkoutId: checkoutId,
    )).id;

    // A payment target, not an order. The server has minted no number.
    final List<Map<String, dynamic>> orders = await ordersFor(api);
    expect(
      orders,
      isEmpty,
      reason: 'nothing was paid for, so nothing may appear as an order',
    );

    // A cold start directly at the route, exactly as a customer relaunching
    // after the app was killed would arrive.
    await launchSignedIn(
      tester,
      customer: customer,
      location: Routes.orderConfirmationPath(orderId),
    );

    await waitFor(
      tester,
      find.byKey(const ValueKey<String>('confirmation-placed')),
      describe: 'the confirmation screen to report on an unpaid order',
    );

    // No order number, because the server has correctly not minted one. This
    // is the Module 16 boundary seen from the client: the screen renders an
    // order that is not yet an order, and does not invent a reference for it.
    expect(
      find.byKey(const ValueKey<String>('confirmation-order-number')),
      findsNothing,
    );

    // No pickup credential either -- there is nothing to collect.
    expect(
      find.byKey(const ValueKey<String>('confirmation-pickup-card')),
      findsNothing,
    );

    // And nothing anywhere claims a payment failed. Checked on the device
    // because this is where the phase is decided from a real HTTP answer.
    expect(
      find.byKey(const ValueKey<String>('confirmation-network-error')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('confirmation-unauthorized')),
      findsNothing,
    );
  });

  // ------------------------------------------- Module 17, as far as it reaches

  /*
   | Order tracking on a real device, for an order nobody has paid for.
   |
   | WHAT THIS REACHES. The tracking screen's job is to render whatever status
   | the server reports. Reaching ACCEPTED or COOKING on a device would need
   | either a captured payment (impossible here -- no provider credentials) or
   | a customer-facing endpoint that moves an order, which is exactly the
   | security defect Module 17 exists to avoid. So what runs on hardware is the
   | part that does not need either: the route exists, the screen loads against
   | a real server, and it renders the real status of a real order.
   |
   | The transition-driven states are covered by backend tests against the real
   | service and by widget tests against the real screen. That is a weaker
   | claim than a device run and is recorded as one.
   */
  testWidgets('the tracking screen opens cold and shows the server status', (
    WidgetTester tester,
  ) async {
    await prepare();
    await seedOrderReadyToCheckOut();

    final Checkout checkout = await serverCheckout();
    final String? checkoutId = checkout.checkoutId;

    if (checkoutId == null) {
      fail('the server prepared no quote, so there is nothing to track');
    }

    final String orderId = (await orderApi.place(
      tripId: trip.id,
      checkoutId: checkoutId,
    )).id;

    // A cold start straight at the route, as a customer returning to a killed
    // app would arrive.
    await launchSignedIn(
      tester,
      customer: customer,
      location: Routes.orderTrackingPath(orderId),
    );

    await waitFor(
      tester,
      find.byKey(const ValueKey<String>('tracking-loaded')),
      describe: 'the tracking screen to load this order from the server',
    );

    // The timeline came from the server, not from anything this app worked out.
    expect(find.byKey(const ValueKey<String>('tracking-timeline')), findsOne);
    expect(find.byKey(const ValueKey<String>('tracking-status')), findsOne);

    /*
     * The Module 17 rule, checked where it is cheapest to break: the screen
     * offers nothing that would change the order. A control here would be a
     * security defect rather than a feature, and a device run is the only
     * place a stray debug button would actually be reachable.
     */
    for (final String forbidden in <String>[
      'Mark as ready',
      'Confirm pickup',
      'Cancel order',
    ]) {
      expect(find.text(forbidden), findsNothing, reason: forbidden);
    }

    // And it does not claim to be something it is not.
    expect(find.text('LIVE'), findsNothing);
  });

  // ------------------------------------------------------ when things change

  testWidgets('editing the cart makes the quote stale and it refreshes', (
    WidgetTester tester,
  ) async {
    await prepare();
    await seedOrderReadyToCheckOut();

    await openCheckout(tester);
    await scrollTo(tester, find.text('Total to pay'));

    final Checkout before = await serverCheckout();

    // A second helping, over HTTP — the cart's version moves, and the
    // fingerprint the quote was written against no longer matches.
    await menus.addToCart(
      tripId: trip.id,
      restaurantId: restaurant.id,
      itemId: item.item.id,
      variantId: variantNamed('Large'),
      optionIds: <String>[optionNamed('Mild')],
      quantity: 1,
    );

    await tester.drag(find.byType(Scrollable).first, const Offset(0, 400));
    await settle(tester);

    final Checkout after = await serverCheckout();

    expect(
      after.commercial.payableTotal.amountMinor,
      greaterThan(before.commercial.payableTotal.amountMinor),
      reason: 'a second helping did not change the payable amount',
    );
  });
}

/// This customer's orders, straight from the server.
///
/// Deliberately not wrapped in a try/catch any more. It was, while the endpoint
/// did not exist and a 404 was the right answer; now the endpoint exists, and
/// swallowing an error here would turn a broken orders API into a passing test
/// reporting an empty list.
Future<List<Map<String, dynamic>>> ordersFor(ApiClient api) async {
  // `authenticated: true` is the whole point of this line, and leaving it out
  // is what failed this test on both platforms for five runs. ApiClient's
  // `get` takes `{bool authenticated = false}`, so the default sends no
  // Authorization header at all and the server answers 401 — correctly. Every
  // repository in lib/ passes it; this helper was the only caller in the
  // codebase that did not.
  //
  // The 401 was never the mystery. It was thrown loudly, on the first run,
  // exactly as it should have been — the mystery was three defects in the CI
  // plumbing that meant no run ever printed it. Two fixes were pushed against
  // guesses in the meantime, and neither was the cause.
  //
  // ApiClient also unwraps the envelope — its own comment says it "returns
  // whatever was under `data`" — so this reads `orders`, not `data.orders`.
  // An earlier version got that wrong too, and the version before that was
  // wrapped in a try/catch returning 0 while the assertion expected 0, so it
  // passed for a reason unrelated to what it claimed to check. Dropping the
  // try/catch is what let this surface as a failure rather than an empty list.
  final Map<String, dynamic> body = await api.get(
    '/customer/orders',
    authenticated: true,
  );

  return <Map<String, dynamic>>[
    for (final Object? entry
        in (body['orders'] as List<Object?>? ?? const <Object?>[]))
      if (entry is Map<String, dynamic>) entry,
  ];
}
