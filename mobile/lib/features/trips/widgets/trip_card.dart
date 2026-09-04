import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/time/journey_time.dart';
import '../../../domain/models/trip.dart';

/// One journey in the list.
///
/// The row leads with the route, because "New Delhi → Jaipur" is how somebody
/// identifies their own journey; the departure is the second line, because it is
/// how they tell two journeys on the same route apart.
class TripListItem extends StatelessWidget {
  const TripListItem({
    required this.trip,
    required this.onOpen,
    this.onEdit,
    this.onCancel,
    this.busy = false,
    super.key,
  });

  final Trip trip;
  final VoidCallback onOpen;
  final VoidCallback? onEdit;
  final VoidCallback? onCancel;

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
                      JourneyTime.compact(trip.departureAt),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (trip.travellerCount > 1) ...<Widget>[
                      const SizedBox(height: FotgSpacing.x1),
                      Text(
                        strings.tripTravellers(trip.travellerCount),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (trip.isCancelled || trip.hasDeparted) ...<Widget>[
                      const SizedBox(height: FotgSpacing.x2),
                      _StateBadge(
                        // Spelled out as words, never signalled by colour alone:
                        // a cancelled journey has to read as cancelled to
                        // somebody who cannot distinguish the two greys.
                        label: trip.isCancelled
                            ? strings.tripCancelledLabel
                            : strings.tripDepartedLabel,
                        emphasis: trip.isCancelled,
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
              else if (onEdit != null || onCancel != null)
                _RowActions(trip: trip, onEdit: onEdit, onCancel: onCancel),
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
    final bool dimmed = trip.isCancelled || trip.hasDeparted;

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
  const _RowActions({required this.trip, this.onEdit, this.onCancel});

  final Trip trip;
  final VoidCallback? onEdit;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);

    return PopupMenuButton<int>(
      tooltip: strings.tripOptionsFor(trip.routeSummary),
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (int value) {
        if (value == 0) onEdit?.call();
        if (value == 1) onCancel?.call();
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<int>>[
        if (onEdit != null)
          PopupMenuItem<int>(value: 0, child: Text(strings.tripDetailEdit)),
        if (onCancel != null)
          PopupMenuItem<int>(
            value: 1,
            child: Text(
              strings.tripDetailCancel,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}
