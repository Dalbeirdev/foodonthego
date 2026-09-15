import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/models/discovery_facets.dart';
import '../../../domain/models/discovery_query.dart';

/// The order the stops are listed in.
///
/// A sheet rather than a dropdown: five options, each needing a line of its
/// own, and one of them needing a sentence explaining why it cannot be picked.
///
/// The list comes from the server's facets rather than from [DiscoverySort] —
/// the server decides which orders its data can support, and a client that
/// offered "highest rated" while nothing has a rating would be offering a sort
/// whose only possible outcome is a list in arbitrary order.
class DiscoverySortSheet extends StatelessWidget {
  const DiscoverySortSheet({
    required this.facets,
    required this.selected,
    super.key,
  });

  final DiscoveryFacets facets;
  final DiscoverySort selected;

  /// Returns the chosen sort, or null if the sheet was dismissed.
  static Future<DiscoverySort?> show(
    BuildContext context, {
    required DiscoveryFacets facets,
    required DiscoverySort selected,
  }) => showModalBottomSheet<DiscoverySort>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext context) =>
        DiscoverySortSheet(facets: facets, selected: selected),
  );

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final ThemeData theme = Theme.of(context);

    final List<SortOption> options = facets.sorts.isEmpty
        ? _fallback(strings)
        : facets.sorts;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              FotgSpacing.x4,
              0,
              FotgSpacing.x4,
              FotgSpacing.x2,
            ),
            child: Semantics(
              header: true,
              child: Text(
                strings.discoverySort,
                style: theme.textTheme.titleMedium,
              ),
            ),
          ),
          RadioGroup<DiscoverySort>(
            groupValue: selected,
            onChanged: (DiscoverySort? value) =>
                Navigator.of(context).pop(value),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (final SortOption option in options)
                  RadioListTile<DiscoverySort>(
                    value: option.sort,
                    // A disabled row rather than a hidden one: the customer can
                    // see the order exists and read why it is not available
                    // yet, instead of wondering whether the app has lost a
                    // feature.
                    enabled: option.isAvailable,
                    title: Text(_label(strings, option)),
                    subtitle:
                        option.isAvailable || option.unavailableReason == null
                        ? null
                        : Text(
                            option.unavailableReason!,
                            style: theme.textTheme.bodySmall,
                          ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: FotgSpacing.x2),
        ],
      ),
    );
  }

  /// The app's own words, falling back to the server's label for an order this
  /// build has no wording for.
  static String _label(AppStrings strings, SortOption option) =>
      switch (option.sort) {
        DiscoverySort.recommended => strings.discoverySortRecommended,
        DiscoverySort.lowestDetour => strings.discoverySortLowestDetour,
        DiscoverySort.soonestAlongRoute => strings.discoverySortSoonest,
        DiscoverySort.highestRated => strings.discoverySortHighestRated,
        DiscoverySort.priceLowToHigh => strings.discoverySortPriceLow,
      };

  static String labelFor(AppStrings strings, DiscoverySort sort) =>
      _label(strings, SortOption(sort: sort, label: '', isAvailable: true));

  /// What to offer when the server sent no facets — an older response, or a
  /// cached one. Rating is left out rather than guessed at.
  static List<SortOption> _fallback(AppStrings strings) => <SortOption>[
    for (final DiscoverySort sort in <DiscoverySort>[
      DiscoverySort.recommended,
      DiscoverySort.lowestDetour,
      DiscoverySort.soonestAlongRoute,
      DiscoverySort.priceLowToHigh,
    ])
      SortOption(sort: sort, label: labelFor(strings, sort), isAvailable: true),
  ];
}
