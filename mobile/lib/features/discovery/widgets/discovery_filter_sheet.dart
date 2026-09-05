import 'package:flutter/material.dart';

import '../../../core/format/journey_measures.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/models/discovery_facets.dart';
import '../../../domain/models/discovery_query.dart';

/// Cuisine, facilities, price, availability and detour, in one sheet.
///
/// The sheet edits a **draft**. Nothing is applied until the customer presses
/// the button, which is what keeps a request per checkbox from happening and
/// stops the list from resorting under their finger while they are still
/// choosing. Dismissing it discards the draft entirely.
///
/// Every option shown comes from the server's facets — the cuisines that exist
/// on *this* route, with the counts they have on it. There is no hard-coded
/// list of cuisines in this file, because a filter for something no partner on
/// the road serves is a filter whose only outcome is an empty screen.
class DiscoveryFilterSheet extends StatefulWidget {
  const DiscoveryFilterSheet({
    required this.facets,
    required this.applied,
    super.key,
  });

  final DiscoveryFacets facets;

  /// What is currently in force. The draft starts as a copy of it.
  final DiscoveryQuery applied;

  /// Returns the query to apply, or null if the sheet was dismissed.
  static Future<DiscoveryQuery?> show(
    BuildContext context, {
    required DiscoveryFacets facets,
    required DiscoveryQuery applied,
  }) => showModalBottomSheet<DiscoveryQuery>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (BuildContext context) =>
        DiscoveryFilterSheet(facets: facets, applied: applied),
  );

  @override
  State<DiscoveryFilterSheet> createState() => _DiscoveryFilterSheetState();
}

class _DiscoveryFilterSheetState extends State<DiscoveryFilterSheet> {
  late DiscoveryQuery _draft = widget.applied;

  void _edit(DiscoveryQuery next) => setState(() => _draft = next);

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final ThemeData theme = Theme.of(context);
    final DiscoveryFacets facets = widget.facets;

    return SafeArea(
      child: ConstrainedBox(
        // Never taller than most of the screen: the customer has to be able to
        // see that there is a list behind the sheet they are filtering.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                FotgSpacing.x4,
                0,
                FotgSpacing.x2,
                FotgSpacing.x2,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        strings.discoveryFilters,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                  ),
                  if (_draft.hasFilters)
                    TextButton(
                      onPressed: () => _edit(_draft.cleared()),
                      child: Text(strings.discoveryFiltersClear),
                    ),
                ],
              ),
            ),

            Flexible(
              child: facets.isEmpty && facets.availability.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(FotgSpacing.x4),
                      child: Text(
                        strings.discoveryFiltersNone,
                        style: theme.textTheme.bodyMedium,
                      ),
                    )
                  : ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(
                        FotgSpacing.x4,
                        0,
                        FotgSpacing.x4,
                        FotgSpacing.x4,
                      ),
                      children: <Widget>[
                        if (facets.availability.isNotEmpty)
                          _Group(
                            title: strings.discoveryFilterAvailability,
                            children: <Widget>[
                              for (final AvailabilityOption option
                                  in facets.availability)
                                _Choice(
                                  // A single choice, not a pair of checkboxes:
                                  // "open" and "taking orders" answer the same
                                  // question, and selecting both would mean
                                  // nothing.
                                  label: strings.discoveryFilterOption(
                                    option.label,
                                    option.count,
                                  ),
                                  selected: _draft.availability == option.value,
                                  onChanged: (bool on) => _edit(
                                    on
                                        ? _draft.copyWith(
                                            availability: option.value,
                                          )
                                        : _draft.copyWith(
                                            clearAvailability: true,
                                          ),
                                  ),
                                ),
                            ],
                          ),

                        if (facets.cuisines.isNotEmpty)
                          _Group(
                            title: strings.discoveryFilterCuisine,
                            hint: strings.discoveryFilterCuisineHint,
                            children: <Widget>[
                              for (final FilterOption option in facets.cuisines)
                                _Choice(
                                  label: strings.discoveryFilterOption(
                                    option.label,
                                    option.count,
                                  ),
                                  selected: _draft.cuisines.contains(
                                    option.slug,
                                  ),
                                  onChanged: (_) =>
                                      _edit(_draft.toggleCuisine(option.slug)),
                                ),
                            ],
                          ),

                        if (facets.facilities.isNotEmpty)
                          _Group(
                            title: strings.discoveryFilterFacilities,
                            hint: strings.discoveryFilterFacilitiesHint,
                            children: <Widget>[
                              for (final FilterOption option
                                  in facets.facilities)
                                _Choice(
                                  label: strings.discoveryFilterOption(
                                    option.label,
                                    option.count,
                                  ),
                                  selected: _draft.facilities.contains(
                                    option.slug,
                                  ),
                                  onChanged: (_) =>
                                      _edit(_draft.toggleFacility(option.slug)),
                                ),
                            ],
                          ),

                        if (facets.priceLevels.isNotEmpty)
                          _Group(
                            title: strings.discoveryFilterPrice,
                            hint: strings.discoveryFilterCuisineHint,
                            children: <Widget>[
                              for (final PriceOption option
                                  in facets.priceLevels)
                                _Choice(
                                  // The rupee symbols are decoration; the words
                                  // are what a screen reader announces.
                                  label: strings.discoveryFilterOption(
                                    '${'₹' * option.level} · '
                                    '${strings.priceLevelLabel(option.level)}',
                                    option.count,
                                  ),
                                  selected: _draft.priceLevels.contains(
                                    option.level,
                                  ),
                                  onChanged: (_) => _edit(
                                    _draft.togglePriceLevel(option.level),
                                  ),
                                ),
                            ],
                          ),

                        if (facets.maxDetourSeconds > 0)
                          _Group(
                            title: strings.discoveryFilterDetour,
                            children: <Widget>[
                              _Choice(
                                label: strings.discoveryDetourAny,
                                selected: _draft.maxDetourSeconds == null,
                                onChanged: (_) => _edit(
                                  _draft.copyWith(clearMaxDetour: true),
                                ),
                              ),
                              for (final int seconds in _detourSteps(
                                facets.maxDetourSeconds,
                              ))
                                _Choice(
                                  label: strings.discoveryDetourUnder(
                                    JourneyMeasures.duration(seconds),
                                  ),
                                  selected: _draft.maxDetourSeconds == seconds,
                                  onChanged: (_) => _edit(
                                    _draft.copyWith(maxDetourSeconds: seconds),
                                  ),
                                ),
                            ],
                          ),

                        // Rendered only where something on this route actually
                        // has a rating. A control that can only ever return
                        // nothing is worse than an absent one: it implies the
                        // ratings are there and the restaurants fall short.
                        if (facets.ratingAvailable)
                          _Group(
                            title: strings.discoverySortHighestRated,
                            children: <Widget>[
                              for (final double rating in <double>[
                                3.0,
                                4.0,
                                4.5,
                              ])
                                _Choice(
                                  label: '$rating+',
                                  selected: _draft.minRating == rating,
                                  onChanged: (bool on) => _edit(
                                    on
                                        ? _draft.copyWith(minRating: rating)
                                        : _draft.copyWith(clearMinRating: true),
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(
                FotgSpacing.x4,
                FotgSpacing.x2,
                FotgSpacing.x4,
                FotgSpacing.x4,
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(_draft),
                  child: Text(strings.discoveryFiltersApply),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Detour options up to whatever the server's ceiling is.
  ///
  /// Derived rather than hard-coded, so raising the corridor's detour budget on
  /// the server does not leave the sheet offering options that no longer reach
  /// the top of the range.
  static List<int> _detourSteps(int ceiling) => <int>[
    for (final int seconds in <int>[300, 600, 900, 1200])
      if (seconds < ceiling) seconds,
    ceiling,
  ];
}

/// A titled group of choices.
class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children, this.hint});

  final String title;
  final String? hint;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: FotgSpacing.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Semantics(
            header: true,
            child: Text(title, style: theme.textTheme.titleSmall),
          ),
          if (hint != null)
            Text(
              hint!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: FotgSpacing.x2),
          Wrap(
            spacing: FotgSpacing.x2,
            runSpacing: FotgSpacing.x2,
            children: children,
          ),
        ],
      ),
    );
  }
}

/// One filter value.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => FilterChip(
    label: Text(label),
    selected: selected,
    onSelected: onChanged,
    showCheckmark: true,
  );
}
