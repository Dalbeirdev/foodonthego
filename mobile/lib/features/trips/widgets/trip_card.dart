import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/format/journey_measures.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/time/journey_time.dart';
import '../../../domain/models/trip.dart';

/// One journey in the list.
///
/// The row leads with the route, because "New Delhi → Jaipur" is how somebody
/// identifies their own journey. The second line says what the app actually
/// knows — that no route has been calculated — rather than a distance or a
/// travel time it would have to invent. Module 06 replaces that line with the
/// real thing; until then a placeholder number would be read as a real one.
class TripListItem extends StatelessWidget {
  const TripListItem({
    required this.trip,
    required this.onOpen,
    this.onDiscard,
    this.busy = false,
    super.key,
  });

  final Trip trip;
  final VoidCallback onOpen;
  final VoidCallback? onDiscard;

  /// True while one of this row's actions is in flight. The row disables itself
  /// rather than the screen freezing, so the rest of the list stays usable.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final ThemeData theme = Theme.of(context);

    return Opacity(
      opacity: busy ? 0.55 : 1,
      child: InkWell(
        onTap: busy ? null : onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: FotgSpacing.x5,
            vertical: FotgSpacing.x4,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _RouteIcon(trip: trip),
              const SizedBox(width: FotgSpacing.x4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      trip.routeSummary,
                      style: theme.textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: FotgSpacing.x1),
                    Text(
                      // The real figures once a route exists, and an honest
                      // absence until then. `hasRoute` requires both a READY
                      // status *and* a summary the server was willing to send,
                      // so a journey whose endpoints moved falls back to the
                      // second line rather than showing a stale distance.
                      trip.hasRoute
                          ? '${JourneyMeasures.duration(trip.selectedRoute!.effectiveDurationSeconds)}'
                                ' · ${JourneyMeasures.distance(trip.selectedRoute!.distanceMeters)}'
                          : strings.tripRouteNotCalculated,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (trip.createdAt != null) ...<Widget>[
                      const SizedBox(height: FotgSpacing.x1),
                      Text(
                        '${strings.tripCreatedAtLabel} ${JourneyTime.compact(trip.createdAt!)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (trip.isCancelled) ...<Widget>[
                      const SizedBox(height: FotgSpacing.x2),
                      _StateBadge(
                        // Spelled out as words, never signalled by colour alone:
                        // a discarded journey has to read as discarded to
                        // somebody who cannot distinguish the two greys.
                        label: strings.tripCancelledLabel,
                        emphasis: true,
                      ),
                    ],
                  ],
                ),
              ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.only(left: FotgSpacing.x2),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (onDiscard != null)
                _RowActions(trip: trip, onDiscard: onDiscard),
            ],
          ),
        ),
      ),
    );
  }
}

class _RouteIcon extends StatelessWidget {
  const _RouteIcon({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dimmed = trip.isCancelled;

    final Color background = dimmed
        ? theme.colorScheme.surfaceContainerHighest
        : theme.colorScheme.primaryContainer;

    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(FotgRadius.md),
      ),
      child: Icon(
        trip.isCancelled ? Icons.block_rounded : Icons.route_rounded,
        size: 22,
        color: dimmed
            ? theme.colorScheme.onSurfaceVariant
            : theme.colorScheme.onPrimaryContainer,
      ),
    );
  }
}

class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.label, required this.emphasis});

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
            ? theme.colorScheme.errorContainer
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(FotgRadius.sm),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: emphasis
              ? theme.colorScheme.onErrorContainer
              : theme.colorScheme.onSurfaceVariant,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// One overflow button whose tooltip names its own row.
///
/// Not a bare "Options": a screen reader announcing the same label on every row
/// tells somebody nothing about which journey they are on. The Module 04 row
/// menu learned this the hard way.
class _RowActions extends StatelessWidget {
  const _RowActions({required this.trip, this.onDiscard});

  final Trip trip;
  final VoidCallback? onDiscard;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);

    return PopupMenuButton<int>(
      tooltip: strings.tripOptionsFor(trip.routeSummary),
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (int value) {
        if (value == 0) onDiscard?.call();
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<int>>[
        if (onDiscard != null)
          PopupMenuItem<int>(
            value: 0,
            child: Text(
              strings.tripDetailDiscard,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}
