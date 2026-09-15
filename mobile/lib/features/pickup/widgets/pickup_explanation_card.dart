import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/models/pickup.dart';
import '../../../shared/widgets/fotg_card.dart';

/// Why the times are what they are.
///
/// Travel, cooking, bagging up — the three durations the server used, shown so
/// a customer can see where a pickup time came from rather than taking it on
/// trust. The first time one looks wrong is the moment they stop believing all
/// of them, and an unexplained list gives them nothing to check it against.
///
/// **Nothing here is calculated.** Every minute count and every instant arrived
/// in the response; this widget formats and lays them out. It does not add the
/// durations together, and does not derive the ready time from them — the
/// server sent that too, and a second sum on the client is a second answer.
///
/// The note at the bottom is not decoration either. The platform has an
/// estimate of a drive and an estimate of a kitchen, and saying "ready at 3:30"
/// without hedging would be a promise neither of them can keep.
class PickupExplanationCard extends StatelessWidget {
  const PickupExplanationCard({
    required this.plan,
    required this.formatTime,
    super.key,
  });

  final PickupPlan plan;

  /// Formats a server instant in the restaurant's zone. Passed in so the screen
  /// owns the one place formatting happens.
  final String Function(DateTime) formatTime;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final ThemeData theme = Theme.of(context);

    final List<(IconData, String)> rows = <(IconData, String)>[
      if (plan.travelMinutes case final int minutes)
        (Icons.directions_car_outlined, strings.pickupTravelMinutes(minutes)),
      if (plan.localEstimatedArrivalAt case final DateTime arrival)
        (
          Icons.place_outlined,
          strings.pickupArrivalEstimate(formatTime(arrival)),
        ),
      if (plan.preparationMinutes case final int minutes)
        (
          Icons.local_fire_department_outlined,
          strings.pickupPreparationMinutes(minutes),
        ),
      if (plan.bufferMinutes case final int minutes when minutes > 0)
        (Icons.shopping_bag_outlined, strings.pickupBufferMinutes(minutes)),
      if (plan.localEarliestReadyAt case final DateTime ready)
        (
          Icons.schedule_outlined,
          strings.pickupEarliestReady(formatTime(ready)),
        ),
    ];

    return FotgCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            strings.pickupExplanationTitle,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: FotgSpacing.x3),
          for (final (IconData icon, String line) in rows) ...<Widget>[
            Padding(
              padding: const EdgeInsets.only(bottom: FotgSpacing.x2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(icon, size: 18, color: FotgColors.neutral500),
                  const SizedBox(width: FotgSpacing.x3),
                  Expanded(
                    child: Text(line, style: theme.textTheme.bodyMedium),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: FotgSpacing.x1),
          Text(
            strings.pickupEstimateNote,
            style: theme.textTheme.bodySmall?.copyWith(
              color: FotgColors.neutral500,
            ),
          ),
          if (plan.timezone case final String zone) ...<Widget>[
            const SizedBox(height: FotgSpacing.x2),
            Text(
              strings.pickupTimezoneNote(zone),
              style: theme.textTheme.bodySmall?.copyWith(
                color: FotgColors.neutral500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
