import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/routing/routes.dart';
import '../../core/theme/tokens.dart';
import '../../domain/models/placed_order.dart';
import '../../shared/state/order_controller.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/fotg_card.dart';
import '../cart/widgets/cart_notice.dart';

/// The screen where money would change hands.
///
/// **Nothing here decides that an order is paid.** The status line and every
/// word on the screen come from the order the server returned. A build that
/// read "paid" from the provider's callback would be trusting a device, which
/// is the one thing this module exists to prevent.
///
/// Opening the screen places the order. That is deliberate: the server
/// re-validates the quote as it does so, which is the last moment a changed
/// basket or a closing kitchen can alter the answer, and doing it here means
/// the customer sees the result on the screen they are already looking at.
class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({
    required this.tripId,
    required this.checkoutId,
    super.key,
  });

  final String tripId;
  final String checkoutId;

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      ref
          .read(orderControllerProvider.notifier)
          .place(tripId: widget.tripId, checkoutId: widget.checkoutId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final OrderState state = ref.watch(orderControllerProvider);

    /*
     | Off this screen the moment the provider says the money went through.
     |
     | `go`, not `push`: the payment screen must not be underneath the
     | confirmation screen, because a back gesture would land the customer on a
     | Pay button after they have already paid. This is the only navigation out
     | of a captured payment, and it goes forward.
     |
     | Watched rather than fired from the controller, so that nothing in the
     | state layer needs a BuildContext, and so a screen that is no longer
     | mounted simply never navigates.
     */
    ref.listen<String?>(
      orderControllerProvider.select((OrderState it) => it.capturedOrderId),
      (String? was, String? now) {
        if (now == null || was == now || !mounted) return;

        context.go(Routes.orderConfirmationPath(now));
      },
    );

    return Scaffold(
      appBar: AppBar(title: Text(strings.paymentTitle)),
      body: SafeArea(
        child: state.isPlacing && state.order == null
            ? _placing(strings)
            : _content(strings, state),
      ),
    );
  }

  Widget _placing(AppStrings strings) => Center(
    child: Column(
      key: const ValueKey<String>('payment-placing'),
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const CircularProgressIndicator(),
        const SizedBox(height: FotgSpacing.x4),
        Text(strings.paymentPlacing),
      ],
    ),
  );

  Widget _content(AppStrings strings, OrderState state) {
    final PlacedOrder? order = state.order;

    if (order == null) {
      return Padding(
        padding: const EdgeInsets.all(FotgSpacing.x4),
        child: _failureNotice(strings, state),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(FotgSpacing.x4),
      children: <Widget>[
        _orderCard(strings, order),
        const SizedBox(height: FotgSpacing.x4),
        if (state.wasCancelled) ...<Widget>[
          CartNotice(
            key: const ValueKey<String>('payment-cancelled'),
            title: strings.paymentCancelledTitle,
            body: strings.paymentCancelledBody,
            tone: CartNoticeTone.neutral,
          ),
          const SizedBox(height: FotgSpacing.x4),
        ],
        if (state.failure != null) ...<Widget>[
          _failureNotice(strings, state),
          const SizedBox(height: FotgSpacing.x4),
        ],
        _statusNotice(strings, order),
        const SizedBox(height: FotgSpacing.x4),
        if (!order.isPlaced) _payAction(strings, state),
      ],
    );
  }

  Widget _orderCard(AppStrings strings, PlacedOrder order) => FotgCard(
    key: const ValueKey<String>('payment-order-card'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        /*
         * The number appears when the order does.
         *
         * Before the money is captured this is a payment target, and Module 16
         * mints no number for one — there is nothing yet for a customer to read
         * out. Rendering an empty line under an "Order number" heading would
         * invite them to quote nothing at a counter.
         */
        if (order.orderNumber case final String number) ...<Widget>[
          Text(
            strings.paymentOrderNumber,
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: FotgSpacing.x1),
          Text(
            number,
            key: const ValueKey<String>('payment-order-number'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ],
        if (order.restaurantName != null) ...<Widget>[
          const SizedBox(height: FotgSpacing.x2),
          Text(order.restaurantName!),
        ],
        const SizedBox(height: FotgSpacing.x4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Expanded(child: Text(strings.paymentAmountDue)),
            Text(
              // The server's figure, formatted. Never computed here.
              order.commercial.payableTotal.format(),
              key: const ValueKey<String>('payment-amount-due'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ],
    ),
  );

  Widget _statusNotice(AppStrings strings, PlacedOrder order) => CartNotice(
    key: ValueKey<String>('payment-status-${order.status.wireValue}'),
    title: order.isPlaced
        ? strings.paymentPaidTitle
        : strings.paymentAwaitingTitle,
    body: order.isPlaced
        ? strings.paymentPaidBody
        : strings.paymentAwaitingBody,
    tone: CartNoticeTone.neutral,
  );

  /// Belt to the navigation's braces.
  ///
  /// `isPaymentFinished` disables this button as well as triggering the move to
  /// the confirmation screen. Navigation takes a frame and can be prevented —
  /// a router guard, a screen already popped — and a button that can still take
  /// money in that window is a button that charges somebody twice.
  Widget _payAction(AppStrings strings, OrderState state) => PrimaryButton(
    key: const ValueKey<String>('payment-pay'),
    label: state.isPaying ? strings.paymentPaying : strings.paymentPayNow,
    onPressed: state.isPaying || state.intent == null || state.isPaymentFinished
        ? null
        : () => ref.read(orderControllerProvider.notifier).pay(),
  );

  /// One notice per failure, in the customer's words rather than the API's.
  ///
  /// The distinction that matters is between a card being refused and payments
  /// being unreachable. They are different sentences because they ask the
  /// customer to do different things, and reporting the second as the first
  /// tells them something untrue about their card.
  Widget _failureNotice(AppStrings strings, OrderState state) {
    final (String title, String body) = switch (state.failure) {
      OrderFailure.declined => (
        strings.paymentDeclinedTitle,
        strings.paymentDeclinedBody,
      ),
      OrderFailure.gatewayUnavailable => (
        strings.paymentUnreachableTitle,
        strings.paymentUnreachableBody,
      ),
      OrderFailure.paymentUnavailable => (
        strings.paymentUnavailableTitle,
        strings.paymentUnavailableBody,
      ),
      OrderFailure.verificationFailed => (
        strings.paymentVerificationFailedTitle,
        strings.paymentVerificationFailedBody,
      ),
      OrderFailure.quoteExpired ||
      OrderFailure.quoteStale ||
      OrderFailure.quoteGone => (
        strings.paymentQuoteMovedTitle,
        strings.paymentQuoteMovedBody,
      ),
      OrderFailure.alreadyPaid => (
        strings.paymentPaidTitle,
        strings.paymentPaidBody,
      ),
      _ => (strings.paymentUnreachableTitle, strings.paymentUnreachableBody),
    };

    return CartNotice(
      key: ValueKey<String>('payment-failure-${state.failure?.name}'),
      title: title,
      body: body,
      tone: state.failure == OrderFailure.alreadyPaid
          ? CartNoticeTone.neutral
          : CartNoticeTone.advisory,
    );
  }
}
