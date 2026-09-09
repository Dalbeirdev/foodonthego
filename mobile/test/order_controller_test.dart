import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/core/network/api_error_code.dart';
import 'package:foodonthego/core/network/api_exception.dart';
import 'package:foodonthego/domain/payments/payment_handoff.dart';
import 'package:foodonthego/shared/state/order_controller.dart';
import 'package:foodonthego/shared/state/providers.dart';

import 'support/harness.dart';

/// Placing an order and paying for it, without a screen.
///
/// The assertion running through all of it: **this controller never decides
/// that an order is paid.** It hands the provider's result to the server and
/// adopts whatever order comes back, so a fabricated handoff result cannot
/// produce a paid order in state.
void main() {
  ProviderContainer containerWith({
    FakeOrderRepository? orders,
    PaymentHandoff? handoff,
  }) {
    final ProviderContainer container = ProviderContainer(
      overrides: [
        orderRepositoryProvider.overrideWithValue(
          orders ?? FakeOrderRepository(),
        ),
        if (handoff != null) paymentHandoffProvider.overrideWithValue(handoff),
      ],
    );

    addTearDown(container.dispose);

    return container;
  }

  const PaymentHandoffSucceeded succeeded = PaymentHandoffSucceeded(
    providerOrderId: 'order_FAKE000001',
    providerPaymentId: 'pay_FAKE1',
    signature: 'a-signature-the-server-will-check',
  );

  group('placing', () {
    test('places the order and opens a payment against it', () async {
      final FakeOrderRepository orders = FakeOrderRepository();
      final ProviderContainer container = containerWith(orders: orders);

      await container
          .read(orderControllerProvider.notifier)
          .place(tripId: 't1', checkoutId: 'c1');

      final OrderState state = container.read(orderControllerProvider);

      expect(orders.placeCalls, 1);
      expect(orders.intentCalls, 1);
      expect(state.order, isNotNull);
      expect(state.intent, isNotNull);
      expect(state.isPlaced, isFalse);
      expect(state.failure, isNull);
    });

    test('a stale quote is reported as the order having changed', () async {
      final FakeOrderRepository orders = FakeOrderRepository()
        ..placeFailure = const ApiException(
          code: ApiErrorCode.checkoutQuoteStale,
          message: 'Your order changed.',
          status: 409,
        );

      final ProviderContainer container = containerWith(orders: orders);

      await container
          .read(orderControllerProvider.notifier)
          .place(tripId: 't1', checkoutId: 'c1');

      final OrderState state = container.read(orderControllerProvider);

      expect(state.failure, OrderFailure.quoteStale);
      expect(state.order, isNull);
      expect(state.isPlacing, isFalse);
    });

    test('an expired quote is its own failure, not a generic one', () async {
      final FakeOrderRepository orders = FakeOrderRepository()
        ..placeFailure = const ApiException(
          code: ApiErrorCode.checkoutQuoteExpired,
          message: 'That checkout timed out.',
          status: 409,
        );

      final ProviderContainer container = containerWith(orders: orders);

      await container
          .read(orderControllerProvider.notifier)
          .place(tripId: 't1', checkoutId: 'c1');

      expect(
        container.read(orderControllerProvider).failure,
        OrderFailure.quoteExpired,
      );
    });

    /// The order exists even though the payment could not be opened. Losing it
    /// from state would strand a customer with an order they cannot see.
    test('a gateway outage keeps the order and reports the outage', () async {
      final FakeOrderRepository orders = FakeOrderRepository()
        ..intentFailure = const ApiException(
          code: ApiErrorCode.paymentGatewayUnavailable,
          message: 'Payments are temporarily unavailable.',
          status: 503,
        );

      final ProviderContainer container = containerWith(orders: orders);

      await container
          .read(orderControllerProvider.notifier)
          .place(tripId: 't1', checkoutId: 'c1');

      final OrderState state = container.read(orderControllerProvider);

      expect(state.order, isNotNull);
      expect(state.intent, isNull);
      expect(state.failure, OrderFailure.gatewayUnavailable);
    });
  });

  group('paying', () {
    test('a successful handoff is verified with the server', () async {
      final FakeOrderRepository orders = FakeOrderRepository();
      final ProviderContainer container = containerWith(
        orders: orders,
        handoff: ScriptedPaymentHandoff(succeeded),
      );

      final OrderController controller = container.read(
        orderControllerProvider.notifier,
      );

      await controller.place(tripId: 't1', checkoutId: 'c1');
      await controller.pay();

      expect(orders.verifyCalls, 1);
      expect(orders.lastVerification, <String, String>{
        'provider_order_id': 'order_FAKE000001',
        'provider_payment_id': 'pay_FAKE1',
        'signature': 'a-signature-the-server-will-check',
      });
      expect(container.read(orderControllerProvider).isPlaced, isTrue);
    });

    /// **The assertion this whole module exists for.**
    ///
    /// The handoff reports a triumphant success. The server, asked, says the
    /// order is still awaiting payment. The screen must follow the server.
    test('a handoff claiming success does not make an order paid', () async {
      final FakeOrderRepository orders = FakeOrderRepository()
        ..settlesOnVerify = false;

      final ProviderContainer container = containerWith(
        orders: orders,
        handoff: ScriptedPaymentHandoff(succeeded),
      );

      final OrderController controller = container.read(
        orderControllerProvider.notifier,
      );

      await controller.place(tripId: 't1', checkoutId: 'c1');
      await controller.pay();

      expect(orders.verifyCalls, 1);
      expect(container.read(orderControllerProvider).isPlaced, isFalse);
    });

    /// And the same when the server refuses the result outright.
    test('a verification the server rejects leaves the order unpaid', () async {
      final FakeOrderRepository orders = FakeOrderRepository()
        ..verifyFailure = const ApiException(
          code: ApiErrorCode.paymentSignatureInvalid,
          message: 'That payment could not be verified.',
          status: 422,
        );

      final ProviderContainer container = containerWith(
        orders: orders,
        handoff: ScriptedPaymentHandoff(succeeded),
      );

      final OrderController controller = container.read(
        orderControllerProvider.notifier,
      );

      await controller.place(tripId: 't1', checkoutId: 'c1');
      await controller.pay();

      final OrderState state = container.read(orderControllerProvider);

      // Still not placed. Only the server decides that, and it did not.
      expect(state.isPlaced, isFalse);
      expect(state.isPaying, isFalse);

      /*
       | AND STILL NOT A FAILURE, since Module 16.
       |
       | The provider's sheet reported a capture before this call was made, so
       | the customer's money may already be gone. A `verificationFailed` here
       | would render beside a Pay button, and paying again is the one thing
       | that must not be offered. The order is not lost by staying quiet: the
       | webhook and the recovery sweep reach the same creation path this call
       | was trying to reach.
       */
      expect(state.failure, isNull);
      expect(state.capturedOrderId, isNotNull);
      expect(state.isPaymentFinished, isTrue);
    });

    /// A rejected signature is not a card problem, and the customer must not be
    /// told it was one.
    test('a rejected signature is not reported as a decline', () async {
      final FakeOrderRepository orders = FakeOrderRepository()
        ..verifyFailure = const ApiException(
          code: ApiErrorCode.paymentAmountMismatch,
          message: 'That payment does not match the amount due.',
          status: 409,
        );

      final ProviderContainer container = containerWith(
        orders: orders,
        handoff: ScriptedPaymentHandoff(succeeded),
      );

      final OrderController controller = container.read(
        orderControllerProvider.notifier,
      );

      await controller.place(tripId: 't1', checkoutId: 'c1');
      await controller.pay();

      final OrderState state = container.read(orderControllerProvider);

      // The original property, and it still holds: an amount the server would
      // not accept is never told to the customer as a card problem.
      expect(state.failure, isNot(OrderFailure.declined));

      // Since Module 16 it is stronger than that. After a capture the screen
      // reports nothing the customer could answer by paying again.
      expect(state.failure, isNull);
      expect(state.isPaymentFinished, isTrue);
    });

    test('a cancelled sheet is not a failure', () async {
      final FakeOrderRepository orders = FakeOrderRepository();
      final ProviderContainer container = containerWith(
        orders: orders,
        handoff: ScriptedPaymentHandoff(const PaymentHandoffCancelled()),
      );

      final OrderController controller = container.read(
        orderControllerProvider.notifier,
      );

      await controller.place(tripId: 't1', checkoutId: 'c1');
      await controller.pay();

      final OrderState state = container.read(orderControllerProvider);

      expect(state.wasCancelled, isTrue);
      expect(state.failure, isNull);
      expect(orders.verifyCalls, 0);
    });

    test('a declined sheet is reported as a decline', () async {
      final ProviderContainer container = containerWith(
        handoff: ScriptedPaymentHandoff(
          const PaymentHandoffFailed('Card declined.'),
        ),
      );

      final OrderController controller = container.read(
        orderControllerProvider.notifier,
      );

      await controller.place(tripId: 't1', checkoutId: 'c1');
      await controller.pay();

      expect(
        container.read(orderControllerProvider).failure,
        OrderFailure.declined,
      );
    });

    /// This build's actual behaviour, asserted rather than assumed. The default
    /// handoff reports that it cannot open a checkout, and that must reach the
    /// screen as its own state — not as a declined card.
    test(
      'the unconfigured handoff reports unavailable, not declined',
      () async {
        final FakeOrderRepository orders = FakeOrderRepository();
        final ProviderContainer container = containerWith(orders: orders);

        final OrderController controller = container.read(
          orderControllerProvider.notifier,
        );

        await controller.place(tripId: 't1', checkoutId: 'c1');
        await controller.pay();

        final OrderState state = container.read(orderControllerProvider);

        expect(state.failure, OrderFailure.paymentUnavailable);
        expect(state.isPlaced, isFalse);
        expect(
          orders.verifyCalls,
          0,
          reason: 'nothing was paid, so nothing to verify',
        );
      },
    );

    test('paying without an intent does nothing at all', () async {
      final FakeOrderRepository orders = FakeOrderRepository();
      final ScriptedPaymentHandoff handoff = ScriptedPaymentHandoff(succeeded);
      final ProviderContainer container = containerWith(
        orders: orders,
        handoff: handoff,
      );

      await container.read(orderControllerProvider.notifier).pay();

      expect(handoff.calls, 0);
      expect(orders.verifyCalls, 0);
    });
  });
}
