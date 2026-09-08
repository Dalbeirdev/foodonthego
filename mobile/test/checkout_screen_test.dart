import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/core/network/api_error_code.dart';
import 'package:foodonthego/core/network/api_exception.dart';
import 'package:foodonthego/domain/models/checkout.dart';
import 'package:foodonthego/domain/models/customer_summary.dart';
import 'package:foodonthego/domain/models/home_dashboard.dart';
import 'package:foodonthego/domain/models/pre_checkout.dart';

import 'support/harness.dart';

/// The last screen before money, as a customer meets it.
///
/// The theme is that **this screen works out no figure and decides no
/// readiness**. Several tests below hand it a body whose parts do not add up to
/// its total, or whose issue list disagrees with its verdict, and require the
/// screen to show the server's answer rather than the one it could compute.
void main() {
  Future<FakeCheckoutRepository> open(
    WidgetTester tester, {
    FakeCheckoutRepository? checkout,
    double textScale = 1.0,
  }) async {
    usePhoneSurface(tester);

    final FakeCheckoutRepository repository =
        checkout ?? FakeCheckoutRepository();

    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: wrapApp(
          repository: StubHomeRepository.value(
            const HomeDashboard(
              customer: CustomerSummary(fullName: 'Rahul Sharma'),
            ),
          ),
          checkouts: repository,
          initialLocation: '/trips/trip-1/cart/pickup/checkout',
        ),
      ),
    );
    await tester.pumpAndSettle();

    return repository;
  }

  /// Scrolls a key into view and taps it.
  Future<void> tapKey(WidgetTester tester, String key) async {
    final Finder target = find.byKey(ValueKey<String>(key));

    await tester.scrollUntilVisible(
      target,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> scrollToBottom(WidgetTester tester) async {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -1200));
    await tester.pumpAndSettle();
  }

  // --- loading --------------------------------------------------------------

  testWidgets('waits rather than showing a price it has not been given', (
    WidgetTester tester,
  ) async {
    usePhoneSurface(tester);

    await tester.pumpWidget(
      wrapApp(
        repository: StubHomeRepository.value(
          const HomeDashboard(
            customer: CustomerSummary(fullName: 'Rahul Sharma'),
          ),
        ),
        checkouts: FakeCheckoutRepository(),
        initialLocation: '/trips/trip-1/cart/pickup/checkout',
      ),
    );

    // One frame in: the request is in flight and nothing has come back.
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.textContaining('₹'), findsNothing);

    await tester.pumpAndSettle();
  });

  testWidgets('opening the screen asks the server once', (
    WidgetTester tester,
  ) async {
    final FakeCheckoutRepository checkout = await open(tester);

    expect(checkout.prepareCalls, 1);
    expect(checkout.validateCalls, 0);
  });

  // --- what the customer sees ----------------------------------------------

  testWidgets('shows the restaurant, the journey, the pickup and the order', (
    WidgetTester tester,
  ) async {
    await open(tester);

    expect(find.text('Highway Spice Kitchen'), findsOneWidget);
    expect(find.text('Delhi → Jaipur'), findsOneWidget);
    expect(find.textContaining('Paneer Tikka'), findsOneWidget);

    // The pickup window on the counter's clock: 12:00 UTC + 70 minutes is
    // 07:40 UTC, which is 1:10 pm in Kolkata — and 1:10 pm is what a customer
    // standing at that counter will see on the wall.
    expect(find.textContaining('1:10 pm'), findsOneWidget);
  });

  testWidgets('the pickup window is never shown on the phone\'s clock', (
    WidgetTester tester,
  ) async {
    await open(tester);

    // 07:40 UTC would render as 7:40 am on a machine set to UTC, which is what
    // `DateTime.parse` alone produces. The counter says 1:10 pm.
    expect(find.textContaining('7:40 am'), findsNothing);
  });

  testWidgets('the quantity and the line total are the server\'s', (
    WidgetTester tester,
  ) async {
    await open(tester);

    expect(find.text('Paneer Tikka ×2'), findsOneWidget);
    expect(find.text('₹498'), findsWidgets);
  });

  // --- the commercial summary ----------------------------------------------

  testWidgets('with nothing configured the payable is the subtotal, said so', (
    WidgetTester tester,
  ) async {
    await open(tester);
    await scrollToBottom(tester);

    // Both figures present and equal, and the reason stated in words.
    expect(find.text('₹498'), findsWidgets);
    expect(
      find.text('No additional charges are currently configured.'),
      findsOneWidget,
    );

    // And nothing invented a row for a rule nobody has set.
    expect(find.text('Tax'), findsNothing);
    expect(find.text('Service fee'), findsNothing);
    expect(find.text('Packaging'), findsNothing);
  });

  testWidgets('a configured charge appears with its real figure', (
    WidgetTester tester,
  ) async {
    final FakeCheckoutRepository checkout = FakeCheckoutRepository()
      ..charges = <({String code, int amountMinor})>[
        (code: 'TAX', amountMinor: 2_490),
      ]
      ..payableTotalMinor = 52_290;

    await open(tester, checkout: checkout);
    await scrollToBottom(tester);

    expect(find.text('Tax'), findsOneWidget);
    expect(find.text('₹24.90'), findsOneWidget);
    expect(find.text('₹522.90'), findsOneWidget);

    // The sentence about nothing being configured is gone, because something
    // is.
    expect(
      find.text('No additional charges are currently configured.'),
      findsNothing,
    );
  });

  testWidgets('a charge configured as zero is shown as a row', (
    WidgetTester tester,
  ) async {
    // The distinction the whole design turns on: "nobody set a packaging fee"
    // and "the packaging fee is nothing" are different facts, and the second
    // belongs on the receipt.
    final FakeCheckoutRepository checkout = FakeCheckoutRepository()
      ..charges = <({String code, int amountMinor})>[
        (code: 'PACKAGING_FEE', amountMinor: 0),
      ];

    await open(tester, checkout: checkout);
    await scrollToBottom(tester);

    expect(find.text('Packaging'), findsOneWidget);
    expect(find.text('₹0'), findsOneWidget);
  });

  testWidgets('a charge code this build never met is shown, not dropped', (
    WidgetTester tester,
  ) async {
    final FakeCheckoutRepository checkout = FakeCheckoutRepository()
      ..charges = <({String code, int amountMinor})>[
        (code: 'CONGESTION_LEVY', amountMinor: 1_500),
      ]
      ..payableTotalMinor = 51_300;

    await open(tester, checkout: checkout);
    await scrollToBottom(tester);

    expect(find.text('CONGESTION_LEVY'), findsOneWidget);
    expect(find.text('₹15'), findsOneWidget);
  });

  testWidgets('the total shown is the server\'s, not the sum of the rows', (
    WidgetTester tester,
  ) async {
    // The parts say 498 + 24.90 = 522.90. The server says 560. A screen that
    // added the rows up would show a figure the customer would not be charged.
    final FakeCheckoutRepository checkout = FakeCheckoutRepository()
      ..charges = <({String code, int amountMinor})>[
        (code: 'TAX', amountMinor: 2_490),
      ]
      ..payableTotalMinor = 56_000;

    await open(tester, checkout: checkout);
    await scrollToBottom(tester);

    expect(find.text('₹560'), findsOneWidget);
    expect(find.text('₹522.90'), findsNothing);
  });

  testWidgets('a discount is shown as a subtraction', (
    WidgetTester tester,
  ) async {
    final FakeCheckoutRepository checkout = FakeCheckoutRepository()
      ..discounts = <({String code, int amountMinor})>[
        (code: 'DISCOUNT', amountMinor: 5_000),
      ]
      ..payableTotalMinor = 44_800;

    await open(tester, checkout: checkout);
    await scrollToBottom(tester);

    expect(find.text('Discount'), findsOneWidget);
    expect(find.text('−₹50'), findsOneWidget);
  });

  // --- proceeding, and where it stops --------------------------------------

  testWidgets('Proceed is offered when the server says the order is ready', (
    WidgetTester tester,
  ) async {
    await open(tester);
    await scrollToBottom(tester);

    final Finder proceed = find.byKey(
      const ValueKey<String>('checkout-proceed'),
    );

    expect(proceed, findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.descendant(of: proceed, matching: find.byType(FilledButton)),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('and it says plainly that payment is not switched on yet', (
    WidgetTester tester,
  ) async {
    await open(tester);
    await scrollToBottom(tester);

    expect(
      find.byKey(const ValueKey<String>('checkout-payment-coming')),
      findsOneWidget,
    );
  });

  testWidgets('Proceed asks the server again and echoes its checkout id', (
    WidgetTester tester,
  ) async {
    final FakeCheckoutRepository checkout = await open(tester);

    await scrollToBottom(tester);
    await tapKey(tester, 'checkout-proceed');

    expect(checkout.validateCalls, 1);

    // The id the server issued, not one the client assembled. The fake refuses
    // anything else, which is what the real server does.
    expect(checkout.checkoutIdsSent.single, checkout.issuedCheckoutId);
  });

  testWidgets('no request the screen makes carries an amount', (
    WidgetTester tester,
  ) async {
    final FakeCheckoutRepository checkout = await open(tester);

    await scrollToBottom(tester);
    await tapKey(tester, 'checkout-proceed');

    // Not "the amounts sent were correct" — there is nowhere to put one. The
    // interface has no parameter for a price and the request has no body.
    expect(checkout.bodiesSent, isNotEmpty);
    for (final Map<String, Object?> body in checkout.bodiesSent) {
      expect(body, isEmpty);
    }
  });

  testWidgets('Proceed is refused when the server says the order is not ready', (
    WidgetTester tester,
  ) async {
    // No issues in the body, and the server still says no. A screen deriving
    // readiness from an empty issue list would take this customer to a payment.
    final FakeCheckoutRepository checkout = FakeCheckoutRepository()
      ..readyForPayment = false;

    await open(tester, checkout: checkout);
    await scrollToBottom(tester);

    expect(
      tester
          .widget<FilledButton>(
            find.descendant(
              of: find.byKey(const ValueKey<String>('checkout-proceed')),
              matching: find.byType(FilledButton),
            ),
          )
          .onPressed,
      isNull,
    );

    // And nothing dangled a payment notice under a button that cannot be used.
    expect(
      find.byKey(const ValueKey<String>('checkout-payment-coming')),
      findsNothing,
    );
  });

  testWidgets('a status this build has never heard of stops the checkout', (
    WidgetTester tester,
  ) async {
    final FakeCheckoutRepository checkout = FakeCheckoutRepository()
      ..status = CheckoutStatus.stale;

    await open(tester, checkout: checkout);
    await scrollToBottom(tester);

    expect(
      tester
          .widget<FilledButton>(
            find.descendant(
              of: find.byKey(const ValueKey<String>('checkout-proceed')),
              matching: find.byType(FilledButton),
            ),
          )
          .onPressed,
      isNull,
    );
  });

  // --- what stops a checkout ------------------------------------------------

  testWidgets('a sold-out line is shown in the server\'s own words', (
    WidgetTester tester,
  ) async {
    final FakeCheckoutRepository checkout = FakeCheckoutRepository()
      ..readyForPayment = false
      ..issues = const <PreCheckoutIssue>[
        PreCheckoutIssue(
          code: PreCheckoutIssueCode.lineUnavailable,
          message: 'Paneer Tikka has sold out.',
          blocking: true,
        ),
      ];

    await open(tester, checkout: checkout);

    expect(find.text('Paneer Tikka has sold out.'), findsOneWidget);
  });

  testWidgets('a paused kitchen is shown in the server\'s own words', (
    WidgetTester tester,
  ) async {
    final FakeCheckoutRepository checkout = FakeCheckoutRepository()
      ..readyForPayment = false
      ..issues = const <PreCheckoutIssue>[
        PreCheckoutIssue(
          code: PreCheckoutIssueCode.restaurantNotAcceptingOrders,
          message: 'Highway Spice Kitchen has stopped taking orders.',
          blocking: true,
        ),
      ];

    await open(tester, checkout: checkout);

    expect(
      find.text('Highway Spice Kitchen has stopped taking orders.'),
      findsOneWidget,
    );
  });

  testWidgets('a price change is shown in the server\'s own words', (
    WidgetTester tester,
  ) async {
    final FakeCheckoutRepository checkout = FakeCheckoutRepository()
      ..readyForPayment = false
      ..issues = const <PreCheckoutIssue>[
        PreCheckoutIssue(
          code: PreCheckoutIssueCode.priceIncreased,
          message: 'Paneer Tikka now costs ₹269.',
          blocking: true,
        ),
      ];

    await open(tester, checkout: checkout);

    expect(find.text('Paneer Tikka now costs ₹269.'), findsOneWidget);
  });

  testWidgets('an issue code this build never met still reaches the customer', (
    WidgetTester tester,
  ) async {
    final FakeCheckoutRepository checkout = FakeCheckoutRepository()
      ..readyForPayment = false
      ..issues = const <PreCheckoutIssue>[
        PreCheckoutIssue(
          message: 'The counter is closed for a public holiday.',
          blocking: true,
        ),
      ];

    await open(tester, checkout: checkout);

    // The message came with the code, so an old build renders a new refusal as
    // a sentence rather than swallowing it.
    expect(
      find.text('The counter is closed for a public holiday.'),
      findsOneWidget,
    );
  });

  // --- the quote's own state ------------------------------------------------

  testWidgets('an expired quote says so and offers to fetch a current one', (
    WidgetTester tester,
  ) async {
    final FakeCheckoutRepository checkout = FakeCheckoutRepository()
      ..status = CheckoutStatus.expired
      ..readyForPayment = false;

    await open(tester, checkout: checkout);

    expect(find.text('Checkout details need refreshing'), findsOneWidget);

    checkout.status = CheckoutStatus.active;
    checkout.readyForPayment = true;

    await tester.tap(find.text('Refresh checkout'));
    await tester.pumpAndSettle();

    expect(checkout.prepareCalls, 2);
    expect(find.text('Checkout details need refreshing'), findsNothing);
  });

  testWidgets('a stale quote is refreshed rather than revalidated', (
    WidgetTester tester,
  ) async {
    // A quote goes stale because the facts under it moved. Re-asking about the
    // old one would answer a question about a cart that no longer exists.
    final FakeCheckoutRepository checkout = FakeCheckoutRepository()
      ..status = CheckoutStatus.stale
      ..readyForPayment = false;

    await open(tester, checkout: checkout);

    expect(find.text('Your order has changed'), findsOneWidget);

    await tester.tap(find.text('Refresh checkout'));
    await tester.pumpAndSettle();

    expect(checkout.prepareCalls, 2);
    expect(checkout.validateCalls, 0);
  });

  testWidgets('a quote the server has forgotten is replaced, not explained', (
    WidgetTester tester,
  ) async {
    final FakeCheckoutRepository checkout = await open(tester);

    checkout.nextValidateError = ApiException(
      code: ApiErrorCode.checkoutQuoteNotFound,
      message: 'That checkout is no longer available.',
    );

    await scrollToBottom(tester);
    await tapKey(tester, 'checkout-proceed');

    // A fresh checkout, rather than an error naming an id the customer never
    // saw.
    expect(checkout.prepareCalls, 2);
  });

  testWidgets('the expiry is shown on the counter\'s clock', (
    WidgetTester tester,
  ) async {
    await open(tester);
    await scrollToBottom(tester);

    // 06:30 UTC + 10 minutes is 06:40 UTC, which is 12:10 pm in Kolkata.
    expect(find.textContaining('Held until 12:10 pm'), findsOneWidget);

    // Never the phone's zone, which on a machine set to UTC would say 6:40 am.
    expect(find.textContaining('6:40 am'), findsNothing);
  });

  // --- failures -------------------------------------------------------------

  testWidgets('a failed prepare offers a retry rather than a blank screen', (
    WidgetTester tester,
  ) async {
    final FakeCheckoutRepository checkout = FakeCheckoutRepository()
      ..nextPrepareError = ApiException(
        code: ApiErrorCode.network,
        message: 'No connection.',
      );

    await open(tester, checkout: checkout);

    expect(find.text("We couldn't prepare your checkout"), findsOneWidget);
    expect(find.textContaining('₹'), findsNothing);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(checkout.prepareCalls, 2);
    expect(find.text('Highway Spice Kitchen'), findsOneWidget);
  });

  // --- getting back to change something ------------------------------------

  testWidgets('the cart and the pickup time are both one tap away', (
    WidgetTester tester,
  ) async {
    await open(tester);
    await scrollToBottom(tester);

    expect(
      find.byKey(const ValueKey<String>('checkout-edit-cart')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('checkout-change-pickup')),
      findsOneWidget,
    );
  });

  testWidgets('changing the pickup time leaves the checkout behind', (
    WidgetTester tester,
  ) async {
    await open(tester);
    await scrollToBottom(tester);
    await tapKey(tester, 'checkout-change-pickup');

    expect(find.text('Checkout'), findsNothing);
    expect(find.text('When will you collect?'), findsOneWidget);
  });

  // --- accessibility --------------------------------------------------------

  testWidgets('the summary lays out at twice the text size', (
    WidgetTester tester,
  ) async {
    final FakeCheckoutRepository checkout = FakeCheckoutRepository()
      ..charges = <({String code, int amountMinor})>[
        (code: 'TAX', amountMinor: 2_490),
        (code: 'PACKAGING_FEE', amountMinor: 1_000),
      ]
      ..payableTotalMinor = 53_290;

    await open(tester, checkout: checkout, textScale: 2.0);
    await scrollToBottom(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Total to pay'), findsOneWidget);
  });
}
