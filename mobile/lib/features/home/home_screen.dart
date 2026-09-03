import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../shared/widgets/fotg_card.dart';

/// The customer's home screen.
///
/// Module 01 renders the greeting and the journey call-to-action so the theme,
/// typography and safe-area handling can be verified against something real. The
/// planner behind the button belongs to Module 09 and the button says so rather
/// than opening an empty screen.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, this.customerName = 'Rahul', this.now});

  final String customerName;

  /// Injectable so the greeting can be tested at a known hour.
  final DateTime? now;

  static String greetingFor(DateTime time) {
    final int hour = time.hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String greeting = greetingFor(now ?? DateTime.now());

    return Scaffold(
      // SafeArea, not a hard-coded top inset: this has to clear a notch, a Dynamic
      // Island and a plain status bar without three different numbers.
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            FotgSpacing.x5,
            FotgSpacing.x6,
            FotgSpacing.x5,
            FotgSpacing.x10,
          ),
          children: <Widget>[
            Text(
              '$greeting, $customerName',
              style: theme.textTheme.displaySmall,
            ),
            const SizedBox(height: FotgSpacing.x2),
            Text(
              'Where are you travelling today?',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: FotgSpacing.x6),

            _JourneyCard(theme: theme),

            const SizedBox(height: FotgSpacing.x6),
            Text('How FoodOnTheGo works', style: theme.textTheme.titleLarge),
            const SizedBox(height: FotgSpacing.x3),
            const _HowItWorksStep(
              index: 1,
              icon: Icons.route_outlined,
              title: 'Tell us your route',
              body: 'Origin and destination — for example Delhi to Jaipur.',
            ),
            const _HowItWorksStep(
              index: 2,
              icon: Icons.storefront_outlined,
              title: 'Pick a kitchen on the way',
              body: 'Restaurants a short detour from your route, with the detour shown in minutes.',
            ),
            const _HowItWorksStep(
              index: 3,
              icon: Icons.schedule_outlined,
              title: 'Order before you arrive',
              body: 'The kitchen starts cooking against your arrival time, not when you tap.',
            ),
            const _HowItWorksStep(
              index: 4,
              icon: Icons.takeout_dining_outlined,
              title: 'Collect and go',
              body: 'Food ready as you pull in — not made an hour early, not made on arrival.',
              isLast: true,
            ),

            const SizedBox(height: FotgSpacing.x6),
            _FoundationNotice(theme: theme),
          ],
        ),
      ),
    );
  }
}

class _JourneyCard extends StatelessWidget {
  const _JourneyCard({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return FotgCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(FotgSpacing.x2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: FotgRadius.control,
                ),
                child: Icon(
                  Icons.map_outlined,
                  color: theme.colorScheme.onSecondaryContainer,
                  size: FotgSizing.iconMd,
                ),
              ),
              const SizedBox(width: FotgSpacing.x3),
              Expanded(
                child: Text(
                  'Plan a journey',
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: FotgSpacing.x3),
          Text(
            'Choose where you are starting and where you are heading, and we will find kitchens '
            'along the way.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: FotgSpacing.x5),
          // Disabled with a visible reason: an enabled button that opens nothing is
          // worse than one that explains itself.
          FilledButton.icon(
            onPressed: null,
            icon: const Icon(Icons.add_road_outlined),
            label: const Text('Plan a journey'),
          ),
          const SizedBox(height: FotgSpacing.x2),
          Text(
            'Journey planning arrives in Module 09 — Route & Corridor Management.',
            style: theme.textTheme.labelSmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _HowItWorksStep extends StatelessWidget {
  const _HowItWorksStep({
    required this.index,
    required this.icon,
    required this.title,
    required this.body,
    this.isLast = false,
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
                  borderRadius: FotgRadius.pill,
                ),
                alignment: Alignment.center,
                child: Text(
                  '$index',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
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
                  Text(body, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FoundationNotice extends StatelessWidget {
  const _FoundationNotice({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final bool isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(FotgSpacing.x4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F1E38) : FotgColors.infoSurface,
        borderRadius: FotgRadius.control,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.info_outline,
            size: FotgSizing.iconSm,
            color: isDark ? FotgColors.darkInfo : FotgColors.info,
          ),
          const SizedBox(width: FotgSpacing.x3),
          Expanded(
            child: Text(
              'Module 01 — foundation only. Nothing on this screen is live data: no journeys, '
              'restaurants or orders exist yet. Rahul Sharma is a development test persona.',
              style: theme.textTheme.labelMedium?.copyWith(
                color: isDark ? FotgColors.darkInfo : FotgColors.info,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
