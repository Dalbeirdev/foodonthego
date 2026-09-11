import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../domain/models/order_timeline.dart';

/// The order's progress, drawn once.
///
/// **NOT COLOUR ALONE.** Each step carries an icon, a label and a semantics
/// sentence saying what state it is in, because a customer who cannot
/// distinguish green from grey still has to be able to tell what has happened
/// to their food. Colour is the least of the three signals rather than the
/// only one.
///
/// Every step's state was decided by the server. This widget renders what it
/// was given and works nothing out — including which step is next, which is why
/// an unfamiliar status still draws correctly.
class OrderTimelineView extends StatelessWidget {
  const OrderTimelineView({required this.steps, super.key});

  final List<OrderTimelineStep> steps;

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey<String>('tracking-timeline'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      for (int i = 0; i < steps.length; i++)
        _Step(step: steps[i], isLast: i == steps.length - 1),
    ],
  );
}

class _Step extends StatelessWidget {
  const _Step({required this.step, required this.isLast});

  final OrderTimelineStep step;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    final (IconData icon, Color colour, String spoken) = switch (step.state) {
      OrderTimelineStepState.completed => (
        Icons.check_circle_rounded,
        scheme.primary,
        'Completed',
      ),
      OrderTimelineStepState.current => (
        Icons.radio_button_checked_rounded,
        scheme.primary,
        'Current status',
      ),
      OrderTimelineStepState.upcoming => (
        Icons.radio_button_unchecked_rounded,
        scheme.outline,
        'Not started',
      ),
      OrderTimelineStepState.exception => (
        Icons.cancel_rounded,
        scheme.error,
        'Order ended here',
      ),
    };

    final String? time = step.occurredAt == null
        ? null
        : TimeOfDay.fromDateTime(step.occurredAt!).format(context);

    return Semantics(
      /*
       * One sentence per step, read the way a person would say it.
       *
       * "Cooking. Current status. at 4:05 PM." rather than an icon name and a
       * bare number. A screen reader announcing "check circle, 4:05" tells
       * somebody nothing about their order.
       */
      label: <String>[
        step.title,
        spoken,
        if (time != null) 'at $time',
        if (step.note case final String note) note,
      ].join('. '),
      excludeSemantics: true,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Column(
              children: <Widget>[
                Icon(icon, size: 22, color: colour),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(
                        vertical: FotgSpacing.x1,
                      ),
                      color: step.isCompleted
                          ? scheme.primary.withValues(alpha: 0.4)
                          : scheme.outlineVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(width: FotgSpacing.x3),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: isLast ? 0 : FotgSpacing.x4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      step.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        // Weight, not colour, marks the current step: it
                        // survives greyscale and colour blindness.
                        fontWeight: step.isCurrent
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: step.state == OrderTimelineStepState.upcoming
                            ? scheme.onSurfaceVariant
                            : null,
                      ),
                    ),
                    if (time != null)
                      Text(
                        time,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    if (step.note case final String note) ...<Widget>[
                      const SizedBox(height: FotgSpacing.x1),
                      Text(note, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
