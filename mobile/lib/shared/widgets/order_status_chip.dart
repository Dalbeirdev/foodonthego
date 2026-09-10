import 'package:flutter/material.dart';

import '../../core/theme/status_palette.dart';
import '../../core/theme/tokens.dart';
import '../../domain/models/placed_order.dart';

/// A compact order-state indicator: icon + label + colour.
///
/// The icon is not decoration — it is the redundant channel that makes the state
/// readable without colour vision, and the label makes it readable without either.
class OrderStatusChip extends StatelessWidget {
  const OrderStatusChip({required this.status, this.dense = false, super.key});

  final PlacedOrderStatus status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final OrderStatusStyle style = OrderStatusStyle.of(
      status,
      theme.brightness,
    );

    return Semantics(
      label: 'Order status: ${status.label}',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: dense ? FotgSpacing.x2 : FotgSpacing.x3,
          vertical: dense ? FotgSpacing.x1 : 6,
        ),
        decoration: BoxDecoration(
          color: style.background,
          borderRadius: FotgRadius.pill,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(style.icon, size: dense ? 14 : 16, color: style.foreground),
            SizedBox(width: dense ? FotgSpacing.x1 : 6),
            Flexible(
              child: Text(
                status.label,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: style.foreground,
                  fontWeight: FontWeight.w700,
                  fontSize: dense ? 12 : 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The five-step progress track shown on an active order.
///
/// An order that is not on the fulfilment path does not render a track at all —
/// drawing the remaining steps as "still to come" for an order that will never
/// reach them is a lie.
///
/// It used to ask `status == cancelled`, which was right for the six states the
/// old client-side enum knew. On [PlacedOrderStatus] there are five ways off the
/// path, not one, and a rejected order would have drawn four steps still to
/// come. Asking whether the state has a place on the track instead of naming the
/// states that do not is what stops the next one being missed.
class OrderStatusTrack extends StatelessWidget {
  const OrderStatusTrack({required this.status, super.key});

  final PlacedOrderStatus status;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    if (!status.isOnFulfilmentPath) return const SizedBox.shrink();

    final int current = status.fulfilmentStep;

    return Semantics(
      label:
          'Progress: step ${current + 1} of '
          '${PlacedOrderStatus.fulfilmentProgression.length}, ${status.label}',
      excludeSemantics: true,
      child: Row(
        children: <Widget>[
          for (
            int i = 0;
            i < PlacedOrderStatus.fulfilmentProgression.length;
            i++
          ) ...<Widget>[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: i <= current ? 1 : 0),
                duration: FotgMotion.respectingReducedMotion(
                  context,
                  FotgMotion.slow,
                ),
                curve: FotgMotion.standard,
                builder: (BuildContext context, double value, _) => Stack(
                  children: <Widget>[
                    Container(
                      height: 5,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.outline,
                        borderRadius: FotgRadius.pill,
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: value,
                      child: Container(
                        height: 5,
                        decoration: BoxDecoration(
                          color: OrderStatusStyle.of(
                            status,
                            theme.brightness,
                          ).foreground,
                          borderRadius: FotgRadius.pill,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
