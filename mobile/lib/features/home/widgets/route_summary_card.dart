import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/models/active_trip_summary.dart';
import '../../../shared/widgets/buttons.dart';

/// The active-journey card: where you are between two places.
///
/// Rendered as a horizontal route — origin, progress line, destination — because
/// that is the shape of the information. Progress is only drawn when a value
/// exists; a bar sitting at zero would imply the journey has not started when in
/// fact nothing has computed it yet.
class RouteSummaryCard extends StatelessWidget {
  const RouteSummaryCard({required this.trip, this.onTap, super.key});

  final ActiveTripSummary trip;
  final VoidCallback? onTap;

  static String formatDuration(Duration duration) {
    final int hours = duration.inHours;
    final int minutes = duration.inMinutes.remainder(60);
    if (hours == 0) return '$minutes min';
    if (minutes == 0) return '$hours hr';
    return '$hours hr $minutes min';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppStrings strings = AppStrings.of(context);
    final double? progress = trip.clampedProgress;

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
                children: <Widget>[
                  Icon(
                    Icons.route_rounded,
                    size: FotgSizing.iconSm,
                    color: theme.colorScheme.secondary,
                  ),
                  const SizedBox(width: FotgSpacing.x2),
                  Expanded(
                    child: Text(
                      trip.status.label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.secondary,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (trip.remainingDuration != null)
                    Text(
                      '${formatDuration(trip.remainingDuration!)} ${strings.journeyRemaining}',
                      style: theme.textTheme.labelSmall,
                    ),
                ],
              ),
              const SizedBox(height: FotgSpacing.x4),
              _RouteEndpoints(trip: trip, progress: progress),
              if (trip.nextPickupLabel != null) ...<Widget>[
                const SizedBox(height: FotgSpacing.x4),
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.storefront_outlined,
                      size: FotgSizing.iconSm,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: FotgSpacing.x2),
                    Text(
                      '${strings.journeyNextPickup}: ',
                      style: theme.textTheme.labelSmall,
                    ),
                    Expanded(
                      child: Text(
                        trip.nextPickupLabel!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: FotgSpacing.x2),
              Row(
                children: <Widget>[
                  if (trip.totalDistanceKm != null)
                    Text(
                      '${trip.totalDistanceKm!.toStringAsFixed(0)} km',
                      style: theme.textTheme.labelSmall,
                    ),
                  const Spacer(),
                  if (onTap != null)
                    LinkAction(
                      label: strings.journeyViewCta,
                      icon: Icons.arrow_forward_rounded,
                      onPressed: onTap,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RouteEndpoints extends StatelessWidget {
  const _RouteEndpoints({required this.trip, this.progress});

  final ActiveTripSummary trip;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Semantics(
      label: progress == null
          ? '${trip.originLabel} to ${trip.destinationLabel}'
          : '${trip.originLabel} to ${trip.destinationLabel}, '
                '${(progress! * 100).round()} percent of the way',
      excludeSemantics: true,
      child: Column(
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: _Endpoint(
                  label: trip.originLabel,
                  icon: Icons.trip_origin_rounded,
                  colour: theme.colorScheme.secondary,
                  alignment: CrossAxisAlignment.start,
                ),
              ),
              const SizedBox(width: FotgSpacing.x3),
              Icon(
                Icons.arrow_forward_rounded,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: FotgSpacing.x3),
              Expanded(
                child: _Endpoint(
                  label: trip.destinationLabel,
                  icon: Icons.place_rounded,
                  colour: theme.colorScheme.primary,
                  alignment: CrossAxisAlignment.end,
                ),
              ),
            ],
          ),
          if (progress != null) ...<Widget>[
            const SizedBox(height: FotgSpacing.x3),
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: progress),
              duration: FotgMotion.respectingReducedMotion(
                context,
                FotgMotion.slow,
              ),
              curve: FotgMotion.decelerate,
              builder: (BuildContext context, double value, _) => ClipRRect(
                borderRadius: FotgRadius.pill,
                child: LinearProgressIndicator(
                  value: value,
                  minHeight: 6,
                  backgroundColor: theme.colorScheme.outline,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    theme.colorScheme.secondary,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Endpoint extends StatelessWidget {
  const _Endpoint({
    required this.label,
    required this.icon,
    required this.colour,
    required this.alignment,
  });

  final String label;
  final IconData icon;
  final Color colour;
  final CrossAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isEnd = alignment == CrossAxisAlignment.end;

    return Column(
      crossAxisAlignment: alignment,
      children: <Widget>[
        Icon(icon, size: FotgSizing.iconSm, color: colour),
        const SizedBox(height: FotgSpacing.x1),
        Text(
          label,
          style: theme.textTheme.titleMedium,
          textAlign: isEnd ? TextAlign.right : TextAlign.left,
          // Two lines: "Indira Gandhi International Airport, New Delhi" must
          // stay readable rather than collapsing to "Indira Gand…".
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
