import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/tokens.dart';
import '../../domain/models/pickup_credential.dart';
import '../../domain/models/placed_order.dart';
import '../../shared/state/order_confirmation_controller.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/fotg_card.dart';
import '../cart/widgets/cart_notice.dart';

/// What a customer sees after paying.
///
/// -------------------------------------------------------------------------
/// THE ONE RULE THIS SCREEN EXISTS TO KEEP
/// -------------------------------------------------------------------------
///
/// **After a capture, never offer to pay again.** Not as a button, not as a
/// retry, not as an error that a customer could read as "that did not work, try
/// once more". Their money has left their account; a second payment is a real
/// charge and a refund conversation, and the app has no way to undo it.
///
/// So the payment affordance is gated on one question — `mayOfferPayment` —
/// which is false whenever the money may already be gone, including the case
/// where the app cannot reach the server and simply does not know. Not knowing
/// is treated as paid, because only one of the two possible mistakes is
/// recoverable.
class OrderConfirmationScreen extends ConsumerWidget {
  const OrderConfirmationScreen({required this.orderId, super.key});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppStrings strings = AppStrings.of(context);
    final OrderConfirmationState state = ref.watch(
      orderConfirmationProvider(orderId),
    );

    return Scaffold(
      appBar: AppBar(title: Text(strings.orderConfirmationTitle)),
      body: SafeArea(
        top: false,
        child: switch (state.phase) {
          OrderConfirmationPhase.loading => const Center(
            key: ValueKey<String>('confirmation-loading'),
            child: CircularProgressIndicator(),
          ),
          OrderConfirmationPhase.creating ||
          OrderConfirmationPhase.recovering => _Settling(state: state),
          OrderConfirmationPhase.unauthorized => _Unauthorized(
            onRetry: () =>
                ref.read(orderConfirmationProvider(orderId).notifier).retry(),
          ),
          OrderConfirmationPhase.networkError => _NetworkError(
            state: state,
            onRetry: () =>
                ref.read(orderConfirmationProvider(orderId).notifier).retry(),
          ),
          OrderConfirmationPhase.awaitingPayment ||
          OrderConfirmationPhase.placed => _Confirmed(state: state),
        },
      ),
    );
  }
}

/// Money captured, order being written.
class _Settling extends StatelessWidget {
  const _Settling({required this.state});

  final OrderConfirmationState state;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);

    return Center(
      key: const ValueKey<String>('confirmation-settling'),
      child: Padding(
        padding: const EdgeInsets.all(FotgSpacing.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const CircularProgressIndicator(),
            const SizedBox(height: FotgSpacing.x4),

            // "Payment confirmed" first, and in the largest type on screen.
            // It is the fact the customer most needs, and the one a spinner
            // alone would leave them doubting.
            Text(
              strings.orderPaymentConfirmed,
              key: const ValueKey<String>('confirmation-payment-confirmed'),
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: FotgSpacing.x2),
            Text(
              // The server's own wording when it sent one, so the message a
              // customer reads is written once rather than drifting between
              // the API and every client.
              state.message ?? strings.orderStillCreating,
              key: const ValueKey<String>('confirmation-do-not-pay-again'),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _Unauthorized extends StatelessWidget {
  const _Unauthorized({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);

    return Center(
      key: const ValueKey<String>('confirmation-unauthorized'),
      child: Padding(
        padding: const EdgeInsets.all(FotgSpacing.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              strings.orderNotYours,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: FotgSpacing.x4),
            SecondaryButton(
              label: strings.retry,
              expand: false,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}

/// The app could not ask. That is not the same as a payment failing.
class _NetworkError extends StatelessWidget {
  const _NetworkError({required this.state, required this.onRetry});

  final OrderConfirmationState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);

    return Center(
      key: const ValueKey<String>('confirmation-network-error'),
      child: Padding(
        padding: const EdgeInsets.all(FotgSpacing.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.wifi_off_rounded,
              size: 40,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: FotgSpacing.x4),
            Text(
              strings.orderCouldNotCheck,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: FotgSpacing.x2),

            /*
             * Says the money is safe, and does NOT offer to pay.
             *
             * The app has no idea whether the capture happened. Guessing "not
             * paid" here and showing a Pay button is how a customer is charged
             * twice for one meal, so the screen declines to guess and asks them
             * to try the check again instead.
             */
            Text(
              strings.orderCouldNotCheckBody,
              key: const ValueKey<String>('confirmation-no-repay'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: FotgSpacing.x4),
            PrimaryButton(
              label: strings.retry,
              expand: false,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}

/// The order, as agreed.
class _Confirmed extends StatelessWidget {
  const _Confirmed({required this.state});

  final OrderConfirmationState state;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final PlacedOrder? order = state.order;

    if (order == null) {
      return Center(child: Text(strings.orderCouldNotCheck));
    }

    return ListView(
      key: const ValueKey<String>('confirmation-placed'),
      padding: const EdgeInsets.all(FotgSpacing.x4),
      children: <Widget>[
        _header(context, strings, order),
        const SizedBox(height: FotgSpacing.x4),
        _orderCard(context, strings, order),

        if (state.credential
            case final PickupCredential credential) ...<Widget>[
          const SizedBox(height: FotgSpacing.x4),
          _pickupCard(context, strings, credential),
        ],

        if (order.status == PlacedOrderStatus.placed) ...<Widget>[
          const SizedBox(height: FotgSpacing.x4),

          /*
           * "Waiting for restaurant confirmation" — not "Accepted".
           *
           * Nothing has told the restaurant yet, and no module exists that
           * lets them respond. Saying anything stronger would have the app
           * promising on a third party's behalf, and the customer arriving to
           * find nobody had started.
           */
          CartNotice(
            key: const ValueKey<String>('confirmation-awaiting-restaurant'),
            title: strings.orderWaitingRestaurantTitle,
            body: strings.orderWaitingRestaurantBody,
            tone: CartNoticeTone.neutral,
          ),
        ],
      ],
    );
  }

  Widget _header(BuildContext context, AppStrings strings, PlacedOrder order) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            order.status.label,
            key: const ValueKey<String>('confirmation-status'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          if (state.isPaidFor) ...<Widget>[
            const SizedBox(height: FotgSpacing.x1),
            Text(
              strings.orderPaymentConfirmed,
              key: const ValueKey<String>('confirmation-paid'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ],
      );

  Widget _orderCard(
    BuildContext context,
    AppStrings strings,
    PlacedOrder order,
  ) => FotgCard(
    key: const ValueKey<String>('confirmation-order-card'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (order.restaurantName case final String name)
          Text(name, style: Theme.of(context).textTheme.titleMedium),

        if (order.orderNumber case final String number) ...<Widget>[
          const SizedBox(height: FotgSpacing.x2),
          Text(
            strings.paymentOrderNumber,
            style: Theme.of(context).textTheme.labelMedium,
          ),
          Text(
            number,
            key: const ValueKey<String>('confirmation-order-number'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ],

        const SizedBox(height: FotgSpacing.x3),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Expanded(child: Text(strings.paymentAmountDue)),
            Text(
              order.commercial.payableTotal.format(),
              key: const ValueKey<String>('confirmation-total'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ],
    ),
  );

  Widget _pickupCard(
    BuildContext context,
    AppStrings strings,
    PickupCredential credential,
  ) => FotgCard(
    key: const ValueKey<String>('confirmation-pickup-card'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          strings.orderPickupCodeLabel,
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: FotgSpacing.x1),

        /*
         * Read out character by character.
         *
         * A screen reader saying "7K4M9PQ2" as a word is unusable, and this is
         * a value a customer has to say out loud to somebody behind a counter.
         * The QR is not an accessible alternative — it cannot be spoken at all
         * — so this IS the accessible path rather than a fallback for it.
         */
        Semantics(
          label: '${strings.orderPickupCodeLabel}, ${credential.spokenCode}',
          excludeSemantics: true,
          child: Text(
            credential.code,
            key: const ValueKey<String>('confirmation-pickup-code'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),

        const SizedBox(height: FotgSpacing.x2),
        Text(
          strings.orderPickupCodePrivate,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}
