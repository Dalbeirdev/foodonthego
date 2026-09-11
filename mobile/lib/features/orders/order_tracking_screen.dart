import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/tokens.dart';
import '../../domain/models/placed_order.dart';
import '../../domain/models/tracked_order.dart';
import '../../shared/state/order_tracking_controller.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/fotg_card.dart';
import '../cart/widgets/cart_notice.dart';
import 'widgets/order_timeline_view.dart';

/// Where a customer watches their order.
///
/// **THIS SCREEN DISPLAYS ORDER STATE. IT DOES NOT DECIDE IT.** There is no
/// control here that moves an order forward, because the customer app is not
/// party to that decision — the restaurant is, through modules that do not
/// exist yet. Everything on screen came from the server in one response.
///
/// The current status is the largest thing on the page. The order number is
/// present and quotable but subordinate: what a customer opens this screen to
/// learn is whether their food is ready, not what their reference is.
class OrderTrackingScreen extends ConsumerWidget {
  const OrderTrackingScreen({required this.orderId, super.key});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppStrings strings = AppStrings.of(context);
    final OrderTrackingState state = ref.watch(orderTrackingProvider(orderId));

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.orderTrackingTitle),
        actions: <Widget>[
          IconButton(
            key: const ValueKey<String>('tracking-refresh'),
            tooltip: strings.orderTrackingRefresh,
            onPressed: () =>
                ref.read(orderTrackingProvider(orderId).notifier).refresh(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: switch (state.phase) {
          OrderTrackingPhase.loading => const _Skeleton(),
          OrderTrackingPhase.notFound => _Message(
            key: const ValueKey<String>('tracking-not-found'),
            text: strings.orderTrackingNotFound,
          ),
          OrderTrackingPhase.unauthorized => _Message(
            key: const ValueKey<String>('tracking-unauthorized'),
            text: strings.orderTrackingSessionEnded,
          ),
          OrderTrackingPhase.error => _Retry(
            text: strings.orderTrackingCouldNotLoad,
            onRetry: () =>
                ref.read(orderTrackingProvider(orderId).notifier).refresh(),
          ),
          _ => _Tracking(
            state: state,
            now: ref.read(trackingClockProvider)(),
            onRefresh: () =>
                ref.read(orderTrackingProvider(orderId).notifier).refresh(),
          ),
        },
      ),
    );
  }
}

/// A shape the order will fill, rather than a spinner in the middle of nothing.
class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) => ListView(
    key: const ValueKey<String>('tracking-skeleton'),
    padding: const EdgeInsets.all(FotgSpacing.x4),
    children: <Widget>[
      for (final double height in <double>[96, 220, 120, 160])
        Padding(
          padding: const EdgeInsets.only(bottom: FotgSpacing.x3),
          child: Container(
            height: height,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(FotgRadius.lg),
            ),
          ),
        ),
    ],
  );
}

class _Tracking extends StatelessWidget {
  const _Tracking({
    required this.state,
    required this.now,
    required this.onRefresh,
  });

  final OrderTrackingState state;

  /// The device clock, read once per build, for "how long ago" only.
  final DateTime now;

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final TrackedOrder tracked = state.tracked!;
    final PlacedOrder order = tracked.order;

    final Duration? age = state.ageAt(now);
    final bool vouched = state.vouchesForStatusAt(now);

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        key: const ValueKey<String>('tracking-loaded'),
        padding: const EdgeInsets.all(FotgSpacing.x4),
        children: <Widget>[
          if (state.phase == OrderTrackingPhase.offline)
            Padding(
              padding: const EdgeInsets.only(bottom: FotgSpacing.x3),
              child: CartNotice(
                key: const ValueKey<String>('tracking-offline'),
                title: strings.orderTrackingOfflineTitle,
                /*
                 * The age, not just the warning.
                 *
                 * KI-031: "it may have changed since" reads the same whether
                 * the read is four minutes or four days old, and those are not
                 * the same situation for somebody deciding whether to pull in.
                 */
                body: age == null
                    ? strings.orderTrackingOfflineBody
                    : '${strings.orderTrackingOfflineBody} '
                          '${strings.orderTrackingUpdatedAgo(age)}.',
                tone: CartNoticeTone.advisory,
              ),
            ),

          /*
           * KI-031. Past TrackingConfig.vouchedFor the status and the timeline
           * come off the screen and this takes their place. Everything below —
           * the pickup window, the restaurant, the items, the amount paid, the
           * order number — stays, because none of it goes stale while nobody is
           * looking. Only the claim about where the order is right now expires.
           */
          if (!vouched) ...<Widget>[
            FotgCard(
              key: const ValueKey<String>('tracking-status-unknown'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    strings.orderTrackingStatusUnknownTitle,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: FotgSpacing.x2),
                  Text(
                    strings.orderTrackingStatusUnknownBody,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (age != null) ...<Widget>[
                    const SizedBox(height: FotgSpacing.x2),
                    Text(
                      strings.orderTrackingUpdatedAgo(age),
                      key: const ValueKey<String>('tracking-freshness'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  if (order.orderNumber case final String number) ...<Widget>[
                    const SizedBox(height: FotgSpacing.x3),
                    Text(
                      'Order #$number',
                      key: const ValueKey<String>('tracking-order-number'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: FotgSpacing.x3),
          ],

          if (vouched) ...<Widget>[
            _Hero(tracked: tracked),

            if (age != null) ...<Widget>[
              const SizedBox(height: FotgSpacing.x2),
              Text(
                strings.orderTrackingUpdatedAgo(age),
                key: const ValueKey<String>('tracking-freshness'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],

            const SizedBox(height: FotgSpacing.x4),

            FotgCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    strings.orderTrackingProgress,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: FotgSpacing.x3),
                  OrderTimelineView(steps: tracked.timeline),
                ],
              ),
            ),

            const SizedBox(height: FotgSpacing.x3),
          ],

          _PickupCard(tracked: tracked),

          if (order.restaurantName case final String name) ...<Widget>[
            const SizedBox(height: FotgSpacing.x3),
            FotgCard(
              key: const ValueKey<String>('tracking-restaurant'),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.storefront_rounded),
                  const SizedBox(width: FotgSpacing.x3),
                  Expanded(
                    child: Text(
                      name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: FotgSpacing.x3),
          _Items(order: order),

          const SizedBox(height: FotgSpacing.x3),
          _Payment(order: order),
        ],
      ),
    );
  }
}

/// The current status, and nothing competing with it.
class _Hero extends StatelessWidget {
  const _Hero({required this.tracked});

  final TrackedOrder tracked;

  @override
  Widget build(BuildContext context) {
    final PlacedOrder order = tracked.order;

    return FotgCard(
      key: const ValueKey<String>('tracking-hero'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            order.statusLabel,
            key: const ValueKey<String>('tracking-status'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),

          if (order.statusSubtitle case final String subtitle) ...<Widget>[
            const SizedBox(height: FotgSpacing.x1),
            Text(
              subtitle,
              key: const ValueKey<String>('tracking-subtitle'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],

          /*
           * The customer-safe reason, when somebody wrote one.
           *
           * Only ever the server's customer_safe_reason. An internal code, a
           * staffing note or an admin comment does not reach this widget
           * because it does not reach the response.
           */
          if (tracked.customerSafeReason case final String reason) ...<Widget>[
            const SizedBox(height: FotgSpacing.x2),
            Text(
              reason,
              key: const ValueKey<String>('tracking-reason'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],

          if (order.orderNumber case final String number) ...<Widget>[
            const SizedBox(height: FotgSpacing.x3),
            Text(
              'Order #$number',
              key: const ValueKey<String>('tracking-order-number'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _PickupCard extends StatelessWidget {
  const _PickupCard({required this.tracked});

  final TrackedOrder tracked;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final PlacedOrder order = tracked.order;

    return FotgCard(
      key: const ValueKey<String>('tracking-pickup'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            strings.orderTrackingRequestedPickup,
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: FotgSpacing.x1),

          if (order.pickupStartAt case final DateTime start)
            Text(
              order.pickupEndAt == null
                  ? TimeOfDay.fromDateTime(start).format(context)
                  : '${TimeOfDay.fromDateTime(start).format(context)} – '
                        '${TimeOfDay.fromDateTime(order.pickupEndAt!).format(context)}',
              style: Theme.of(context).textTheme.titleMedium,
            ),

          const SizedBox(height: FotgSpacing.x1),

          /*
           * Requested, not estimated.
           *
           * Module 18 builds the ETA engine. Until it exists this screen must
           * not imply it knows when the food will actually be ready, and the
           * cheapest way to keep that promise is to say so on the card.
           */
          Text(
            strings.orderTrackingRequestedPickupNote,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),

          if (tracked.pickupCredentialAvailable) ...<Widget>[
            const SizedBox(height: FotgSpacing.x3),
            Text(
              strings.orderTrackingUseCodeWhenReady,
              key: const ValueKey<String>('tracking-code-guidance'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _Items extends StatelessWidget {
  const _Items({required this.order});

  final PlacedOrder order;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);

    return FotgCard(
      key: const ValueKey<String>('tracking-items'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            strings.orderTrackingYourOrder,
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: FotgSpacing.x2),

          // Snapshots, from the order rather than from today's menu. A receipt
          // that changed when a restaurant renamed a dish would not be one.
          for (final OrderLine line in order.items)
            Padding(
              padding: const EdgeInsets.only(bottom: FotgSpacing.x2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('${line.quantity}×  '),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(line.name),
                        if (line.variant case final String variant)
                          Text(
                            variant,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        if (line.modifiers.isNotEmpty)
                          Text(
                            line.modifiers
                                .map((OrderLineModifier m) => m.option)
                                .join(', '),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                  Text(line.lineTotal.format()),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// What was paid, read from the payment rather than inferred from the order.
///
/// An order being rejected does not make its payment refunded. No refund
/// workflow exists in this build, so nothing here can or does claim one.
class _Payment extends StatelessWidget {
  const _Payment({required this.order});

  final PlacedOrder order;

  @override
  Widget build(BuildContext context) => FotgCard(
    key: const ValueKey<String>('tracking-payment'),
    child: Row(
      children: <Widget>[
        Expanded(
          child: Text(
            order.payment?.customerLabel ?? 'Payment',
            key: const ValueKey<String>('tracking-payment-status'),
          ),
        ),
        Text(
          order.commercial.payableTotal.format(),
          key: const ValueKey<String>('tracking-total'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ],
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(FotgSpacing.x6),
      child: Text(text, textAlign: TextAlign.center),
    ),
  );
}

class _Retry extends StatelessWidget {
  const _Retry({required this.text, required this.onRetry});

  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);

    return Center(
      key: const ValueKey<String>('tracking-error'),
      child: Padding(
        padding: const EdgeInsets.all(FotgSpacing.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(text, textAlign: TextAlign.center),
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
