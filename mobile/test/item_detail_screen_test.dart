import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/core/network/api_error_code.dart';
import 'package:foodonthego/core/network/api_exception.dart';
import 'package:foodonthego/domain/models/cart.dart';
import 'package:foodonthego/domain/models/customer_summary.dart';
import 'package:foodonthego/domain/models/home_dashboard.dart';
import 'package:foodonthego/domain/models/menu_customization.dart';
import 'package:foodonthego/domain/models/money.dart';
import 'package:foodonthego/domain/models/restaurant_detail.dart';
import 'package:foodonthego/domain/models/restaurant_menu.dart';

import 'support/harness.dart';

/// Configuring a dish, as a customer meets it.
///
/// The theme is that the screen states a rule before the customer can break it,
/// and never invents anything: no fabricated "Regular", no preselected paid
/// option, no promise about what the kitchen will do with a note.
void main() {
  Future<FakeMenuRepository> open(
    WidgetTester tester, {
    FakeMenuRepository? menus,
    FakeCartRepository? carts,
    MenuItemPreview? preview,
    Size size = const Size(390, 844),
    double textScale = 1.0,
  }) async {
    usePhoneSurface(tester, size: size);

    final FakeMenuRepository repository = menus ?? FakeMenuRepository();
    repository.previewToReturn = preview ?? sampleItemPreview();

    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: wrapApp(
          repository: StubHomeRepository.value(
            const HomeDashboard(
              customer: CustomerSummary(fullName: 'Rahul Sharma'),
            ),
          ),
          routes: FakeRouteRepository(calculated: true),
          menus: repository,
          carts: carts,
          initialLocation:
              '/trips/trip-1/route/restaurants/restaurant-1/menu/items/item-1',
        ),
      ),
    );
    await tester.pumpAndSettle();

    return repository;
  }

  /// The screen is a ListView; anything below the fold is never built.
  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  /// Answers the one required group, so the button quotes a price rather than
  /// asking for the missing choice.
  Future<void> answerRequired(WidgetTester tester) async {
    await scrollTo(tester, find.text('Mild'));
    await tester.tap(find.text('Mild'));
    await tester.pumpAndSettle();
  }

  Future<void> tapAdd(WidgetTester tester) async {
    await tester.tap(find.byType(FilledButton).last);
    await tester.pumpAndSettle();
  }

  group('the dish', () {
    testWidgets('shows its name, price and description', (
      WidgetTester tester,
    ) async {
      await open(tester);

      expect(find.text('Paneer Tikka'), findsWidgets);

      // Twice, correctly: the dish's base price under the name, and the
      // Regular variant's own price in the size list.
      expect(find.text('₹249'), findsNWidgets(2));
      expect(find.text('Cottage cheese in the tandoor.'), findsOneWidget);
    });

    testWidgets('a dish with no sizes gets no size selector', (
      WidgetTester tester,
    ) async {
      await open(
        tester,
        preview: sampleItemPreview(
          customization: sampleCustomization(withVariants: false),
        ),
      );

      // Not a fabricated "Regular".
      expect(find.text('Choose a size'), findsNothing);
      expect(find.text('Spice level'), findsOneWidget);
    });

    testWidgets('a dish with nothing configurable still works', (
      WidgetTester tester,
    ) async {
      await open(
        tester,
        preview: sampleItemPreview(
          customization: sampleCustomization(
            withVariants: false,
            groups: const <MenuModifierGroup>[],
          ),
        ),
      );

      expect(find.text('Choose a size'), findsNothing);
      expect(find.textContaining('Add to cart'), findsOneWidget);
    });
  });

  group('sizes', () {
    testWidgets('open on the configured default', (WidgetTester tester) async {
      await open(tester);

      expect(find.text('Choose a size'), findsOneWidget);
      expect(find.text('Regular'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Regular. 249 rupees. Selected'),
        findsOneWidget,
      );

      await answerRequired(tester);

      expect(find.textContaining('Add to cart · ₹249'), findsOneWidget);
    });

    testWidgets('a sold-out size is shown, disabled and labelled', (
      WidgetTester tester,
    ) async {
      await open(tester);

      // Hiding it would leave a customer who came for the family portion
      // wondering whether they misremembered.
      expect(find.text('Family (serves 4)'), findsOneWidget);
      expect(find.text('Unavailable'), findsWidgets);
    });

    testWidgets('choosing one moves the price on the button', (
      WidgetTester tester,
    ) async {
      await open(tester);

      await tester.tap(find.text('Large'));
      await tester.pumpAndSettle();

      // Absolute, not additive.
      expect(find.textContaining('₹329'), findsWidgets);
    });

    testWidgets('a sold-out size cannot be chosen', (
      WidgetTester tester,
    ) async {
      await open(tester);
      await answerRequired(tester);

      await tester.tap(find.text('Family (serves 4)'));
      await tester.pumpAndSettle();

      // Still on Regular.
      expect(find.textContaining('Add to cart · ₹249'), findsOneWidget);
    });
  });

  group('the rules are stated before they are broken', () {
    testWidgets('a required group says so above its options', (
      WidgetTester tester,
    ) async {
      await open(tester);

      await scrollTo(tester, find.text('Spice level'));

      expect(find.text('Required · Choose 1'), findsOneWidget);
    });

    testWidgets('an optional group says how many', (WidgetTester tester) async {
      await open(tester);

      await scrollTo(tester, find.text('Add extras'));

      expect(find.text('Optional · Choose up to 2'), findsOneWidget);
    });

    testWidgets('a range group says the range', (WidgetTester tester) async {
      await open(
        tester,
        preview: sampleItemPreview(
          customization: sampleCustomization(
            groups: const <MenuModifierGroup>[
              MenuModifierGroup(
                id: 'group-sides',
                name: 'Pick your sides',
                minSelect: 2,
                maxSelect: 4,
                options: <MenuModifierOption>[
                  MenuModifierOption(
                    id: 'a',
                    name: 'Mint chutney',
                    priceDelta: Money(amountMinor: 0, currency: 'INR'),
                  ),
                  MenuModifierOption(
                    id: 'b',
                    name: 'Onion salad',
                    priceDelta: Money(amountMinor: 0, currency: 'INR'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

      await scrollTo(tester, find.text('Pick your sides'));

      expect(find.text('Required · Choose 2 to 4'), findsOneWidget);
    });
  });

  group('options', () {
    testWidgets('a paid one shows what it adds', (WidgetTester tester) async {
      await open(tester);

      await scrollTo(tester, find.text('Extra Cheese'));

      expect(find.text('+₹40'), findsOneWidget);
    });

    testWidgets('a free one shows no price at all', (
      WidgetTester tester,
    ) async {
      await open(tester);

      await scrollTo(tester, find.text('Mild'));

      // The absence of a price is the clearest way to say a choice is free.
      expect(find.text('₹0'), findsNothing);
      expect(find.text('+₹0'), findsNothing);
    });

    testWidgets('a paid one is never preselected', (WidgetTester tester) async {
      await open(tester);
      await answerRequired(tester);

      // Starting a customer at "Extra Cheese +₹40" and letting them find it at
      // the total is a dark pattern. The total is the dish's own price.
      expect(find.textContaining('Add to cart · ₹249'), findsOneWidget);
    });

    testWidgets('reaching the ceiling explains itself', (
      WidgetTester tester,
    ) async {
      await open(tester);

      await scrollTo(tester, find.text('Extra Cheese'));
      await tester.tap(find.text('Extra Cheese'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Jalapeños'));
      await tester.pumpAndSettle();

      // The disabled rows get an explanation next to them rather than looking
      // broken.
      expect(find.text('You can choose up to 2.'), findsOneWidget);
    });

    testWidgets('a sold-out option is shown and labelled', (
      WidgetTester tester,
    ) async {
      await open(tester);

      await scrollTo(tester, find.text('Extra Cashew'));

      expect(find.text('Extra Cashew'), findsOneWidget);
    });
  });

  group('quantity', () {
    testWidgets('starts at one and cannot go below', (
      WidgetTester tester,
    ) async {
      await open(tester);

      await scrollTo(tester, find.text('Quantity'));

      expect(find.bySemanticsLabel('Quantity, 1'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Remove one'));
      await tester.pumpAndSettle();

      // A customer who wants none simply does not add the dish.
      expect(find.bySemanticsLabel('Quantity, 1'), findsOneWidget);
    });

    testWidgets('multiplies the price on the button', (
      WidgetTester tester,
    ) async {
      await open(tester);
      await answerRequired(tester);

      await scrollTo(tester, find.text('Quantity'));
      await tester.tap(find.bySemanticsLabel('Add one more'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Add to cart · ₹498'), findsOneWidget);
    });
  });

  group('the note', () {
    testWidgets('is optional and does not promise anything', (
      WidgetTester tester,
    ) async {
      await open(tester);

      await scrollTo(tester, find.text('Special instructions'));

      expect(find.text('Optional'), findsWidgets);
      expect(find.textContaining('will do what they can'), findsOneWidget);

      // Never a promise the platform cannot keep.
      expect(find.textContaining('will definitely'), findsNothing);
      expect(find.textContaining('guarantee'), findsNothing);
    });

    testWidgets('stops at the length the server accepts', (
      WidgetTester tester,
    ) async {
      await open(tester);

      await scrollTo(tester, find.text('Special instructions'));

      final TextField field = tester.widget<TextField>(find.byType(TextField));

      expect(field.maxLength, 300);
    });
  });

  group('adding', () {
    testWidgets('an unanswered required group blocks and is marked', (
      WidgetTester tester,
    ) async {
      final FakeMenuRepository menus = await open(tester);

      await tapAdd(tester);

      expect(find.text('Choose 1 option to continue.'), findsOneWidget);

      // Nothing went to the server.
      expect(menus.addCalls, 0);
    });

    testWidgets('the button says what is missing rather than going dead', (
      WidgetTester tester,
    ) async {
      await open(tester);

      // A disabled button with no explanation is a customer wondering what
      // they did wrong.
      expect(find.text('Choose required options'), findsOneWidget);
    });

    testWidgets('a complete configuration is sent and confirmed', (
      WidgetTester tester,
    ) async {
      final FakeMenuRepository menus = await open(tester);

      await scrollTo(tester, find.text('Mild'));
      await tester.tap(find.text('Mild'));
      await tester.pumpAndSettle();

      await tapAdd(tester);

      expect(menus.addCalls, 1);
      expect(menus.addRequests.single.optionIds, <String>['option-mild']);

      // Subtle, not a celebration: the customer is mid-task.
      expect(find.text('Added to cart · 1 item in your cart'), findsOneWidget);
    });

    testWidgets('a sold-out dish offers no way to order', (
      WidgetTester tester,
    ) async {
      await open(
        tester,
        preview: sampleItemPreview(
          item: sampleMenuItem(stockStatus: MenuItemStockStatus.soldOut),
        ),
      );

      expect(find.text('Sold out'), findsWidgets);
      expect(find.textContaining('Add to cart'), findsNothing);
    });

    testWidgets('a paused restaurant says so and takes nothing', (
      WidgetTester tester,
    ) async {
      await open(
        tester,
        preview: sampleItemPreview(
          ordering: RestaurantOrderingState.openPaused,
        ),
      );

      expect(find.text('Not taking orders right now'), findsWidgets);
      expect(find.textContaining('Add to cart'), findsNothing);
    });
  });

  group('failures', () {
    /// Taps a control inside the failure notice.
    ///
    /// The notice is in the scroll view, so a control below the fold exists in
    /// the tree and is not on screen. `tester.tap` on one of those misses
    /// silently and surfaces much later as "the button did nothing".
    Future<void> tapNotice(WidgetTester tester, String label) async {
      final Finder button = find.text(label);

      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    Future<FakeMenuRepository> readyToAdd(
      WidgetTester tester, {
      FakeCartRepository? carts,
    }) async {
      final FakeMenuRepository menus = await open(tester, carts: carts);

      await scrollTo(tester, find.text('Mild'));
      await tester.tap(find.text('Mild'));
      await tester.pumpAndSettle();

      return menus;
    }

    testWidgets('a network failure offers a retry and keeps the choices', (
      WidgetTester tester,
    ) async {
      final FakeMenuRepository menus = await readyToAdd(tester);

      menus.nextAddError = const ApiException.network();

      await tapAdd(tester);

      expect(find.textContaining("You're offline"), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.textContaining('Your choices are kept'), findsOneWidget);
    });

    testWidgets('a sold-out race says so and offers no retry', (
      WidgetTester tester,
    ) async {
      final FakeMenuRepository menus = await readyToAdd(tester);

      menus.nextAddError = const ApiException(
        code: ApiErrorCode.itemSoldOut,
        message: 'Gone.',
        status: 409,
      );

      await tapAdd(tester);

      expect(find.text('Just sold out'), findsOneWidget);

      // It will not come back because somebody pressed a button.
      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('a cart conflict names the other restaurant', (
      WidgetTester tester,
    ) async {
      final FakeMenuRepository menus = await readyToAdd(tester);

      // The refusal as the server actually sends it: a generic message, with
      // the restaurant named in `details`. This fixture used to put the name in
      // the message, which no server does — the assertion passed because the
      // screen echoed the message back, not because anything read the name.
      menus.nextAddError = const ApiException(
        code: ApiErrorCode.cartRestaurantConflict,
        message: 'Your cart has items from a different restaurant.',
        status: 409,
        details: <String, dynamic>{
          'cart_id': 'cart-1',
          'restaurant_id': 'restaurant-9',
          'restaurant_name': 'Highway Spice Kitchen',
        },
      );

      await tapAdd(tester);

      expect(find.text('Your cart has other items'), findsOneWidget);
      expect(find.textContaining('Highway Spice Kitchen'), findsWidgets);
    });

    testWidgets('a cart conflict offers two choices and no third', (
      WidgetTester tester,
    ) async {
      final FakeMenuRepository menus = await readyToAdd(tester);

      menus.nextAddError = const ApiException(
        code: ApiErrorCode.cartRestaurantConflict,
        message: 'Your cart has items from a different restaurant.',
        status: 409,
        details: <String, dynamic>{'restaurant_name': 'Highway Spice Kitchen'},
      );

      await tapAdd(tester);

      // Both explicit, and nothing that empties a cart on the customer's
      // behalf. See docs/27-cart-management.md.
      expect(find.text('Keep my cart'), findsOneWidget);
      expect(find.text('Start a new cart'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('keeping the cart abandons the add and touches nothing', (
      WidgetTester tester,
    ) async {
      final FakeCartRepository carts = FakeCartRepository(
        lines: <CartLine>[sampleCartLine()],
      );
      final FakeMenuRepository menus = await readyToAdd(tester, carts: carts);

      menus.nextAddError = const ApiException(
        code: ApiErrorCode.cartRestaurantConflict,
        message: 'Your cart has items from a different restaurant.',
        status: 409,
        details: <String, dynamic>{'restaurant_name': 'Highway Spice Kitchen'},
      );

      final int addsBefore = menus.addCalls;

      await tapAdd(tester);
      await tapNotice(tester, 'Keep my cart');

      expect(find.text('Your cart has other items'), findsNothing);

      // Nothing was closed and nothing was re-sent. "Keep my cart" abandons the
      // add; it is not a quieter way of doing the other thing.
      expect(carts.emptyCalls, 0);
      expect(carts.snapshot, hasLength(1));
      expect(menus.addCalls, addsBefore + 1);
    });

    testWidgets('starting a new cart asks before destroying the old one', (
      WidgetTester tester,
    ) async {
      final FakeCartRepository carts = FakeCartRepository(
        lines: <CartLine>[sampleCartLine()],
      );
      final FakeMenuRepository menus = await readyToAdd(tester, carts: carts);

      menus.nextAddError = const ApiException(
        code: ApiErrorCode.cartRestaurantConflict,
        message: 'Your cart has items from a different restaurant.',
        status: 409,
        details: <String, dynamic>{'restaurant_name': 'Highway Spice Kitchen'},
      );

      await tapAdd(tester);
      await tapNotice(tester, 'Start a new cart');

      expect(find.text('Empty your current cart?'), findsOneWidget);
      expect(find.textContaining('Highway Spice Kitchen'), findsWidgets);

      // Backing out of the confirmation destroys nothing.
      await tester.tap(find.widgetWithText(TextButton, 'Keep my cart').last);
      await tester.pumpAndSettle();

      expect(carts.emptyCalls, 0);
      expect(carts.snapshot, hasLength(1));
    });

    testWidgets('confirming closes the old cart and adds the dish', (
      WidgetTester tester,
    ) async {
      final FakeCartRepository carts = FakeCartRepository(
        lines: <CartLine>[sampleCartLine()],
      );
      final FakeMenuRepository menus = await readyToAdd(tester, carts: carts);

      menus.nextAddError = const ApiException(
        code: ApiErrorCode.cartRestaurantConflict,
        message: 'Your cart has items from a different restaurant.',
        status: 409,
        details: <String, dynamic>{'restaurant_name': 'Highway Spice Kitchen'},
      );

      final int addsBefore = menus.addCalls;

      await tapAdd(tester);
      await tapNotice(tester, 'Start a new cart');

      await tester.tap(
        find.widgetWithText(TextButton, 'Start a new cart').last,
      );
      await tester.pumpAndSettle();

      // The old cart closed because the customer said to, and the add retried.
      expect(carts.emptyCalls, 1);
      expect(carts.snapshot, isEmpty);
      expect(menus.addCalls, addsBefore + 2);
      expect(find.text('Your cart has other items'), findsNothing);
    });

    testWidgets('a cross-journey conflict does not invent a restaurant name', (
      WidgetTester tester,
    ) async {
      final FakeMenuRepository menus = await readyToAdd(tester);

      // The server names the *journey* here, not the kitchen. "Your cart has
      // items from " with nothing after it is worse than a sentence that never
      // promised a name.
      menus.nextAddError = const ApiException(
        code: ApiErrorCode.cartTripConflict,
        message: 'You have items in a cart for a different journey.',
        status: 409,
        details: <String, dynamic>{'cart_id': 'cart-1', 'trip_id': 'trip-9'},
      );

      await tapAdd(tester);

      expect(
        find.textContaining('belongs to a different journey'),
        findsOneWidget,
      );
      expect(find.text('Start a new cart'), findsOneWidget);
    });

    testWidgets('a price rise shows both figures and asks', (
      WidgetTester tester,
    ) async {
      final FakeMenuRepository menus = await readyToAdd(tester);

      menus.nextAddError = const ApiException(
        code: ApiErrorCode.priceUpdated,
        message: 'The price changed.',
        status: 409,
        details: <String, dynamic>{
          'current_unit_price': <String, dynamic>{
            'amount_minor': 26900,
            'currency': 'INR',
          },
        },
      );

      await tapAdd(tester);

      expect(find.text('The price changed'), findsOneWidget);

      // Both figures. "The price changed" without saying to what is not
      // information.
      expect(find.textContaining('was ₹249 and is now ₹269'), findsOneWidget);
      expect(find.text('Add at ₹269'), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);
    });

    testWidgets('accepting the new price adds at it', (
      WidgetTester tester,
    ) async {
      final FakeMenuRepository menus = await readyToAdd(tester);

      menus.nextAddError = const ApiException(
        code: ApiErrorCode.priceUpdated,
        message: 'The price changed.',
        status: 409,
        details: <String, dynamic>{
          'current_unit_price': <String, dynamic>{
            'amount_minor': 26900,
            'currency': 'INR',
          },
        },
      );

      await tapAdd(tester);

      menus.serverUnitPriceMinor = (int _) => 26900;

      await scrollTo(tester, find.text('Add at ₹269'));
      await tester.tap(find.text('Add at ₹269'));
      await tester.pumpAndSettle();

      expect(menus.addCalls, 2);
      expect(menus.addRequests.last.quotedUnitPriceMinor, isNull);
    });

    testWidgets('an item that has gone offers the way back', (
      WidgetTester tester,
    ) async {
      final FakeMenuRepository menus = FakeMenuRepository()
        ..nextItemError = const ApiException(
          code: ApiErrorCode.itemNotFound,
          message: 'Gone.',
          status: 404,
        );

      await open(tester, menus: menus);

      expect(find.text('No longer on the menu'), findsOneWidget);
      expect(find.text('Back to restaurant'), findsOneWidget);
    });
  });

  group('accessibility', () {
    testWidgets('a size is announced with its price and its state', (
      WidgetTester tester,
    ) async {
      await open(tester);

      expect(
        find.bySemanticsLabel('Regular. 249 rupees. Selected'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Large. 329 rupees. Not selected'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp('Family.*Unavailable')),
        findsOneWidget,
      );
    });

    testWidgets('a free option is announced as free, not as blank', (
      WidgetTester tester,
    ) async {
      await open(tester);

      await scrollTo(tester, find.text('Mild'));

      // A screen reader cannot see that the trailing column is empty.
      expect(
        find.bySemanticsLabel('Mild. No extra charge. Not selected'),
        findsOneWidget,
      );
    });

    testWidgets('a paid option is announced with what it adds', (
      WidgetTester tester,
    ) async {
      await open(tester);

      await scrollTo(tester, find.text('Extra Cheese'));

      expect(
        find.bySemanticsLabel('Extra Cheese. Adds 40 rupees. Not selected'),
        findsOneWidget,
      );
    });

    testWidgets('the quantity says what it counts', (
      WidgetTester tester,
    ) async {
      await open(tester);

      await scrollTo(tester, find.text('Quantity'));

      // A bare "1" between two buttons tells a screen-reader user nothing.
      expect(find.bySemanticsLabel('Quantity, 1'), findsOneWidget);
    });

    testWidgets('the button announces the total it will charge', (
      WidgetTester tester,
    ) async {
      await open(tester);

      await scrollTo(tester, find.text('Mild'));
      await tester.tap(find.text('Mild'));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel(RegExp('Add to cart · ₹249')),
        findsOneWidget,
      );
    });

    testWidgets('the screen survives the largest text a phone offers', (
      WidgetTester tester,
    ) async {
      await open(tester, textScale: 2.0);

      expect(tester.takeException(), isNull);
      expect(find.text('Paneer Tikka'), findsWidgets);
    });

    testWidgets('the screen fits a 320 dp phone', (WidgetTester tester) async {
      await open(tester, size: const Size(320, 568));

      expect(tester.takeException(), isNull);

      // The button is reachable and says what it will do.
      expect(find.text('Choose required options'), findsOneWidget);
    });
  });
}
