import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format/journey_measures.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/routing/routes.dart';
import '../../core/theme/tokens.dart';
import '../../domain/models/discovered_restaurant.dart';
import '../../domain/models/discovery_query.dart';
import '../../domain/models/trip.dart';
import '../../domain/models/trip_route.dart';
import '../../shared/state/discovery_controller.dart';
import '../../shared/state/route_controller.dart';
import '../../shared/widgets/app_skeleton.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/empty_state_view.dart';
import 'widgets/active_filter_chips.dart';
import 'widgets/discovery_filter_sheet.dart';
import 'widgets/discovery_map_view.dart';
import 'widgets/discovery_search_field.dart';
import 'widgets/discovery_sort_sheet.dart';
import 'widgets/restaurant_preview_card.dart';

/// Restaurants along the selected route.
///
/// Reached from the route screen's "Find food on this route", which is the only
/// way in: discovery has no meaning without a journey, and a journey without a
/// calculated route cannot be searched along.
///
/// The screen holds the route as well as the results, because both are drawn on
/// the same map. It takes the route from Module 06's controller rather than
/// asking the server again — the route the customer just looked at is the route
/// the restaurants were found along.
class DiscoveryScreen extends ConsumerStatefulWidget {
  const DiscoveryScreen({required this.tripId, super.key});

  final String tripId;

  @override
  ConsumerState<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends ConsumerState<DiscoveryScreen> {
  final GlobalKey<State<DiscoveryMapView>> _mapKey =
      GlobalKey<State<DiscoveryMapView>>();

  @override
  void initState() {
    super.initState();

    // After the first frame, not inside build(). Discovery is the most
    // expensive endpoint in the application, and a build method runs whenever
    // the framework feels like it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      ref.read(discoveryControllerProvider.notifier).open(widget.tripId);
      // The route, for the map. Never calculated from here: this screen is
      // reached from one that has already established it.
      ref
          .read(routeControllerProvider.notifier)
          .open(widget.tripId, calculateIfMissing: false);
    });
  }

  void _recentre() {
    final State<DiscoveryMapView>? map = _mapKey.currentState;

    if (map is DiscoveryMapRecentre) {
      (map as DiscoveryMapRecentre).recentreOnRoute();
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final DiscoveryState state = ref.watch(discoveryControllerProvider);
    final RouteViewState routeState = ref.watch(routeControllerProvider);

    final Trip? trip = routeState.routes?.trip;
    final TripRoute? route = routeState.selected;

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.discoveryTitle),
        actions: <Widget>[
          if (state.hasResults &&
              state.view == DiscoveryView.map &&
              _canRecentre)
            IconButton(
              icon: const Icon(Icons.my_location_rounded),
              tooltip: strings.discoveryRecentre,
              onPressed: _recentre,
            ),
        ],
        bottom: trip == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(24),
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: FotgSpacing.x4,
                    right: FotgSpacing.x4,
                    bottom: FotgSpacing.x2,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      strings.discoverySubtitle(
                        trip.origin.shortName,
                        trip.destination.shortName,
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
      ),
      body: SafeArea(
        top: false,
        child: _DiscoveryBody(
          state: state,
          trip: trip,
          route: route,
          mapKey: _mapKey,
          tripId: widget.tripId,
        ),
      ),
    );
  }

  /// The recentre control is offered only where a map can actually be drawn.
  /// An inert control reads as a broken app rather than as an absent feature.
  bool get _canRecentre => _mapKey.currentState is DiscoveryMapRecentre;
}

/// Everything below the app bar.
///
/// The search field and the filter chips are rendered outside the results,
/// which is deliberate: a customer whose filters left them with nothing must
/// still be able to see the filters and take one off. A screen that swaps the
/// whole body for an empty state takes the way out away with the results.
class _DiscoveryBody extends ConsumerWidget {
  const _DiscoveryBody({
    required this.state,
    required this.trip,
    required this.route,
    required this.mapKey,
    required this.tripId,
  });

  final DiscoveryState state;
  final Trip? trip;
  final TripRoute? route;
  final GlobalKey<State<DiscoveryMapView>> mapKey;
  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppStrings strings = AppStrings.of(context);
    final DiscoveryController controller = ref.read(
      discoveryControllerProvider.notifier,
    );

    // The very first load, with nothing to put a search field above.
    if (state.isLoading && state.discovery == null) {
      return const _DiscoverySkeleton();
    }

    // A failure with no results behind it: the route is not ready, the trip is
    // gone, we are offline with nothing cached. There is nothing to filter, so
    // there are no controls.
    if (state.discovery == null) {
      return _DiscoveryProblem(state: state, tripId: tripId);
    }

    return Column(
      children: <Widget>[
        if (state.isOffline)
          _Banner(
            icon: Icons.cloud_off_rounded,
            message: strings.discoveryOfflineCached,
          ),

        // The same honesty the route screen applies: a stop found along a
        // stand-in route is labelled as one.
        if (state.discovery?.isFromRealProvider == false)
          _Banner(
            icon: Icons.science_outlined,
            message: strings.discoveryDevelopmentProvider,
            isWarning: true,
          ),

        if (state.isClosedOnly)
          _Banner(
            icon: Icons.schedule_rounded,
            message: strings.discoveryClosedOnlyBody,
            isWarning: true,
          ),

        // A filter the server refused is our bug, not the customer's. It gets a
        // banner with a way out rather than an empty screen.
        if (state.failure == DiscoveryFailure.filtersRejected)
          _Banner(
            icon: Icons.filter_alt_off_rounded,
            message: strings.discoveryFiltersRejectedBody,
            isWarning: true,
          ),

        _DiscoveryControls(state: state, controller: controller),

        Expanded(
          child: switch (state) {
            DiscoveryState(hasResults: true) => switch (state.view) {
              DiscoveryView.map => _MapMode(
                state: state,
                trip: trip,
                route: route,
                mapKey: mapKey,
                controller: controller,
              ),
              DiscoveryView.list => _ListMode(
                state: state,
                controller: controller,
              ),
            },
            _ => _DiscoveryProblem(state: state, tripId: tripId),
          },
        ),
      ],
    );
  }
}

/// Search, filters, sort, and the count above the list.
class _DiscoveryControls extends StatelessWidget {
  const _DiscoveryControls({required this.state, required this.controller});

  final DiscoveryState state;
  final DiscoveryController controller;

  Future<void> _openFilters(BuildContext context) async {
    final DiscoveryQuery? chosen = await DiscoveryFilterSheet.show(
      context,
      facets: state.facets,
      applied: state.query,
    );

    // Null means dismissed. Dismissing a sheet is not applying an empty one.
    if (chosen != null) controller.applyQuery(chosen);
  }

  Future<void> _openSort(BuildContext context) async {
    final DiscoverySort? chosen = await DiscoverySortSheet.show(
      context,
      facets: state.facets,
      selected: state.query.sort,
    );

    if (chosen != null) controller.sortBy(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final ThemeData theme = Theme.of(context);

    final int filterCount = state.query.filterCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            FotgSpacing.x4,
            FotgSpacing.x3,
            FotgSpacing.x4,
            FotgSpacing.x2,
          ),
          child: DiscoverySearchField(
            text: state.searchText,
            onChanged: controller.searchChanged,
            onSubmitted: controller.submitSearch,
            onCleared: controller.clearSearch,
          ),
        ),

        ActiveFilterChips(
          query: state.query,
          facets: state.facets,
          onRemoveCuisine: controller.removeCuisine,
          onRemoveFacility: controller.removeFacility,
          onRemovePriceLevel: controller.removePriceLevel,
          onRemoveAvailability: controller.removeAvailability,
          onRemoveMaxDetour: controller.removeMaxDetour,
          onRemoveMaxDistanceAhead: controller.removeMaxDistanceAhead,
          onRemoveMinRating: controller.removeMinRating,
          onClearAll: controller.clearFilters,
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(
            FotgSpacing.x4,
            FotgSpacing.x2,
            FotgSpacing.x4,
            FotgSpacing.x2,
          ),
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              // Measured: with both toggle labels the row wants about 250dp,
              // and on a 320dp screen that overflowed by 69 pixels. Below 300dp
              // the labels go; the icons and their accessible names stay.
              final bool compact = constraints.maxWidth < 340;

              return Row(
                children: <Widget>[
                  Expanded(
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        // "6 of 11" only while something is hiding results, so
                        // an unfiltered screen is never made to look filtered.
                        state.query.isRefined
                            ? strings.discoveryResultCountFiltered(
                                state.totalCount,
                                state.eligibleCount,
                              )
                            : strings.discoveryResultCount(state.totalCount),
                        style: theme.textTheme.titleSmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: FotgSpacing.x2),
                  _FilterButton(
                    count: filterCount,
                    compact: compact,
                    onPressed: () => _openFilters(context),
                  ),
                  const SizedBox(width: FotgSpacing.x1),
                  IconButton(
                    icon: const Icon(Icons.swap_vert_rounded, size: 20),
                    tooltip: strings.discoverySortBy(
                      DiscoverySortSheet.labelFor(strings, state.query.sort),
                    ),
                    onPressed: () => _openSort(context),
                  ),
                ],
              );
            },
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(
            FotgSpacing.x4,
            0,
            FotgSpacing.x4,
            FotgSpacing.x2,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  strings.discoverySortBy(
                    DiscoverySortSheet.labelFor(strings, state.query.sort),
                  ),
                  style: theme.textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: FotgSpacing.x2),
              _MapListToggle(
                view: state.view,
                onChanged: controller.showView,
                compact: MediaQuery.sizeOf(context).width < 340,
              ),
            ],
          ),
        ),

        // A thin bar rather than a spinner over the list: the results below are
        // still the last honest answer, and blanking them on every keystroke
        // makes the list unreadable while somebody types.
        if (state.isRefining)
          Semantics(
            liveRegion: true,
            label: strings.discoveryRefining,
            child: const LinearProgressIndicator(minHeight: 2),
          ),
      ],
    );
  }
}

/// "Filters", with how many are on.
class _FilterButton extends StatelessWidget {
  const _FilterButton({
    required this.count,
    required this.onPressed,
    this.compact = false,
  });

  final int count;
  final VoidCallback onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);

    // The count is in the accessible name whether or not the badge is drawn,
    // so a screen reader never announces a bare "Filters" over a filtered list.
    final String label = count == 0
        ? strings.discoveryFiltersOpen
        : '${strings.discoveryFiltersOpen}, ${strings.discoveryFilterCount(count)}';

    final Widget icon = Badge(
      isLabelVisible: count > 0,
      label: Text('$count'),
      child: const Icon(Icons.tune_rounded, size: 20),
    );

    return Tooltip(
      message: label,
      child: compact
          ? IconButton(onPressed: onPressed, icon: icon)
          : TextButton.icon(
              onPressed: onPressed,
              icon: icon,
              label: Text(strings.discoveryFilters),
            ),
    );
  }
}

/// Map above, the selected restaurant's card below it.
class _MapMode extends StatelessWidget {
  const _MapMode({
    required this.state,
    required this.trip,
    required this.route,
    required this.mapKey,
    required this.controller,
  });

  final DiscoveryState state;
  final Trip? trip;
  final TripRoute? route;
  final GlobalKey<State<DiscoveryMapView>> mapKey;
  final DiscoveryController controller;

  @override
  Widget build(BuildContext context) {
    final Trip? trip = this.trip;

    if (trip == null) {
      // The route is still loading. The list is complete without it, so the map
      // waits rather than the whole screen doing so.
      return const Center(child: CircularProgressIndicator());
    }

    final DiscoveredRestaurant? selected = state.selected;

    return Column(
      children: <Widget>[
        Expanded(
          child: DiscoveryMapView(
            key: mapKey,
            trip: trip,
            route: route,
            restaurants: state.restaurants,
            selectedRestaurantId: state.selectedRestaurantId,
            onRestaurantTapped: controller.selectRestaurant,
          ),
        ),
        if (selected != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              FotgSpacing.x4,
              FotgSpacing.x2,
              FotgSpacing.x4,
              FotgSpacing.x4,
            ),
            child: RestaurantPreviewCard(
              restaurant: selected,
              isSelected: true,
              onSelect: () => controller.selectRestaurant(selected.id),
              onView: () => _openRestaurant(context, selected),
            ),
          ),
      ],
    );
  }
}

/// Every stop that matches, in the chosen order.
class _ListMode extends StatelessWidget {
  const _ListMode({required this.state, required this.controller});

  final DiscoveryState state;
  final DiscoveryController controller;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        FotgSpacing.x4,
        0,
        FotgSpacing.x4,
        FotgSpacing.x6,
      ),
      // One extra row for the button, and only when there is another page.
      itemCount: state.restaurants.length + (state.hasMore ? 1 : 0),
      itemBuilder: (BuildContext context, int index) {
        if (index >= state.restaurants.length) {
          return Padding(
            padding: const EdgeInsets.only(top: FotgSpacing.x2),
            child: state.isLoadingMore
                ? const Center(child: CircularProgressIndicator())
                : SecondaryButton(
                    label: strings.discoveryLoadMore,
                    expand: true,
                    onPressed: controller.loadMore,
                  ),
          );
        }

        final DiscoveredRestaurant restaurant = state.restaurants[index];

        return RestaurantPreviewCard(
          restaurant: restaurant,
          isSelected: restaurant.id == state.selectedRestaurantId,
          onSelect: () => controller.selectRestaurant(restaurant.id),
          onView: () => _openRestaurant(context, restaurant),
        );
      },
    );
  }
}

/// The full restaurant page belongs to a later module.
void _openRestaurant(BuildContext context, DiscoveredRestaurant restaurant) {
  context.push(
    Routes.comingSoonFor(feature: restaurant.displayName, module: 'Module 09'),
  );
}

/// Map or list. State is preserved across the switch — the results are already
/// in hand, and re-running the search because somebody changed how they are
/// looking at them would be a bill for nothing.
class _MapListToggle extends StatelessWidget {
  const _MapListToggle({
    required this.view,
    required this.onChanged,
    this.compact = false,
  });

  final DiscoveryView view;
  final ValueChanged<DiscoveryView> onChanged;

  /// Icons without their labels, for a screen too narrow for both.
  ///
  /// The labels are what a screen reader announces, so they do not simply
  /// disappear: each segment keeps its own tooltip, which is also its
  /// accessible name.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);

    return SegmentedButton<DiscoveryView>(
      segments: <ButtonSegment<DiscoveryView>>[
        ButtonSegment<DiscoveryView>(
          value: DiscoveryView.list,
          icon: const Icon(Icons.view_list_rounded, size: 18),
          label: compact ? null : Text(strings.discoveryListTab),
          tooltip: strings.discoveryListTab,
        ),
        ButtonSegment<DiscoveryView>(
          value: DiscoveryView.map,
          icon: const Icon(Icons.map_rounded, size: 18),
          label: compact ? null : Text(strings.discoveryMapTab),
          tooltip: strings.discoveryMapTab,
        ),
      ],
      selected: <DiscoveryView>{view},
      onSelectionChanged: (Set<DiscoveryView> selection) =>
          onChanged(selection.first),
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

/// Everything that is not a list of restaurants.
class _DiscoveryProblem extends ConsumerWidget {
  const _DiscoveryProblem({required this.state, required this.tripId});

  final DiscoveryState state;
  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppStrings strings = AppStrings.of(context);
    final DiscoveryController controller = ref.read(
      discoveryControllerProvider.notifier,
    );

    // Three different empty screens, and the difference matters more than the
    // wording. "Nothing matched your search" is the customer's own doing and
    // offers to undo it; "no stops on this route yet" is ours and offers a way
    // back to the journey. Showing the second when it is the first tells
    // somebody there is no food on a road with eleven restaurants on it.
    if (state.isSearchEmpty) {
      return EmptyStateView(
        icon: Icons.search_off_rounded,
        title: strings.discoverySearchEmptyTitle,
        body: strings.discoverySearchEmptyBody(state.query.search ?? ''),
        action: SecondaryButton(
          label: strings.discoverySearchEmptyCta,
          onPressed: controller.clearSearch,
        ),
      );
    }

    if (state.isFilteredEmpty) {
      return EmptyStateView(
        icon: Icons.filter_alt_off_rounded,
        title: strings.discoveryFilteredEmptyTitle,
        body: strings.discoveryFilteredEmptyBody(state.eligibleCount),
        action: SecondaryButton(
          label: strings.discoveryFilteredEmptyCta,
          onPressed: controller.clearFilters,
        ),
      );
    }

    // An empty result is not a failure. It is the honest answer that there is
    // nothing on this road yet, and it gets its own words and its own actions.
    if (state.isEmptyResult) {
      return EmptyStateView(
        icon: Icons.storefront_outlined,
        title: strings.discoveryEmptyTitle,
        body: strings.discoveryEmptyBody(
          JourneyMeasures.distance(state.discovery?.corridorMetres ?? 0),
        ),
        action: SecondaryButton(
          label: strings.discoveryEmptyBackToJourney,
          onPressed: () => context.pop(),
        ),
      );
    }

    final (IconData icon, String title, String body) = switch (state.failure) {
      DiscoveryFailure.routeNotReady => (
        Icons.alt_route_rounded,
        strings.discoveryRouteNotReadyTitle,
        strings.discoveryRouteNotReadyBody,
      ),
      DiscoveryFailure.rateLimited => (
        Icons.hourglass_top_rounded,
        strings.discoveryRateLimitedTitle,
        strings.discoveryRateLimitedBody,
      ),
      DiscoveryFailure.network => (
        Icons.cloud_off_rounded,
        strings.discoveryOfflineTitle,
        strings.discoveryOfflineBody,
      ),
      DiscoveryFailure.tripGone => (
        Icons.link_off_rounded,
        strings.discoveryErrorTitle,
        strings.tripErrorGone,
      ),
      DiscoveryFailure.filtersRejected => (
        Icons.filter_alt_off_rounded,
        strings.discoveryFiltersRejectedTitle,
        strings.discoveryFiltersRejectedBody,
      ),
      _ => (
        Icons.error_outline_rounded,
        strings.discoveryErrorTitle,
        strings.discoveryErrorBody,
      ),
    };

    return EmptyStateView(
      icon: icon,
      title: title,
      body: body,
      action: state.failure == DiscoveryFailure.filtersRejected
          ? PrimaryButton(
              label: strings.discoveryFiltersClear,
              expand: false,
              onPressed: controller.resetAll,
            )
          : state.failure == DiscoveryFailure.routeNotReady
          ? PrimaryButton(
              label: strings.discoveryRouteNotReadyCta,
              expand: false,
              onPressed: () =>
                  context.pushReplacement(Routes.tripRoutePath(tripId)),
            )
          : state.isRetryable
          ? PrimaryButton(
              label: strings.discoveryTryAgain,
              expand: false,
              onPressed: controller.retry,
            )
          : null,
    );
  }
}

/// A restrained notice over the results.
class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.message,
    this.isWarning = false,
  });

  final IconData icon;
  final String message;
  final bool isWarning;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    final Color background = isWarning
        ? theme.colorScheme.errorContainer
        : theme.colorScheme.surfaceContainerHighest;
    final Color foreground = isWarning
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.onSurfaceVariant;

    return Container(
      width: double.infinity,
      color: background,
      padding: const EdgeInsets.symmetric(
        horizontal: FotgSpacing.x4,
        vertical: FotgSpacing.x2,
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 16, color: foreground),
          const SizedBox(width: FotgSpacing.x2),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.labelSmall?.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

/// The shape of the answer, while it is being worked out.
///
/// A skeleton rather than a spinner: the customer is about to read a list of
/// cards, and showing where they will be is less jarring than a blank screen
/// that suddenly fills.
class _DiscoverySkeleton extends StatelessWidget {
  const _DiscoverySkeleton();

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);

    return Padding(
      padding: const EdgeInsets.all(FotgSpacing.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Semantics(
            liveRegion: true,
            child: Text(
              strings.discoveryLoading,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: FotgSpacing.x4),
          for (int i = 0; i < 3; i++) ...<Widget>[
            const AppSkeleton(height: 96, radius: FotgRadius.lg),
            const SizedBox(height: FotgSpacing.x3),
          ],
        ],
      ),
    );
  }
}
