import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/tokens.dart';

/// The four-step explanation shown to a customer with no journey.
///
/// The route motif again: numbered stops connected by a line, because the steps
/// *are* a journey. This is the screen's answer to "what is this app for" and it
/// only appears when there is nothing more useful to show.
class HowItWorks extends StatelessWidget {
  const HowItWorks({super.key});

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);

    final List<(IconData, String, String)> steps = <(IconData, String, String)>[
      (
        Icons.route_outlined,
        strings.howItWorksStep1Title,
        strings.howItWorksStep1Body,
      ),
      (
        Icons.storefront_outlined,
        strings.howItWorksStep2Title,
        strings.howItWorksStep2Body,
      ),
      (
        Icons.schedule_outlined,
        strings.howItWorksStep3Title,
        strings.howItWorksStep3Body,
      ),
      (
        Icons.takeout_dining_outlined,
        strings.howItWorksStep4Title,
        strings.howItWorksStep4Body,
      ),
    ];

    return Column(
      children: <Widget>[
        for (int i = 0; i < steps.length; i++)
          _Step(
            index: i + 1,
            icon: steps[i].$1,
            title: steps[i].$2,
            body: steps[i].$3,
            isLast: i == steps.length - 1,
          ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.index,
    required this.icon,
    required this.title,
    required this.body,
    required this.isLast,
  });

  final int index;
  final IconData icon;
  final String title;
  final String body;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Column(
            children: <Widget>[
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '$index',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(width: 2, color: theme.colorScheme.outline),
                ),
            ],
          ),
          const SizedBox(width: FotgSpacing.x4),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : FotgSpacing.x5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(
                        icon,
                        size: FotgSizing.iconSm,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: FotgSpacing.x2),
                      Expanded(
                        child: Text(title, style: theme.textTheme.labelLarge),
                      ),
                    ],
                  ),
                  const SizedBox(height: FotgSpacing.x1),
                  Text(
                    body,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
