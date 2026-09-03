import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/models/active_order_summary.dart';
import '../../../domain/models/order_status.dart';
import '../../../shared/widgets/buttons.dart';
import '../../../shared/widgets/order_status_chip.dart';

/// The active-order card.
///
/// The question it answers is not "what did I order" but **"when do I need to be
/// there"** — so the countdown is the largest thing on the card, and the status
/// track sits under it to show how close the kitchen is.
class ActiveOrderCard extends StatelessWidget {
  const ActiveOrderCard({required this.order, this.onTap, this.now, super.key});

  final ActiveOrderSummary order;
  final VoidCallback? onTap;

  /// Injectable so the countdown can be tested at a known instant.
  final DateTime? now;

  /// Rounded to the nearest minute, floored at zero.
  ///
  /// A negative countdown — the clock passing an estimate that has not been
  /// refreshed — must read "Ready now", never "-3 min".
  static int? minutesUntil(DateTime? target, DateTime reference) {
    if (target == null) return null;
    final int minutes = target.difference(reference).inMinutes;
    return minutes < 0 ? 0 : minutes;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppStrings strings = AppStrings.of(context);
    final int? minutes = minutesUntil(
      order.estimatedPickup,
      now ?? DateTime.now(),
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(FotgSpacing.x5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: FotgRadius.control,
                    ),
                    child: Icon(
                      Icons.storefront_rounded,
                      size: FotgSizing.iconMd,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: FotgSpacing.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          order.restaurantName,
                          style: theme.textTheme.titleMedium,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          <String>[
                            strings.orderReference(order.reference),
                            if (order.itemCount != null)
                              strings.orderItemCount(order.itemCount!),
                          ].join('  ·  '),
                          style: theme.textTheme.labelSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: FotgSpacing.x4),

              // The countdown, and the status beside it.
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          minutes == null || minutes == 0
                              ? strings.orderPickupNow
                              : strings.orderPickupIn,
                          style: theme.textTheme.labelSmall,
                        ),
                        if (minutes != null && minutes > 0)
                          Text.rich(
                            TextSpan(
                              children: <InlineSpan>[
                                TextSpan(
                                  text: '$minutes',
                                  style: theme.textTheme.headlineMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                TextSpan(
                                  text: ' min',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  OrderStatusChip(status: order.status),
                ],
              ),

              if (order.status != OrderStatus.cancelled) ...<Widget>[
                const SizedBox(height: FotgSpacing.x4),
                OrderStatusTrack(status: order.status),
                const SizedBox(height: FotgSpacing.x2),
                Text(
                  order.status.explanation,
                  style: theme.textTheme.labelSmall,
                ),
              ],

              if (onTap != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: LinkAction(
                    label: strings.orderViewCta,
                    icon: Icons.arrow_forward_rounded,
                    onPressed: onTap,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
