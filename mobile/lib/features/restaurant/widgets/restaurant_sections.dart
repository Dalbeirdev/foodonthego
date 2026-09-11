import 'package:flutter/material.dart';

import '../../../core/format/journey_measures.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/models/discovered_restaurant.dart';
import '../../../domain/models/restaurant_detail.dart';

/// The parts of a restaurant page below the photographs.
///
/// One file rather than eight, because each of these is thirty lines and
/// splitting them would be filing rather than design. They share a section
/// heading and nothing else.

/// A titled block, or nothing at all.
///
/// Returning `SizedBox.shrink()` for empty content is the whole point: a
/// restaurant that declared no facilities gets no facilities section, not an
/// empty card with a heading over blank space. An empty card reads as a bug.
class RestaurantSection extends StatelessWidget {
  const RestaurantSection({
    required this.title,
    required this.child,
    this.trailing,
    super.key,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FotgSpacing.x4,
        FotgSpacing.x5,
        FotgSpacing.x4,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: FotgSpacing.x2),
          child,
        ],
      ),
    );
  }
}

/// Name, cuisines, price, rating — the four facts under the photographs.
class RestaurantDetailHeader extends StatelessWidget {
  const RestaurantDetailHeader({required this.detail, super.key});

  final RestaurantDetail detail;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final ThemeData theme = Theme.of(context);
    final DiscoveredRestaurant r = detail.restaurant;

    final List<String> facts = <String>[
      ...r.cuisines,
      if (r.priceLevel != null) '₹' * r.priceLevel!,
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FotgSpacing.x4,
        FotgSpacing.x4,
        FotgSpacing.x4,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            r.name,
            // No maxLines: a long name wraps rather than being cut off, and a
            // restaurant's own name is the last thing to truncate.
            style: theme.textTheme.headlineSmall,
          ),

          if (facts.isNotEmpty) ...<Widget>[
            const SizedBox(height: FotgSpacing.x1),
            Semantics(
              // The rupee symbols are a visual convention a screen reader
              // cannot convey; the word can.
              label: <String>[
                ...r.cuisines,
                if (r.priceLevel != null)
                  strings.priceLevelLabel(r.priceLevel!),
              ].join(', '),
              excludeSemantics: true,
              child: Text(
                facts.join(' · '),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],

          const SizedBox(height: FotgSpacing.x2),
          _RatingSummary(rating: r.rating, reviewCount: r.reviewCount),
        ],
      ),
    );
  }
}

/// A rating, or the honest absence of one.
class _RatingSummary extends StatelessWidget {
  const _RatingSummary({this.rating, this.reviewCount});

  final double? rating;
  final int? reviewCount;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final ThemeData theme = Theme.of(context);

    final double? value = rating;

    // No reviews module, so no rating. "New" rather than 0.0, which a customer
    // reads as "everybody hated it" — and rather than a hopeful 4.5, which is
    // a claim somebody would act on.
    if (value == null) {
      return Chip(
        label: Text(strings.discoveryNoRating),
        visualDensity: VisualDensity.compact,
      );
    }

    final int? count = reviewCount;

    return Semantics(
      label: count == null
          ? '$value out of 5'
          : '$value out of 5, from $count reviews',
      excludeSemantics: true,
      child: Row(
        children: <Widget>[
          Icon(Icons.star_rounded, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: FotgSpacing.x1),
          Text(value.toStringAsFixed(1), style: theme.textTheme.titleSmall),
          if (count != null) ...<Widget>[
            const SizedBox(width: FotgSpacing.x1),
            Text(
              '($count)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Why this restaurant is worth stopping at *on this journey*.
///
/// The card that makes this screen FoodOnTheGo's rather than a generic
/// restaurant page. Distance ahead and detour, in that order, because that is
/// the order a driver decides in: how far until I get there, and what does
/// pulling off cost me.
class RestaurantRouteSummary extends StatelessWidget {
  const RestaurantRouteSummary({required this.route, super.key});

  final RouteRelation route;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final ThemeData theme = Theme.of(context);

    final List<(IconData, String)> facts = <(IconData, String)>[
      if (route.requiresBacktracking)
        (Icons.u_turn_left_rounded, strings.discoveryBacktrack)
      else
        (
          Icons.straighten_rounded,
          strings.discoveryDistanceAhead(
            JourneyMeasures.distance(route.distanceAheadMetres),
          ),
        ),
      if (route.timeAheadSeconds != null && !route.requiresBacktracking)
        (
          Icons.schedule_rounded,
          strings.discoveryTimeAhead(
            JourneyMeasures.duration(route.timeAheadSeconds!),
          ),
        ),
      if (route.detourDurationSeconds != null)
        (
          Icons.alt_route_rounded,
          strings.discoveryDetour(
            JourneyMeasures.duration(route.detourDurationSeconds!),
          ),
        )
      else
        (Icons.alt_route_rounded, strings.discoveryDetourUnknown),
      (
        Icons.near_me_rounded,
        strings.discoveryOffRoute(
          JourneyMeasures.distance(route.proximityMetres),
        ),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FotgSpacing.x4,
        FotgSpacing.x4,
        FotgSpacing.x4,
        0,
      ),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(FotgSpacing.x4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Semantics(
                header: true,
                child: Text(
                  strings.restaurantOnYourRoute,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              const SizedBox(height: FotgSpacing.x3),
              for (final (IconData icon, String label) in facts)
                Padding(
                  padding: const EdgeInsets.only(bottom: FotgSpacing.x2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        icon,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: FotgSpacing.x3),
                      // Flexible, not Expanded-with-ellipsis: at 320 dp with
                      // large text these wrap, and a truncated "4 min det…" is
                      // worse than two lines.
                      Flexible(
                        child: Text(label, style: theme.textTheme.bodyMedium),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The facilities an operator has declared. Never inferred from anything.
class RestaurantFacilitiesGrid extends StatelessWidget {
  const RestaurantFacilitiesGrid({required this.facilities, super.key});

  final List<String> facilities;

  /// The icon this app has for a known facility, or a neutral tick.
  ///
  /// A tick is honest: it says "the operator declared this" without pretending
  /// to know what it looks like. Guessing an icon for an unfamiliar facility
  /// would put a wheelchair beside "Wi-Fi" the first time somebody adds one.
  static IconData iconFor(String facility) => switch (facility
      .toLowerCase()
      .replaceAll(RegExp('[^a-z]+'), '_')) {
    'parking' => Icons.local_parking_rounded,
    'restroom' || 'toilets' => Icons.wc_rounded,
    'seating' || 'indoor_seating' => Icons.chair_rounded,
    'wheelchair_accessible' || 'accessible' => Icons.accessible_forward_rounded,
    'takeaway' => Icons.takeout_dining_rounded,
    'ev_charging' || 'electric_vehicle_charging' => Icons.ev_station_rounded,
    'wi_fi' || 'wifi' => Icons.wifi_rounded,
    _ => Icons.check_circle_outline_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Wrap(
      spacing: FotgSpacing.x2,
      runSpacing: FotgSpacing.x2,
      children: <Widget>[
        for (final String facility in facilities)
          Chip(
            avatar: Icon(
              iconFor(facility),
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            // The label is the accessible name. An icon on its own would be a
            // picture nobody using a screen reader can read.
            label: Text(facility),
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }
}

/// Today's hours, and the rest of the week on request.
class RestaurantHoursSection extends StatelessWidget {
  const RestaurantHoursSection({
    required this.hours,
    required this.expanded,
    required this.onToggle,
    super.key,
  });

  final RestaurantHours hours;
  final bool expanded;
  final VoidCallback onToggle;

  /// "8:00 AM – 10:00 PM" from two `HH:mm:ss` strings.
  ///
  /// Formatted here rather than by the server: what a time looks like is a
  /// locale decision, and the server does not know the customer's.
  static String window(BuildContext context, OpeningWindow w) {
    final MaterialLocalizations l10n = MaterialLocalizations.of(context);

    String format(String time) {
      final List<String> parts = time.split(':');

      return l10n.formatTimeOfDay(
        TimeOfDay(
          hour: int.tryParse(parts.first) ?? 0,
          minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
        ),
        alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
      );
    }

    return '${format(w.opensAt)} – ${format(w.closesAt)}';
  }

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final ThemeData theme = Theme.of(context);

    if (!hours.hasSchedule) {
      return Text(
        strings.restaurantAvailabilityUnknown,
        style: theme.textTheme.bodyMedium,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Today first and always. A customer wants to know about now; the week
        // is a follow-up question.
        _DayRow(
          label: strings.restaurantHoursToday,
          windows: hours.today,
          emphasised: true,
        ),

        if (expanded) ...<Widget>[
          const Divider(height: FotgSpacing.x5),
          for (final DayHours day in hours.week)
            _DayRow(
              label: strings.weekdayName(day.dayOfWeek),
              windows: day.windows,
              emphasised: day.isToday,
            ),
          if (hours.timezone.isNotEmpty) ...<Widget>[
            const SizedBox(height: FotgSpacing.x2),
            Text(
              strings.restaurantHoursTimezone(hours.timezone),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],

        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: onToggle,
            child: Text(
              expanded
                  ? strings.restaurantHoursHide
                  : strings.restaurantHoursShowAll,
            ),
          ),
        ),
      ],
    );
  }
}

/// One day, and the windows it is open.
class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.label,
    required this.windows,
    this.emphasised = false,
  });

  final String label;
  final List<OpeningWindow> windows;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final ThemeData theme = Theme.of(context);

    final TextStyle? style = emphasised
        ? theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)
        : theme.textTheme.bodyMedium;

    // A day with no windows says "Closed". A missing row is a question; a row
    // that says Closed is an answer.
    final List<String> text = windows.isEmpty
        ? <String>[strings.restaurantHoursClosedDay]
        : windows
              .map(
                (OpeningWindow w) => w.isOvernight
                    // Said out loud, because "18:00 – 02:00" read quickly
                    // looks like a typo.
                    ? strings.restaurantHoursOvernight(
                        RestaurantHoursSection.window(context, w),
                      )
                    : RestaurantHoursSection.window(context, w),
              )
              .toList(growable: false);

    return Padding(
      padding: const EdgeInsets.only(bottom: FotgSpacing.x2),
      child: Semantics(
        // Its own node, not merged into the section around it. Without
        // `container` every day of the week collapses into one enormous label
        // and a screen-reader user cannot step through the schedule a day at
        // a time.
        container: true,
        label: '$label, ${text.join(', ')}',
        excludeSemantics: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(width: 108, child: Text(label, style: style)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (final String line in text) Text(line, style: style),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
