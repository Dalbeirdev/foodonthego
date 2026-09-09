import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/core/network/api_error_code.dart';
import 'package:foodonthego/core/network/api_exception.dart';
import 'package:foodonthego/domain/models/customer_summary.dart';
import 'package:foodonthego/domain/models/home_dashboard.dart';
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

  testWidgets('a placed order says so and stops offering to pay', (
    WidgetTester tester,
  ) async {
    await open(tester, handoff: ScriptedPaymentHandoff(succeeded));

    await tester.tap(find.byKey(const ValueKey<String>('payment-pay')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('payment-status-PLACED')),
      findsOne,
    );
    expect(find.byKey(const ValueKey<String>('payment-pay')), findsNothing);
  });

  /// The screen must follow the server, not the sheet.
  testWidgets('a handoff claiming success does not turn the screen paid', (
    WidgetTester tester,
  ) async {
    await open(
      tester,
      orders: FakeOrderRepository()..settlesOnVerify = false,
      handoff: ScriptedPaymentHandoff(succeeded),
    );

    await tester.tap(find.byKey(const ValueKey<String>('payment-pay')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('payment-status-PLACED')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('payment-status-AWAITING_PAYMENT')),
      findsOne,
    );
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
