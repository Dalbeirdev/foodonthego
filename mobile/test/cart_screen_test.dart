import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/core/network/api_error_code.dart';
import 'package:foodonthego/core/network/api_exception.dart';
import 'package:foodonthego/domain/models/cart.dart';
import 'package:foodonthego/domain/models/cart_revalidation.dart';
import 'package:foodonthego/domain/models/customer_summary.dart';
import 'package:foodonthego/domain/models/home_dashboard.dart';
import 'package:foodonthego/domain/models/money.dart';

import 'support/harness.dart';

/// The cart, as a customer meets it.
///
/// The theme is that **the screen decides nothing about money**. Several tests
/// below change a quantity and then assert the total is the one the server
/// sent, not the one arithmetic would suggest — because a client that computed
/// its own would be right most days and wrong on the day a price moved.
///
/// The second theme is that closing is not deleting, and that removing is never
/// something the app does on the customer's behalf.
void main() {
  Future<FakeCartRepository> open(
    WidgetTester tester, {
    FakeCartRepository? carts,
    Size size = const Size(390, 844),
    double textScale = 1.0,
  }) async {
    usePhoneSurface(tester, size: size);

    final FakeCartRepository repository =
        carts ??
        FakeCartRepository(lines: <CartLine>[sampleCartLine(quantity: 2)]);

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
          carts: repository,
          initialLocation: '/trips/trip-1/cart',
        ),
      ),
    );
    await tester.pumpAndSettle();

    return repository;
  }

  // --- reading -------------------------------------------------------------

  testWidgets('shows what was chosen, in full', (WidgetTester tester) async {
    await open(
      tester,
      carts: FakeCartRepository(
        lines: <CartLine>[
          sampleCartLine(
            quantity: 2,
            specialInstructions: 'Less spicy please',
            modifiers: const <CartLineModifier>[
              CartLineModifier(groupName: 'Spice level', optionName: 'Mild'),
            ],
          ),
        ],
      ),
    );

    // A cart is where somebody checks that the thing they configured three
    // screens ago is the thing they are about to buy. A line that said only
    // "Paneer Tikka ×2" could not be checked.
    expect(find.text('Paneer Tikka'), findsOneWidget);
    expect(find.text('Large · Mild'), findsOneWidget);
    expect(find.text('Note: Less spicy please'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('shows the server figures and nothing it worked out itself', (
    WidgetTester tester,
  ) async {
    await open(
      tester,
      carts: FakeCartRepository(lines: <CartLine>[sampleCartLine(quantity: 2)])
        ..taxRateBps = 500
        ..packagingFeeMinor = 2000
        ..platformFeeMinor = 1000,
    );

    // 658.00 subtotal, 32.90 tax, 20.00 packaging, 10.00 service = 720.90.
    expect(find.text('₹658'), findsWidgets);
    expect(find.text('₹32.90'), findsOneWidget);
    expect(find.text('₹20'), findsOneWidget);
    expect(find.text('₹10'), findsOneWidget);
    expect(find.text('₹720.90'), findsOneWidget);
  });

  testWidgets('a charge of nothing gets no row', (WidgetTester tester) async {
    await open(tester);

    // "Service fee ₹0.00" is a line a customer has to read to discover it is
    // nothing. The total is always shown; the nothings are not.
    expect(find.text('Taxes'), findsNothing);
    expect(find.text('Packaging'), findsNothing);
    expect(find.text('Service fee'), findsNothing);
    expect(find.text('Total'), findsOneWidget);
    expect(find.text('Subtotal'), findsOneWidget);
  });

  testWidgets('an empty cart is an empty state, not an error', (
    WidgetTester tester,
  ) async {
    await open(tester, carts: FakeCartRepository());

    expect(find.text('Nothing in your cart yet'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('a journey with no cart at all reads as empty', (
    WidgetTester tester,
  ) async {
    final FakeCartRepository carts = FakeCartRepository()
      ..nextReadError = const ApiException(
        code: ApiErrorCode.cartNotFound,
        message: 'You do not have a cart on this journey.',
      );

    await open(tester, carts: carts);

    // The server has nothing to revalidate and says so. To the customer this is
    // the ordinary screen they would see before adding anything — not a
    // failure with a retry button.
    expect(find.text('Nothing in your cart yet'), findsOneWidget);
    expect(find.text("We couldn't load your cart"), findsNothing);
  });

  // --- changing a quantity -------------------------------------------------

  testWidgets('the plus asks the server and shows the answer', (
    WidgetTester tester,
  ) async {
    final FakeCartRepository carts = await open(tester);

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();

    expect(carts.quantitiesRequested, <int>[3]);
    expect(find.text('3'), findsOneWidget);

    // 329.00 × 3, as the server computed it.
    expect(find.text('₹987'), findsWidgets);
  });

  testWidgets('the minus does nothing at one, and never sends a zero', (
    WidgetTester tester,
  ) async {
    final FakeCartRepository carts = await open(
      tester,
      carts: FakeCartRepository(lines: <CartLine>[sampleCartLine()]),
    );

    final Finder minus = find.byIcon(Icons.remove_rounded);

    expect(
      tester
          .widget<IconButton>(
            find.ancestor(of: minus, matching: find.byType(IconButton)),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(minus, warnIfMissed: false);
    await tester.pumpAndSettle();

    // Zero is not "remove". An off-by-one in a stepper must not destroy what
    // the customer chose, and the request is never even made.
    expect(carts.quantitiesRequested, isEmpty);
    expect(carts.snapshot, hasLength(1));
  });

  testWidgets('a refused quantity is reported and the line is unchanged', (
    WidgetTester tester,
  ) async {
    final FakeCartRepository carts = await open(
      tester,
      carts: FakeCartRepository(
        lines: <CartLine>[sampleCartLine(quantity: 20)],
        maxQuantity: 20,
      ),
    );

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();

    expect(find.textContaining('up to 20'), findsOneWidget);
    expect(carts.snapshot.single.quantity, 20);
  });

  testWidgets('a price rise on an edit is shown rather than charged', (
    WidgetTester tester,
  ) async {
    final FakeCartRepository carts = await open(tester);

    carts.nextWriteError = const ApiException(
      code: ApiErrorCode.priceUpdated,
      message: 'The price of this item has changed. Review it before adding.',
      details: <String, dynamic>{
        'current_unit_price': <String, dynamic>{
          'amount_minor': 39900,
          'currency': 'INR',
        },
      },
    );

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();

    expect(find.textContaining('price'), findsWidgets);

    // Nothing moved. The customer agrees to the new figure before it is
    // charged, or the cart stays as it was.
    expect(carts.snapshot.single.quantity, 2);
    expect(find.text('2'), findsOneWidget);
  });

  // --- removing ------------------------------------------------------------

  testWidgets('removing a line takes it out and leaves the rest', (
    WidgetTester tester,
  ) async {
    final FakeCartRepository carts = await open(
      tester,
      carts: FakeCartRepository(
        lines: <CartLine>[
          sampleCartLine(),
          sampleCartLine(
            id: 'line-2',
            name: 'Masala Chai',
            variantName: null,
            unitPriceMinor: 4900,
          ),
        ],
      ),
    );

    await tester.tap(find.text('Remove').first);
    await tester.pumpAndSettle();

    expect(carts.removeCalls, 1);
    expect(find.text('Paneer Tikka'), findsNothing);
    expect(find.text('Masala Chai'), findsOneWidget);
  });

  testWidgets('removing the last line leaves the empty state', (
    WidgetTester tester,
  ) async {
    await open(
      tester,
      carts: FakeCartRepository(lines: <CartLine>[sampleCartLine()]),
    );

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    // An empty cart is the absence of a cart, and is shown as one.
    expect(find.text('Nothing in your cart yet'), findsOneWidget);
  });

  // --- emptying ------------------------------------------------------------

  testWidgets('emptying is confirmed before anything is destroyed', (
    WidgetTester tester,
  ) async {
    final FakeCartRepository carts = await open(tester);

    await tester.tap(find.text('Empty cart').first);
    await tester.pumpAndSettle();

    expect(find.text('Empty your cart?'), findsOneWidget);

    // Backing out destroys nothing. A destructive action reached by one tap is
    // a destructive action taken by accident.
    await tester.tap(find.text('Keep it'));
    await tester.pumpAndSettle();

    expect(carts.emptyCalls, 0);
    expect(find.text('Paneer Tikka'), findsOneWidget);
  });

  testWidgets('confirming empties the cart', (WidgetTester tester) async {
    final FakeCartRepository carts = await open(tester);

    await tester.tap(find.text('Empty cart').first);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Empty cart').last);
    await tester.pumpAndSettle();

    expect(carts.emptyCalls, 1);
    expect(find.text('Nothing in your cart yet'), findsOneWidget);
  });

  // --- revalidation --------------------------------------------------------

  testWidgets('a price change is shown with both figures', (
    WidgetTester tester,
  ) async {
    final FakeCartRepository carts =
        FakeCartRepository(lines: <CartLine>[sampleCartLine()])
          ..revalidationToReturn = const CartRevalidation(
            canProceed: true,
            unchanged: false,
            restaurantAcceptingOrders: true,
            lines: <CartLineVerdict>[
              CartLineVerdict(
                cartItemId: 'line-1',
                name: 'Paneer Tikka',
                quantity: 1,
                blocksOrdering: false,
                finding: CartFinding.priceIncreased,
                priceWhenAdded: Money(amountMinor: 32900, currency: 'INR'),
                priceNow: Money(amountMinor: 39900, currency: 'INR'),
              ),
            ],
          );

    await open(tester, carts: carts);

    expect(find.text('Prices have changed'), findsOneWidget);
    expect(find.textContaining('Was ₹329'), findsOneWidget);
    expect(find.textContaining('Now ₹399'), findsOneWidget);
  });

  testWidgets('a sold-out line blocks ordering and says so', (
    WidgetTester tester,
  ) async {
    final FakeCartRepository carts =
        FakeCartRepository(lines: <CartLine>[sampleCartLine()])
          ..revalidationToReturn = const CartRevalidation(
            canProceed: false,
            unchanged: false,
            restaurantAcceptingOrders: true,
            lines: <CartLineVerdict>[
              CartLineVerdict(
                cartItemId: 'line-1',
                name: 'Paneer Tikka',
                quantity: 1,
                blocksOrdering: true,
                finding: CartFinding.itemUnavailable,
                message: 'The kitchen has run out of this one.',
              ),
            ],
          );

    await open(tester, carts: carts);

    expect(find.text('Some items need your attention'), findsOneWidget);
    expect(find.text('The kitchen has run out of this one.'), findsOneWidget);

    // The line is still there. The customer removes it; the app does not.
    expect(find.text('Paneer Tikka'), findsOneWidget);
    expect(carts.snapshot, hasLength(1));
  });

  testWidgets('a finding this build has never heard of still blocks', (
    WidgetTester tester,
  ) async {
    final FakeCartRepository
    carts = FakeCartRepository(lines: <CartLine>[sampleCartLine()])
      ..revalidationToReturn = const CartRevalidation(
        canProceed: false,
        unchanged: false,
        restaurantAcceptingOrders: true,
        lines: <CartLineVerdict>[
          // No finding the enum recognises — as an older build would see a code
          // the server added after it shipped. `blocksOrdering` is the server's
          // own flag, so the block survives.
          CartLineVerdict(
            cartItemId: 'line-1',
            name: 'Paneer Tikka',
            quantity: 1,
            blocksOrdering: true,
            message: 'Something about this item changed.',
          ),
        ],
      );

    await open(tester, carts: carts);

    expect(find.text('Some items need your attention'), findsOneWidget);
  });

  testWidgets('a closed kitchen outranks a price change', (
    WidgetTester tester,
  ) async {
    final FakeCartRepository carts =
        FakeCartRepository(lines: <CartLine>[sampleCartLine()])
          ..revalidationToReturn = const CartRevalidation(
            canProceed: false,
            unchanged: false,
            restaurantAcceptingOrders: false,
            lines: <CartLineVerdict>[
              CartLineVerdict(
                cartItemId: 'line-1',
                name: 'Paneer Tikka',
                quantity: 1,
                blocksOrdering: false,
                finding: CartFinding.priceIncreased,
                priceWhenAdded: Money(amountMinor: 32900, currency: 'INR'),
                priceNow: Money(amountMinor: 39900, currency: 'INR'),
              ),
            ],
          );

    await open(tester, carts: carts);

    // A customer who cannot order here does not need to be told the paneer went
    // up by seventy rupees first.
    expect(find.text('This kitchen has stopped taking orders'), findsOneWidget);
    expect(find.text('Prices have changed'), findsNothing);
  });

  // --- failures ------------------------------------------------------------

  testWidgets('a load failure offers the move that fixes it', (
    WidgetTester tester,
  ) async {
    final FakeCartRepository carts = FakeCartRepository()
      ..nextReadError = const ApiException.network();

    await open(tester, carts: carts);

    expect(find.text("You're offline"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('a journey that is gone offers no retry', (
    WidgetTester tester,
  ) async {
    final FakeCartRepository carts = FakeCartRepository()
      ..nextReadError = const ApiException(
        code: ApiErrorCode.tripNotFound,
        message: 'Journey not found.',
      );

    await open(tester, carts: carts);

    // Asking again cannot bring a deleted journey back. A retry that cannot
    // work is worse than none.
    expect(find.text('That journey is gone'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });

  // --- what is never sent --------------------------------------------------

  testWidgets('an edit sends a count and an idempotency key, never a price', (
    WidgetTester tester,
  ) async {
    final FakeCartRepository carts = await open(tester);

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();

    // The repository interface has no price parameter, so this is structural
    // rather than a check somebody has to remember — the assertion is here so
    // that adding one would break a test rather than pass silently.
    expect(carts.quantitiesRequested, <int>[3]);
    expect(carts.keysUsed.single, isNotNull);
    expect(carts.keysUsed.single, startsWith('cart-'));
  });
}
