import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/time/journey_time.dart';
import '../../../domain/models/trip.dart';
import '../../../shared/widgets/fotg_card.dart';

/// The customer's next journey, on the home screen.
///
/// Deliberately not the Module 02 `RouteSummaryCard`: that one renders an
/// `ActiveTripSummary` with progress, remaining time and a next pickup, none of
/// which exists yet. Showing a progress bar at zero would imply the app is
/// tracking a journey it cannot see.
///
/// This card shows only what is real: where, when, and how many people.
class NextJourneyCard extends StatelessWidget {
  const NextJourneyCard({required this.trip, required this.onTap, super.key});

  final Trip trip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final ThemeData theme = Theme.of(context);

    // FotgCard is not tappable, so the gesture goes around it rather than
    // inside — an InkWell in the card would clip its ripple to the padding.
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(FotgRadius.lg),
      child: FotgCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(FotgRadius.md),
                  ),
                  child: Icon(
                    Icons.route_rounded,
                    size: 20,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: FotgSpacing.x4),
                Expanded(
                  child: Text(
                    trip.routeSummary,
                    style: theme.textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: FotgSpacing.x4),
            _Line(
              icon: Icons.schedule_rounded,
              label: strings.tripDeparts,
              value: JourneyTime.full(trip.departureAt),
            ),
            // Rendered only when the traveller stated one. A row reading "Arrives:
            // not set" on the home screen is a blank the customer has to interpret.
            if (trip.expectedArrivalAt != null) ...<Widget>[
              const SizedBox(height: FotgSpacing.x2),
              _Line(
                icon: Icons.flag_rounded,
                label: strings.tripArrives,
                value: JourneyTime.full(trip.expectedArrivalAt!),
              ),
            ],
            if (trip.travellerCount > 1) ...<Widget>[
              const SizedBox(height: FotgSpacing.x2),
              _Line(
                icon: Icons.group_rounded,
                label: strings.tripFormTravellers,
                value: strings.tripTravellers(trip.travellerCount),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Row(
      children: <Widget>[
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: FotgSpacing.x2),
        Text(
          '$label: ',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodyMedium,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
