import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/core/network/api_error_code.dart';
import 'package:foodonthego/core/network/api_exception.dart';
import 'package:foodonthego/domain/models/customer_summary.dart';
import 'package:foodonthego/domain/models/home_dashboard.dart';
import 'package:foodonthego/domain/models/order_status_report.dart';
import 'package:foodonthego/domain/payments/payment_handoff.dart';

import 'support/harness.dart';

/// The payment screen, as a customer meets it.
///
/// The theme: **the screen states the server's answer and never its own.** A
/// handoff that claims success does not turn the screen green; only an order
/// that comes back paid does.
void main() {
  const PaymentHandoffSucceeded succeeded = PaymentHandoffSucceeded(
    providerOrderId: 'order_FAKE000001',
    providerPaymentId: 'pay_FAKE1',
    signature: 'a-signature-the-server-will-check',
  );

  Future<void> open(
    WidgetTester tester, {
    FakeOrderRepository? orders,
    PaymentHandoff? handoff,
    double textScale = 1.0,
  }) async {
    usePhoneSurface(tester);

    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: wrapApp(
          repository: StubHomeRepository.value(
            const HomeDashboard(
              customer: CustomerSummary(fullName: 'Rahul Sharma'),
            ),
          ),
          orders: orders ?? FakeOrderRepository(),
          handoff: handoff,
          initialLocation:
              '/trips/trip-1/cart/pickup/checkout/payment?checkout=quote-1',
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('placing the order shows its number and the amount due', (
    WidgetTester tester,
  ) async {
    await open(tester);

    expect(
      find.byKey(const ValueKey<String>('payment-order-number')),
      findsOne,
    );
    expect(find.text('260916-7K2M9QX4TB'), findsOne);
    expect(find.byKey(const ValueKey<String>('payment-amount-due')), findsOne);
    expect(find.textContaining('498'), findsWidgets);
  });

  testWidgets('an unpaid order says so and offers a way to pay', (
    WidgetTester tester,
  ) async {
    await open(tester);

    expect(
      find.byKey(const ValueKey<String>('payment-status-AWAITING_PAYMENT')),
      findsOne,
    );
    expect(find.byKey(const ValueKey<String>('payment-pay')), findsOne);
  });

  /// Since Module 16 this ends somewhere else, and that is the improvement.
  ///
  /// The screen used to report the placed order in place and simply hide its
  /// Pay button. It now leaves for the confirmation screen the instant the
  /// provider reports a capture, so the assertion moved with the customer.
  testWidgets('a placed order is shown on the confirmation screen, not here', (
    WidgetTester tester,
  ) async {
    await open(tester, handoff: ScriptedPaymentHandoff(succeeded));

    await tester.tap(find.byKey(const ValueKey<String>('payment-pay')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('payment-pay')), findsNothing);
    expect(find.byKey(const ValueKey<String>('confirmation-placed')), findsOne);
    expect(
      find.byKey(const ValueKey<String>('confirmation-order-number')),
      findsOne,
    );
  });

  /// The screen must follow the server, not the sheet.
  testWidgets('a handoff claiming success does not turn the screen paid', (
    WidgetTester tester,
  ) async {
    // The server disagrees on BOTH the questions the client can ask it: the
    // verification does not settle the order, and the status the confirmation
    // screen fetches afterwards does not report it placed either. Without the
    // second, the fake's cheerful default would answer PLACED and the test
    // would prove nothing about the sheet being disbelieved.
    await open(
      tester,
      orders: FakeOrderRepository()
        ..settlesOnVerify = false
        ..statusReport = const OrderStatusReport(
          state: OrderCreationState.creating,
          isPaidFor: true,
          order: null,
          message: 'We are still writing your order.',
        ),
      handoff: ScriptedPaymentHandoff(succeeded),
    );

    await tester.tap(find.byKey(const ValueKey<String>('payment-pay')));

    // `pump`, not `pumpAndSettle`. The confirmation screen polls while the
    // order is still being written, so there is a pending timer by design and
    // settling would wait for a quiet frame that correctly never comes.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // The sheet said the money went through, and the server did not agree.
    // Nothing anywhere claims this order is placed.
    expect(
      find.byKey(const ValueKey<String>('payment-status-PLACED')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('confirmation-placed')),
      findsNothing,
    );

    // The customer is on the confirmation screen either way, because the
    // capture is what moves them and the server's answer is what they wait
    // for. What they are NOT offered is another payment.
    expect(find.byKey(const ValueKey<String>('payment-pay')), findsNothing);
  });

  /*
   | THE POINT OF NO RETURN.
   |
   | Once the provider reports a capture, the money may already be gone. From
   | that instant the payment screen is finished: it must not show a failure,
   | must not offer to pay, and must hand the customer to the confirmation
   | screen — which has no route backwards to paying.
   |
   | The case tested here is the nasty one. The capture succeeded and the
   | server call that would have turned it into an order did NOT. Before this
   | wiring existed, that combination rendered "we could not verify your
   | payment" beside a live Pay button.
   */
  testWidgets('a capture the server never confirmed still leaves the payment '
      'screen behind', (WidgetTester tester) async {
    final FakeOrderRepository orders = FakeOrderRepository()
      ..verifyFailure = const ApiException(
        code: ApiErrorCode.paymentNotFound,
        message: 'the server never heard about this payment',
        status: 404,
      );

    await open(
      tester,
      orders: orders,
      handoff: ScriptedPaymentHandoff(succeeded),
    );

    await tester.tap(find.byKey(const ValueKey<String>('payment-pay')));
    await tester.pumpAndSettle();

    // Gone from the payment screen entirely.
    expect(find.byKey(const ValueKey<String>('payment-pay')), findsNothing);

    // And no failure notice was ever rendered for it. This is the assertion
    // that fails if a captured payment is reported as a payment problem.
    expect(
      find.byKey(const ValueKey<String>('payment-failure-verificationFailed')),
      findsNothing,
    );
    expect(find.textContaining('declined'), findsNothing);

    // On the confirmation screen. Which phase it settles into depends on what
    // the server says when asked afresh; what matters is that the customer is
    // here, on a screen with no route back to paying, rather than there.
    expect(find.byKey(const ValueKey<String>('confirmation-placed')), findsOne);
  });

  /// This build's real state, on screen. Not dressed up as a card failure.
  testWidgets('with no provider configured the screen says exactly that', (
    WidgetTester tester,
  ) async {
    await open(tester);

    await tester.tap(find.byKey(const ValueKey<String>('payment-pay')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('payment-failure-paymentUnavailable')),
      findsOne,
    );
    expect(find.textContaining('not enabled'), findsWidgets);
    expect(find.textContaining('declined'), findsNothing);
  });

  testWidgets('a cancelled sheet is a neutral note, not an error', (
    WidgetTester tester,
  ) async {
    await open(
      tester,
      handoff: ScriptedPaymentHandoff(const PaymentHandoffCancelled()),
    );

    await tester.tap(find.byKey(const ValueKey<String>('payment-pay')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('payment-cancelled')), findsOne);
    expect(find.textContaining('Nothing was charged'), findsWidgets);
  });

  testWidgets('a stale quote sends the customer back to review the order', (
    WidgetTester tester,
  ) async {
    await open(
      tester,
      orders: FakeOrderRepository()
        ..placeFailure = const ApiException(
          code: ApiErrorCode.checkoutQuoteStale,
          message: 'Your order changed.',
          status: 409,
        ),
    );

    expect(
      find.byKey(const ValueKey<String>('payment-failure-quoteStale')),
      findsOne,
    );
    expect(find.byKey(const ValueKey<String>('payment-pay')), findsNothing);
  });

  testWidgets('a gateway outage is not reported as a declined card', (
    WidgetTester tester,
  ) async {
    await open(
      tester,
      orders: FakeOrderRepository()
        ..intentFailure = const ApiException(
          code: ApiErrorCode.paymentGatewayUnavailable,
          message: 'Payments are temporarily unavailable.',
          status: 503,
        ),
    );

    expect(
      find.byKey(const ValueKey<String>('payment-failure-gatewayUnavailable')),
      findsOne,
    );
    expect(find.textContaining('declined'), findsNothing);
    // The order still exists and is still shown.
    expect(
      find.byKey(const ValueKey<String>('payment-order-number')),
      findsOne,
    );
  });

  /// Semantics are not pixels — Module 14 learned that the hard way — so this
  /// asserts the rendered width of the amount rather than only its text.
  testWidgets('the amount due is not clipped at double text size', (
    WidgetTester tester,
  ) async {
    await open(tester, textScale: 2.0);

    final Finder amount = find.byKey(
      const ValueKey<String>('payment-amount-due'),
    );

    expect(amount, findsOne);

    final RenderBox box = tester.renderObject<RenderBox>(amount);

    expect(box.size.width, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
}
