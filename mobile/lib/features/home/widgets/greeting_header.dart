import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/models/customer_summary.dart';

/// The home screen's header: who you are, and a one-line read on your situation.
///
/// Kept to three elements — greeting, subtitle, avatar. A header that also
/// carries a search field, a notification bell and a location chip stops being a
/// greeting and becomes a toolbar.
class GreetingHeader extends StatelessWidget {
  const GreetingHeader({
    required this.customer,
    required this.isTravelling,
    this.onAvatarTap,
    this.now,
    super.key,
  });

  final CustomerSummary customer;
  final bool isTravelling;
  final VoidCallback? onAvatarTap;

  /// Injectable so the greeting can be tested at a known hour.
  final DateTime? now;

  /// 05:00–11:59 morning · 12:00–16:59 afternoon · otherwise evening.
  ///
  /// The small hours are checked FIRST. Ordering the morning test before a bare
  /// `hour < 17` meant 04:00 fell through to "Good afternoon" — which matters
  /// here, because pre-dawn starts are exactly when people set off on a long
  /// drive and open this app.
  static String greetingFor(DateTime time, AppStrings strings, String name) {
    final int hour = time.hour;
    if (hour < 5 || hour >= 17) return strings.greetingEvening(name);
    if (hour < 12) return strings.greetingMorning(name);
    return strings.greetingAfternoon(name);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppStrings strings = AppStrings.of(context);
    final String greeting = greetingFor(
      now ?? DateTime.now(),
      strings,
      customer.greetingName,
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // The greeting steps down on a narrow phone. At 34sp on a 320dp screen
        // "Good evening, Rahul" truncated to "Good evening, R…" — losing the
        // name, which is the entire point of greeting somebody. The avatar and
        // the horizontal padding leave barely 210dp for the text there.
        final TextStyle? greetingStyle = constraints.maxWidth < 300
            ? theme.textTheme.headlineMedium
            : constraints.maxWidth < 360
            ? theme.textTheme.headlineLarge
            : theme.textTheme.displaySmall;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    greeting,
                    style: greetingStyle,
                    // Two lines, then ellipsis: a long first name must not push the
                    // avatar off screen, but it should still be readable.
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: FotgSpacing.x1),
                  Text(
                    isTravelling
                        ? strings.greetingSubtitleTravelling
                        : strings.greetingSubtitleIdle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: FotgSpacing.x4),
            _Avatar(customer: customer, onTap: onAvatarTap),
          ],
        );
      },
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.customer, this.onTap});

  final CustomerSummary customer;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Semantics(
      button: onTap != null,
      label: 'Profile, ${customer.fullName}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          // The tappable box is 48dp even though the circle is 46 — the target,
          // not the paint, is what has to clear the accessibility floor.
          width: FotgSizing.touchTargetMin,
          height: FotgSizing.touchTargetMin,
          child: Center(
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                shape: BoxShape.circle,
                border: Border.all(color: theme.colorScheme.outline),
              ),
              alignment: Alignment.center,
              child: Text(
                customer.initials,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
