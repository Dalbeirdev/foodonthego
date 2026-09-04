import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/models/discovered_restaurant.dart';

/// Whether a traveller can stop here, said in words.
///
/// Colour carries the same message a second time and never the only time: the
/// chip always contains its own label, so a customer who cannot distinguish
/// green from amber reads "Not accepting orders" rather than inferring it.
class AvailabilityChip extends StatelessWidget {
  const AvailabilityChip({required this.availability, super.key});

  final RestaurantAvailability availability;

  static String labelFor(RestaurantAvailability a, AppStrings strings) =>
      switch (a) {
        RestaurantAvailability.open => strings.discoveryAvailabilityOpen,
        RestaurantAvailability.closingSoon =>
          strings.discoveryAvailabilityClosingSoon,
        RestaurantAvailability.openingSoon =>
          strings.discoveryAvailabilityOpeningSoon,
        RestaurantAvailability.closed => strings.discoveryAvailabilityClosed,
        RestaurantAvailability.notAcceptingOrders =>
          strings.discoveryAvailabilityPaused,
        RestaurantAvailability.unknown => strings.discoveryAvailabilityUnknown,
      };

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppStrings strings = AppStrings.of(context);

    final (Color background, Color foreground) = switch (availability) {
      RestaurantAvailability.open || RestaurantAvailability.closingSoon => (
        theme.colorScheme.secondaryContainer,
        theme.colorScheme.onSecondaryContainer,
      ),
      // Amber-ish rather than green: open by the clock, and not a stop the
      // customer can act on.
      RestaurantAvailability.notAcceptingOrders ||
      RestaurantAvailability.openingSoon => (
        theme.colorScheme.tertiaryContainer,
        theme.colorScheme.onTertiaryContainer,
      ),
      RestaurantAvailability.closed || RestaurantAvailability.unknown => (
        theme.colorScheme.surfaceContainerHighest,
        theme.colorScheme.onSurfaceVariant,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FotgSpacing.x2,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(FotgRadius.full),
      ),
      child: Text(
        labelFor(availability, strings),
        style: theme.textTheme.labelSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
