import 'package:flutter/material.dart';

import '../../../core/format/journey_measures.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/models/discovery_facets.dart';
import '../../../domain/models/discovery_query.dart';

/// What the customer has narrowed the list to, as removable chips.
///
/// The point of the row is that a filter is never invisible. A screen showing
/// two restaurants because a facility filter is on, with nothing on screen
/// saying so, is a screen that looks like a road with two restaurants on it.
///
/// Each chip removes exactly its own value — not the group it belongs to.
/// Removing "North Indian" from "North Indian, Cafe" leaves "Cafe", because
/// wiping the group would undo a choice the customer did not ask to undo.
class ActiveFilterChips extends StatelessWidget {
  const ActiveFilterChips({
    required this.query,
    required this.facets,
    required this.onRemoveCuisine,
    required this.onRemoveFacility,
    required this.onRemovePriceLevel,
    required this.onRemoveAvailability,
    required this.onRemoveMaxDetour,
    required this.onRemoveMaxDistanceAhead,
    required this.onRemoveMinRating,
    required this.onClearAll,
    super.key,
  });

  final DiscoveryQuery query;

  /// Used only to turn a slug back into the label the customer chose. A slug
  /// the facets no longer carry still gets a chip — it is still filtering the
  /// list — with the slug itself made readable rather than shown raw.
  final DiscoveryFacets facets;

  final ValueChanged<String> onRemoveCuisine;
  final ValueChanged<String> onRemoveFacility;
  final ValueChanged<int> onRemovePriceLevel;
  final VoidCallback onRemoveAvailability;
  final VoidCallback onRemoveMaxDetour;
  final VoidCallback onRemoveMaxDistanceAhead;
  final VoidCallback onRemoveMinRating;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    if (!query.hasFilters) return const SizedBox.shrink();

    final AppStrings strings = AppStrings.of(context);

    final List<Widget> chips = <Widget>[
      if (query.availability != null)
        _chip(
          strings,
          _availabilityLabel(strings, query.availability!),
          onRemoveAvailability,
        ),
      for (final String slug in _sorted(query.cuisines))
        _chip(
          strings,
          _labelFor(facets.cuisines, slug),
          () => onRemoveCuisine(slug),
        ),
      for (final String slug in _sorted(query.facilities))
        _chip(
          strings,
          _labelFor(facets.facilities, slug),
          () => onRemoveFacility(slug),
        ),
      for (final int level in _sortedInts(query.priceLevels))
        _chip(
          strings,
          '${'₹' * level} · ${strings.priceLevelLabel(level)}',
          () => onRemovePriceLevel(level),
        ),
      if (query.maxDetourSeconds != null)
        _chip(
          strings,
          strings.discoveryDetourUnder(
            JourneyMeasures.duration(query.maxDetourSeconds!),
          ),
          onRemoveMaxDetour,
        ),
      if (query.maxDistanceAheadMetres != null)
        _chip(
          strings,
          strings.discoveryDistanceAhead(
            JourneyMeasures.distance(query.maxDistanceAheadMetres!),
          ),
          onRemoveMaxDistanceAhead,
        ),
      if (query.minRating != null)
        _chip(strings, '${query.minRating}+', onRemoveMinRating),
    ];

    return SizedBox(
      height: 44,
      child: Row(
        children: <Widget>[
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: FotgSpacing.x4),
              children: <Widget>[
                for (final Widget chip in chips) ...<Widget>[
                  chip,
                  const SizedBox(width: FotgSpacing.x2),
                ],
              ],
            ),
          ),

          // Pinned outside the scrolling row rather than at the end of it.
          // Three filters already push it off the side of a 390dp phone, and
          // the customer who most needs it is the one whose filters left them
          // with an empty screen — they must not have to discover a sideways
          // scroll to get out of it.
          if (chips.length > 1)
            Padding(
              padding: const EdgeInsets.only(right: FotgSpacing.x2),
              child: TextButton(
                onPressed: onClearAll,
                child: Text(strings.discoveryFiltersClear),
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip(AppStrings strings, String label, VoidCallback onRemove) =>
      InputChip(
        label: Text(label),
        onDeleted: onRemove,
        deleteIcon: const Icon(Icons.close_rounded, size: 16),
        // The delete button's own accessible name. Without it a screen reader
        // announces an unlabelled button beside every chip.
        deleteButtonTooltipMessage: strings.discoveryFiltersClearOne,
      );

  static String _availabilityLabel(
    AppStrings strings,
    AvailabilityFilter filter,
  ) => switch (filter) {
    AvailabilityFilter.openNow => strings.discoveryFilterOpenNow,
    AvailabilityFilter.acceptingOrders =>
      strings.discoveryFilterAcceptingOrders,
  };

  /// The label the customer saw when they chose it, or the slug made readable.
  static String _labelFor(List<FilterOption> options, String slug) {
    for (final FilterOption option in options) {
      if (option.slug == slug) return option.label;
    }

    return slug
        .split('_')
        .where((String part) => part.isNotEmpty)
        .map((String part) => part[0].toUpperCase() + part.substring(1))
        .join(' ');
  }

  static List<String> _sorted(Set<String> values) => values.toList()..sort();

  static List<int> _sortedInts(Set<int> values) => values.toList()..sort();
}
