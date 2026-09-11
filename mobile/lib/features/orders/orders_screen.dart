import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/tokens.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/routing/routes.dart';
import '../../domain/models/placed_order.dart';
import '../../shared/state/providers.dart';
import '../../domain/repositories/home_repository.dart';
import '../../shared/widgets/app_error_view.dart';
import '../../shared/widgets/app_skeleton.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/empty_state_view.dart';
import '../../shared/widgets/fotg_card.dart';

/// The customer's orders, from the server.
///
/// **Only placed orders appear here.** The list endpoint filters on placed_at,
/// so a basket somebody started and never paid for is absent — showing one
/// would tell a customer they had bought food they have not.
///
/// Module 17 adds the tracking timeline. This shows what an order is and what
/// was agreed, and stops there.
class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppStrings strings = AppStrings.of(context);
    final AsyncValue<List<PlacedOrder>> orders = ref.watch(myOrdersProvider);

    return Scaffold(
      appBar: AppBar(title: Text(strings.navOrders)),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () async => ref.refresh(myOrdersProvider.future),
          child: orders.when(
            loading: () => const _OrdersSkeleton(),
            error: (Object error, StackTrace _) => AppErrorView(
              key: const ValueKey<String>('orders-error'),
              // The shared failure vocabulary, not the exception's text. A
              // customer has no use for a FormatException, and a stack trace is
              // worse than useless to them.
              kind: HomeFailureKind.unknown,
              onRetry: () => ref.invalidate(myOrdersProvider),
            ),
            data: (List<PlacedOrder> list) =>
                list.isEmpty ? _empty(context, strings) : _list(list),
          ),
        ),
      ),
    );
  }

  Widget _empty(BuildContext context, AppStrings strings) => ListView(
    // Scrollable even when empty, or pull-to-refresh has nothing to grab and a
    // customer who suspects the list is stale cannot ask it to reload.
    physics: const AlwaysScrollableScrollPhysics(),
    children: <Widget>[
      SizedBox(height: MediaQuery.sizeOf(context).height * 0.12),
      EmptyStateView(
        key: const ValueKey<String>('orders-empty'),
        icon: Icons.receipt_long_rounded,
        title: strings.ordersEmptyTitle,
        body: strings.ordersEmptyBody,
        action: PrimaryButton(
          label: strings.plannerCta,
          icon: Icons.near_me_rounded,
          expand: false,
          onPressed: () => context.go(Routes.trips),
        ),
      ),
    ],
  );

  Widget _list(List<PlacedOrder> orders) => ListView.separated(
    key: const ValueKey<String>('orders-list'),
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.all(FotgSpacing.x4),
    itemCount: orders.length,
    separatorBuilder: (BuildContext _, int _) =>
        const SizedBox(height: FotgSpacing.x3),
    itemBuilder: (BuildContext context, int index) =>
        _OrderRow(order: orders[index]),
  );
}

class _OrderRow extends StatelessWidget {
  const _OrderRow({required this.order});

  final PlacedOrder order;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppStrings strings = AppStrings.of(context);

    return FotgCard(
      key: ValueKey<String>('order-row-${order.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          /*
           * Wrap, not Row, and this is not a style preference.
           *
           * At 320 px with the text scaled to 2x — a small phone belonging to
           * somebody who needs large type, which is a real customer and not an
           * edge case — a Row overflowed by 44 pixels and Flutter painted the
           * yellow-and-black stripes over the total. Expanded on the name does
           * not help, because the amount itself is what no longer fits.
           *
           * Wrap puts the two side by side when they fit and stacks them when
           * they do not. Nothing is truncated, and the amount a customer paid
           * is never the thing that gets clipped.
           */
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: FotgSpacing.x2,
            runSpacing: FotgSpacing.x1,
            children: <Widget>[
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.55,
                ),
                child: Text(
                  order.restaurantName ?? strings.ordersUnknownRestaurant,
                  style: theme.textTheme.titleMedium,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                order.commercial.payableTotal.format(),
                style: theme.textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: FotgSpacing.x1),

          // The number, when there is one. Every row in this list is a placed
          // order so there always should be; rendering conditionally rather
          // than with a bang means a server that somehow sent one without a
          // number shows a row missing a line instead of crashing the tab.
          if (order.orderNumber case final String number)
            Text(
              number,
              style: theme.textTheme.bodySmall,
              key: ValueKey<String>('order-row-number-${order.id}'),
            ),

          const SizedBox(height: FotgSpacing.x2),

          /*
           * "Order placed", never "Accepted".
           *
           * The restaurant has not seen this order yet. A label implying they
           * had would be the app promising something on their behalf, and the
           * customer would be at a counter expecting food nobody has started.
           */
          Row(
            children: <Widget>[
              Icon(
                Icons.check_circle_outline_rounded,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: FotgSpacing.x1),
              // Flexible, for the same reason as the row above: at 2x text on a
              // 320 px phone "Order placed" beside an icon no longer fits, and
              // an unflexible child overflows rather than wrapping.
              Flexible(
                child: Text(
                  order.statusLabel,
                  key: ValueKey<String>('order-row-status-${order.id}'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: FotgSpacing.x3),

          /*
           | The way in to tracking.
           |
           | On the card rather than on the whole row: a card that navigates
           | anywhere it is touched is a card a customer opens by accident
           | while scrolling, and this one carries a total they may be reading.
           */
          Align(
            alignment: Alignment.centerLeft,
            child: SecondaryButton(
              key: ValueKey<String>('order-row-track-${order.id}'),
              label: strings.orderTrackingTrackCta,
              expand: false,
              onPressed: () => context.push(Routes.orderTrackingPath(order.id)),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrdersSkeleton extends StatelessWidget {
  const _OrdersSkeleton();

  @override
  Widget build(BuildContext context) => ListView(
    key: const ValueKey<String>('orders-loading'),
    padding: const EdgeInsets.all(FotgSpacing.x4),
    children: const <Widget>[
      AppSkeleton(height: 96),
      SizedBox(height: FotgSpacing.x3),
      AppSkeleton(height: 96),
    ],
  );
}
