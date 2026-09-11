import 'package:flutter/material.dart';

import '../../../core/format/journey_measures.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/models/trip_route.dart';

/// One route to choose from.
///
/// A card rather than only a line on the map, because a two-pixel polyline on a
/// moving map is not a control anybody can rely on — least of all with a screen
/// reader, one hand, or a bus going over a pothole. The map tap is a
/// convenience; this is the way.
class RouteOptionCard extends StatelessWidget {
  const RouteOptionCard({
    required this.route,
    required this.isSelected,
    required this.onSelect,
    this.comparedWith,
    this.isBusy = false,
    super.key,
  });

  final TripRoute route;
  final bool isSelected;
  final VoidCallback onSelect;

  /// The recommended route, so this one can say how it differs.
  final TripRoute? comparedWith;

  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppStrings strings = AppStrings.of(context);

    final String duration = JourneyMeasures.duration(
      route.effectiveDurationSeconds,
    );
    final String distance = JourneyMeasures.distance(route.distanceMeters);
    final String? delay = JourneyMeasures.trafficDelay(
      route.trafficDelaySeconds,
    );

    final String? comparison = comparedWith == null || route.isRecommended
        ? null
        : JourneyMeasures.comparison(
            metres: route.distanceMeters,
            seconds: route.effectiveDurationSeconds,
            againstMetres: comparedWith!.distanceMeters,
            againstSeconds: comparedWith!.effectiveDurationSeconds,
          );

    return Semantics(
      button: true,
      selected: isSelected,
      label: <String>[
        route.isRecommended
            ? strings.routeRecommended
            : strings.routeAlternative,
        ?route.summary,
        duration,
        distance,
        ?(delay == null ? null : '${strings.routeTrafficLabel} $delay'),
        ?comparison,
        if (isSelected) strings.routeSelected,
      ].join(', '),
      excludeSemantics: true,
      // Declared here as well as on the InkWell: excluding the children's
      // semantics also removes their tap action, and a labelled button nothing
      // can press is worse than an unlabelled one.
      onTap: isBusy ? null : onSelect,
      child: Container(
        margin: const EdgeInsets.only(bottom: FotgSpacing.x3),
        decoration: BoxDecoration(
          borderRadius: FotgRadius.card,
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline,
            // Selection is a border width as well as a colour, so it survives
            // a screen nobody can read subtle hue differences on.
            width: isSelected ? 2 : 1,
          ),
          color: isSelected
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.18)
              : null,
        ),
        child: InkWell(
          onTap: isBusy ? null : onSelect,
          borderRadius: FotgRadius.card,
          child: Padding(
            padding: const EdgeInsets.all(FotgSpacing.x4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      // Wraps rather than a Row: two chips plus the radio
                      // control and the card's padding overflow a 390dp phone
                      // by a few pixels, and at 1.6x text they overflow every
                      // phone. A second line is the correct answer; a striped
                      // overflow bar is not.
                      Wrap(
                        spacing: FotgSpacing.x2,
                        runSpacing: FotgSpacing.x1,
                        children: <Widget>[
                          _Chip(
                            label: route.isRecommended
                                ? strings.routeRecommended
                                : strings.routeAlternative,
                            emphasis: route.isRecommended,
                          ),
                          // Spelled out, never signalled by colour alone.
                          if (isSelected)
                            _Chip(label: strings.routeSelected, emphasis: true),
                        ],
                      ),
                      const SizedBox(height: FotgSpacing.x2),
                      Text(duration, style: theme.textTheme.titleMedium),
                      Text(
                        distance,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (route.summary != null)
                        Text(
                          route.summary!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (delay != null)
                        Text(
                          '${strings.routeTrafficLabel} $delay',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      if (comparison != null)
                        Text(
                          comparison,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                if (isBusy)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                  )
                else
                  Icon(
                    isSelected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.emphasis});

  final String label;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FotgSpacing.x2,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: emphasis
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(FotgRadius.sm),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: emphasis
              ? theme.colorScheme.onPrimaryContainer
              : theme.colorScheme.onSurfaceVariant,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
