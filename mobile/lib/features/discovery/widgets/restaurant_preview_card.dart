import 'package:flutter/material.dart';

import '../../../core/format/journey_measures.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/models/discovered_restaurant.dart';
import 'availability_chip.dart';

/// One stop a traveller could make.
///
/// The information hierarchy is deliberate and is the product's argument in
/// miniature: **how far ahead** and **what the stop costs** come before the
/// name's supporting detail, because those are the two facts that decide whether
/// somebody stops here rather than at the next one.
///
/// Everything is conditional. A restaurant with no rating shows no rating, one
/// with no declared price shows no price, and one whose detour could not be
/// established shows no detour badge — not a zero, and not a guess.
class RestaurantPreviewCard extends StatelessWidget {
  const RestaurantPreviewCard({
    required this.restaurant,
    required this.isSelected,
    required this.onSelect,
    this.onView,
    super.key,
  });

  final DiscoveredRestaurant restaurant;
  final bool isSelected;
  final VoidCallback onSelect;

  /// The full restaurant page belongs to a later module, so this may be null and
  /// the action is simply absent rather than present and inert.
  final VoidCallback? onView;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppStrings strings = AppStrings.of(context);

    // "Behind you" rather than "0 m ahead" for a stop that needs backtracking.
    // One string, used by both the visible chip and the semantics label: the
    // first version of this card computed them separately, and a screen reader
    // was told "0 m ahead" about the very restaurant the screen labelled
    // "Behind you".
    final String ahead = restaurant.route.requiresBacktracking
        ? strings.discoveryBacktrack
        : strings.discoveryDistanceAhead(
            JourneyMeasures.distance(restaurant.route.distanceAheadMetres),
          );

    final String? detour = restaurant.route.detourDurationSeconds == null
        ? null
        : strings.discoveryDetour(
            JourneyMeasures.duration(restaurant.route.detourDurationSeconds!),
          );

    return Semantics(
      button: true,
      selected: isSelected,
      // One sentence a screen reader can read straight through, in the order a
      // sighted customer scans the card.
      label: strings.discoveryRestaurantSemantics(
        name: restaurant.displayName,
        // Cuisine and price, and price as a *word*. The rupee symbols are a
        // visual convention: a screen reader announces "₹₹" as nothing useful,
        // and a font without the glyph draws two empty boxes.
        cuisines: <String>[
          if (restaurant.cuisines.isNotEmpty) restaurant.cuisines.join(', '),
          if (restaurant.priceLevel != null)
            strings.priceLevelLabel(restaurant.priceLevel!),
        ].join(', '),
        availability: AvailabilityChip.labelFor(
          restaurant.availability,
          strings,
        ),
        ahead: ahead,
        detour: detour,
        offRoute: strings.discoveryOffRoute(
          JourneyMeasures.distance(restaurant.route.proximityMetres),
        ),
      ),
      onTap: onSelect,
      excludeSemantics: true,
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: FotgSpacing.x1),
        elevation: isSelected ? 3 : 0,
        color: isSelected
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FotgRadius.lg),
          side: BorderSide(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: onSelect,
          borderRadius: BorderRadius.circular(FotgRadius.lg),
          child: Padding(
            padding: const EdgeInsets.all(FotgSpacing.x4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        restaurant.displayName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: FotgSpacing.x2),
                    AvailabilityChip(availability: restaurant.availability),
                  ],
                ),

                if (_supporting(strings).isNotEmpty) ...<Widget>[
                  const SizedBox(height: FotgSpacing.x1),
                  Text(
                    _supporting(strings),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],

                const SizedBox(height: FotgSpacing.x3),

                // The two figures the decision turns on. A `Wrap`, because at
                // 320dp with a long duration these do not fit on one line and a
                // `Row` would overflow rather than reflow.
                Wrap(
                  spacing: FotgSpacing.x2,
                  runSpacing: FotgSpacing.x2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    _Fact(
                      icon: Icons.straighten_rounded,
                      label: ahead,
                      emphasised: true,
                    ),
                    if (detour != null)
                      _Fact(icon: Icons.alt_route_rounded, label: detour)
                    else
                      // Said plainly rather than left blank, so the absence
                      // reads as "we could not work it out" rather than as a
                      // missing part of the card.
                      _Fact(
                        icon: Icons.help_outline_rounded,
                        label: strings.discoveryDetourUnknown,
                      ),
                    _Fact(
                      icon: Icons.near_me_outlined,
                      label: strings.discoveryOffRoute(
                        JourneyMeasures.distance(
                          restaurant.route.proximityMetres,
                        ),
                      ),
                    ),
                  ],
                ),

                if (restaurant.facilities.isNotEmpty) ...<Widget>[
                  const SizedBox(height: FotgSpacing.x2),
                  Text(
                    restaurant.facilities.take(3).join(' · '),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],

                if (onView != null) ...<Widget>[
                  const SizedBox(height: FotgSpacing.x2),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: onView,
                      child: Text(strings.discoveryViewRestaurant),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Cuisine, price and rating, joined — and each one present only if it is
  /// real. There is no reviews module, so `rating` is null on every genuine row
  /// and this line simply has one part fewer.
  String _supporting(AppStrings strings) {
    final List<String> parts = <String>[
      if (restaurant.cuisines.isNotEmpty)
        restaurant.cuisines.take(2).join(', '),
      if (restaurant.priceLevel != null)
        '₹' * restaurant.priceLevel!.clamp(1, 4),
      // The word is in the semantics label above; this list is the visible one.
      if (restaurant.hasRating)
        '${restaurant.rating!.toStringAsFixed(1)} ★'
            '${restaurant.reviewCount == null ? '' : ' (${restaurant.reviewCount})'}',
    ];

    return parts.join(' · ');
  }
}

/// One route fact: an icon, and words that say the same thing.
class _Fact extends StatelessWidget {
  const _Fact({
    required this.icon,
    required this.label,
    this.emphasised = false,
  });

  final IconData icon;
  final String label;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    final TextStyle? style = emphasised
        ? theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)
        : theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(
          icon,
          size: 16,
          color: emphasised
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        // Flexible, and wrapping rather than ellipsising. On a 320dp screen a
        // single fact — "1.8 km off your route" — is wider than the card, and
        // measured 69 pixels past its edge before this. The `Wrap` above puts
        // facts on separate lines when they will not sit side by side; this
        // does the same job within one fact.
        Flexible(child: Text(label, style: style)),
      ],
    );
  }
}
