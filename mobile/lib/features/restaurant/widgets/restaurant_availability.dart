import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/models/restaurant_detail.dart';

/// Whether a customer can order, said plainly.
///
/// The single most consequential sentence on this screen. A traveller reading
/// "Open · Accepting orders" may drive forty kilometres on the strength of it,
/// so every state below is derived from the server's normalised answer rather
/// than reconstructed here from opening hours and a boolean.
class RestaurantAvailabilityBadge extends StatelessWidget {
  const RestaurantAvailabilityBadge({required this.state, super.key});

  final RestaurantOrderingState state;

  static String labelFor(AppStrings strings, RestaurantOrderingState state) =>
      switch (state) {
        RestaurantOrderingState.openAccepting =>
          strings.restaurantOpenAccepting,
        RestaurantOrderingState.openPaused => strings.restaurantOpenPaused,
        RestaurantOrderingState.closed => strings.restaurantClosedNow,
        RestaurantOrderingState.closedPermanently =>
          strings.restaurantClosedPermanently,
        RestaurantOrderingState.unavailable =>
          strings.restaurantAvailabilityUnknown,
      };

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;

    final (Color background, Color foreground, IconData icon) = switch (state) {
      RestaurantOrderingState.openAccepting => (
        dark
            ? FotgColors.success.withValues(alpha: 0.22)
            : FotgColors.successSurface,
        dark ? FotgColors.darkSuccess : FotgColors.success,
        Icons.check_circle_rounded,
      ),
      RestaurantOrderingState.openPaused => (
        dark
            ? FotgColors.warning.withValues(alpha: 0.22)
            : FotgColors.warningSurface,
        dark ? FotgColors.darkWarning : FotgColors.warning,
        Icons.pause_circle_rounded,
      ),
      RestaurantOrderingState.closed ||
      RestaurantOrderingState.closedPermanently ||
      RestaurantOrderingState.unavailable => (
        theme.colorScheme.surfaceContainerHighest,
        theme.colorScheme.onSurfaceVariant,
        Icons.schedule_rounded,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FotgSpacing.x3,
        vertical: FotgSpacing.x2,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: const BorderRadius.all(Radius.circular(FotgRadius.md)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // An icon *and* a word. Colour alone cannot carry this: a customer
          // who cannot distinguish the green from the amber would be reading
          // "open" off a chip that says paused.
          Icon(icon, size: 16, color: foreground),
          const SizedBox(width: FotgSpacing.x2),
          Flexible(
            child: Text(
              labelFor(strings, state),
              style: theme.textTheme.labelLarge?.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

/// The banner over a restaurant that cannot take an order right now.
///
/// A chip alone is too quiet for this. A customer who has scrolled to the menu
/// button without noticing a small amber pill has been failed by the screen,
/// so the states that block ordering get a full-width band as well.
class RestaurantUnavailableBanner extends StatelessWidget {
  const RestaurantUnavailableBanner({
    required this.state,
    this.nextOpenAt,
    super.key,
  });

  final RestaurantOrderingState state;
  final DateTime? nextOpenAt;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final ThemeData theme = Theme.of(context);

    if (state == RestaurantOrderingState.openAccepting) {
      return const SizedBox.shrink();
    }

    final (String title, String? body) = switch (state) {
      RestaurantOrderingState.openPaused => (
        strings.restaurantPausedBannerTitle,
        strings.restaurantPausedBannerBody,
      ),
      RestaurantOrderingState.closed => (
        strings.restaurantClosedBannerTitle,
        // Only when the server could work it out. "Opens at" is not something
        // to guess at, and silence is better than a time nobody computed.
        nextOpenAt == null
            ? null
            : strings.restaurantOpensAt(_when(context, nextOpenAt!)),
      ),
      RestaurantOrderingState.closedPermanently => (
        strings.restaurantGoneBannerTitle,
        strings.restaurantGoneBannerBody,
      ),
      _ => (strings.restaurantAvailabilityUnknown, null),
    };

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
        FotgSpacing.x4,
        FotgSpacing.x4,
        FotgSpacing.x4,
        0,
      ),
      padding: const EdgeInsets.all(FotgSpacing.x3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.all(Radius.circular(FotgRadius.lg)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: FotgSpacing.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: theme.textTheme.titleSmall),
                if (body != null) ...<Widget>[
                  const SizedBox(height: FotgSpacing.x1),
                  Text(body, style: theme.textTheme.bodySmall),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// "at 8:00 AM", or "tomorrow at 8:00 AM", or a weekday.
  ///
  /// A bare time is ambiguous the moment it is not today, and "opens at 8:00"
  /// on a Monday evening for a restaurant that opens on Friday is a lie by
  /// omission.
  static String _when(BuildContext context, DateTime when) {
    final MaterialLocalizations l10n = MaterialLocalizations.of(context);
    final AppStrings strings = AppStrings.of(context);

    final String time = l10n.formatTimeOfDay(
      TimeOfDay.fromDateTime(when),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );

    final DateTime now = DateTime.now();
    final int days = DateTime(
      when.year,
      when.month,
      when.day,
    ).difference(DateTime(now.year, now.month, now.day)).inDays;

    return switch (days) {
      0 => 'at $time',
      1 => 'tomorrow at $time',
      _ => '${strings.weekdayName(when.weekday - 1)} at $time',
    };
  }
}

/// The button at the bottom of the screen.
///
/// Its state is the ordering state and nothing else. A live button on a kitchen
/// that has stopped cooking is the one mistake on this screen a customer pays
/// for in kilometres.
class RestaurantPrimaryCta extends StatelessWidget {
  const RestaurantPrimaryCta({
    required this.state,
    required this.onPressed,
    super.key,
  });

  final RestaurantOrderingState state;

  /// Null disables the button. Module 10 owns where it goes.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);

    final (String label, bool enabled) = switch (state) {
      RestaurantOrderingState.openAccepting => (
        strings.restaurantViewMenu,
        true,
      ),
      // Shut or paused: the menu is still worth reading, because the traveller
      // is two hours away and the pause may lift before they arrive. The
      // wording changes so nobody thinks they are placing an order.
      RestaurantOrderingState.openPaused => (
        strings.restaurantBrowseMenuWhileClosed,
        true,
      ),
      RestaurantOrderingState.closed => (
        strings.restaurantBrowseMenuWhileClosed,
        true,
      ),
      // Closed for good, or unknown. The menu describes something that may no
      // longer exist, so there is nothing to open.
      RestaurantOrderingState.closedPermanently => (
        strings.restaurantMenuUnavailableGone,
        false,
      ),
      RestaurantOrderingState.unavailable => (
        strings.restaurantMenuUnavailableGone,
        false,
      ),
    };

    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: enabled ? onPressed : null,
        child: Text(label),
      ),
    );
  }
}
