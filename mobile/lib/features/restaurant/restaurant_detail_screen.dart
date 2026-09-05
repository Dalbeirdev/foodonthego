import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/routing/routes.dart';
import '../../core/theme/tokens.dart';
import '../../domain/models/discovered_restaurant.dart';
import '../../domain/models/restaurant_detail.dart';
import '../../shared/state/restaurant_detail_controller.dart';
import '../../shared/widgets/app_skeleton.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/empty_state_view.dart';
import 'widgets/restaurant_availability.dart';
import 'widgets/restaurant_hero_gallery.dart';
import 'widgets/restaurant_sections.dart';

/// One restaurant, on this customer's route.
///
/// Reached only from discovery, and it keeps the journey in the URL: the route
/// figures on this screen were measured against one particular road, and a
/// detail page without a trip would be a generic restaurant listing — which is
/// the product FoodOnTheGo is deliberately not.
///
/// The customer's question here is narrow: *is this the right place for me to
/// stop?* Everything on the screen serves that and nothing else. There is no
/// favourite button, no share sheet and no reviews list, because none of them
/// helps answer it.
class RestaurantDetailScreen extends ConsumerStatefulWidget {
  const RestaurantDetailScreen({
    required this.tripId,
    required this.restaurantId,
    this.preview,
    super.key,
  });

  final String tripId;
  final String restaurantId;

  /// What the card already knew, handed over at the moment of the tap so the
  /// transition has something in it. Replaced the moment the server answers.
  final DiscoveredRestaurant? preview;

  @override
  ConsumerState<RestaurantDetailScreen> createState() =>
      _RestaurantDetailScreenState();
}

class _RestaurantDetailScreenState
    extends ConsumerState<RestaurantDetailScreen> {
  @override
  void initState() {
    super.initState();

    // After the first frame, not inside build(). A build method runs whenever
    // the framework feels like it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      ref
          .read(restaurantDetailControllerProvider.notifier)
          .open(
            tripId: widget.tripId,
            restaurantId: widget.restaurantId,
            preview: widget.preview,
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final RestaurantDetailState state = ref.watch(
      restaurantDetailControllerProvider,
    );
    final RestaurantDetailController controller = ref.read(
      restaurantDetailControllerProvider.notifier,
    );

    final RestaurantDetail? detail = state.detail;

    return Scaffold(
      appBar: AppBar(
        // Explicit, and wired to the router rather than to the raw Navigator.
        // `Navigator.maybePop` — what the automatic back button calls — pops
        // the widget stack without telling go_router, which leaves its match
        // list empty and the shell without a location. The customer sees a
        // blank screen where the discovery list should be.
        leading: BackButton(onPressed: () => context.pop()),
        title: Text(
          state.name.isEmpty ? strings.restaurantDetailTitle : state.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        top: false,
        child: switch (state) {
          // A failure with nothing behind it. The preview is deliberately not
          // used to paper over this: a suspended restaurant must not go on
          // looking open because its card is still in memory.
          RestaurantDetailState(hasDetail: false, failure: != null) =>
            _RestaurantProblem(state: state, controller: controller),

          RestaurantDetailState(hasDetail: false) => _RestaurantSkeleton(
            preview: state.preview,
          ),

          _ => _RestaurantBody(
            detail: detail!,
            state: state,
            controller: controller,
          ),
        },
      ),
      bottomNavigationBar: detail == null
          ? null
          : _StickyCta(detail: detail, tripId: widget.tripId),
    );
  }
}

/// Everything between the app bar and the button.
class _RestaurantBody extends StatelessWidget {
  const _RestaurantBody({
    required this.detail,
    required this.state,
    required this.controller,
  });

  final RestaurantDetail detail;
  final RestaurantDetailState state;
  final RestaurantDetailController controller;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final DiscoveredRestaurant r = detail.restaurant;

    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView(
        // Always scrollable, so pull-to-refresh works on a short page too.
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: FotgSpacing.x6),
        children: <Widget>[
          if (state.isOffline) _OfflineBanner(generatedAt: detail.generatedAt),

          RestaurantHeroGallery(
            name: r.name,
            images: detail.media,
            onIndexChanged: controller.galleryMovedTo,
          ),

          RestaurantDetailHeader(detail: detail),

          Padding(
            padding: const EdgeInsets.fromLTRB(
              FotgSpacing.x4,
              FotgSpacing.x3,
              FotgSpacing.x4,
              0,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: RestaurantAvailabilityBadge(state: detail.ordering),
            ),
          ),

          RestaurantUnavailableBanner(
            state: detail.ordering,
            nextOpenAt: detail.hours.nextOpenAt,
          ),

          // The card that makes this FoodOnTheGo's screen rather than a
          // generic restaurant page.
          RestaurantRouteSummary(route: r.route),

          // Every section below omits itself when the restaurant declared
          // nothing. An empty card with a heading over blank space reads as a
          // bug, and inventing content to fill it would be worse.
          if (detail.hasDescription)
            RestaurantSection(
              title: strings.restaurantAbout,
              child: Text(
                detail.description!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),

          if (r.facilities.isNotEmpty)
            RestaurantSection(
              title: strings.restaurantFacilities,
              child: RestaurantFacilitiesGrid(facilities: r.facilities),
            ),

          RestaurantSection(
            title: strings.restaurantOpeningHours,
            child: RestaurantHoursSection(
              hours: detail.hours,
              expanded: state.hoursExpanded,
              onToggle: controller.toggleHours,
            ),
          ),

          _LocationSection(detail: detail),
        ],
      ),
    );
  }
}

/// Where it is, and a way back to seeing it on the route.
class _LocationSection extends StatelessWidget {
  const _LocationSection({required this.detail});

  final RestaurantDetail detail;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final ThemeData theme = Theme.of(context);
    final DiscoveredRestaurant r = detail.restaurant;

    final String? address = r.city;

    return RestaurantSection(
      title: strings.restaurantLocation,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (address != null && address.isNotEmpty)
            Text(address, style: theme.textTheme.bodyMedium),

          // The published business number, where the operator has one. Never
          // the owner's personal mobile — a different column that this screen
          // is never sent.
          if (detail.publicPhone != null) ...<Widget>[
            const SizedBox(height: FotgSpacing.x2),
            Row(
              children: <Widget>[
                Icon(
                  Icons.call_rounded,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: FotgSpacing.x2),
                Flexible(
                  child: Semantics(
                    label: strings.restaurantCallLabel,
                    child: Text(
                      detail.publicPhone!,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: FotgSpacing.x2),
          // Back to the discovery map, which already draws this restaurant
          // against the route. A second full map here would be the same screen
          // twice, and FoodOnTheGo is not a navigation app.
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => context.pop(),
              icon: const Icon(Icons.map_rounded, size: 18),
              label: Text(strings.restaurantViewOnRoute),
            ),
          ),
        ],
      ),
    );
  }
}

/// The button, pinned above the safe area.
class _StickyCta extends StatelessWidget {
  const _StickyCta({required this.detail, required this.tripId});

  final RestaurantDetail detail;
  final String tripId;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(FotgSpacing.x4),
          child: RestaurantPrimaryCta(
            state: detail.ordering,
            // Module 10 owns the menu. Until it exists the controlled
            // placeholder stands in — and it is reached only where the
            // ordering state permits browsing, so the button's meaning is
            // already correct.
            onPressed: () => context.push(
              Routes.comingSoonFor(feature: detail.name, module: 'Module 10'),
            ),
          ),
        ),
      ),
    );
  }
}

/// Offline, with an honest age on what is being shown.
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.generatedAt});

  final DateTime generatedAt;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final ThemeData theme = Theme.of(context);

    final Duration age = DateTime.now().difference(generatedAt);

    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(
        horizontal: FotgSpacing.x4,
        vertical: FotgSpacing.x2,
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.cloud_off_rounded,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: FotgSpacing.x2),
          Expanded(
            child: Text(
              // The real age of the real payload. Never a fabricated
              // timestamp, and never a claim that the open sign is live.
              age.inMinutes < 1
                  ? strings.restaurantOfflineCached
                  : strings.restaurantOfflineAge(_age(age)),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _age(Duration age) =>
      age.inHours >= 1 ? '${age.inHours} hr' : '${age.inMinutes} min';
}

/// The shape of the answer, while it is being fetched.
///
/// Not a spinner. The customer is about to read a page with a picture, a name
/// and a route card on it, and showing where those will be is less jarring than
/// a blank screen that suddenly fills. Where a preview came from the card, its
/// real name is drawn immediately.
class _RestaurantSkeleton extends StatelessWidget {
  const _RestaurantSkeleton({this.preview});

  final DiscoveredRestaurant? preview;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final ThemeData theme = Theme.of(context);

    return ListView(
      padding: EdgeInsets.zero,
      children: <Widget>[
        const AppSkeleton(height: 240, radius: 0),
        Padding(
          padding: const EdgeInsets.all(FotgSpacing.x4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Semantics(
                liveRegion: true,
                child: Text(
                  preview?.name ?? strings.restaurantLoading,
                  style: theme.textTheme.headlineSmall,
                ),
              ),
              const SizedBox(height: FotgSpacing.x3),
              const AppSkeleton(height: 18, radius: FotgRadius.sm),
              const SizedBox(height: FotgSpacing.x2),
              const AppSkeleton(height: 18, radius: FotgRadius.sm),
              const SizedBox(height: FotgSpacing.x4),
              const AppSkeleton(height: 132, radius: FotgRadius.lg),
              const SizedBox(height: FotgSpacing.x4),
              const AppSkeleton(height: 96, radius: FotgRadius.lg),
            ],
          ),
        ),
      ],
    );
  }
}

/// Everything that is not a restaurant.
class _RestaurantProblem extends StatelessWidget {
  const _RestaurantProblem({required this.state, required this.controller});

  final RestaurantDetailState state;
  final RestaurantDetailController controller;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);

    final (IconData icon, String title, String body) = switch (state.failure) {
      // It was on the route a moment ago and has since been withdrawn. A
      // different sentence from "we couldn't load it", and a different button.
      RestaurantDetailFailure.withdrawn => (
        Icons.storefront_outlined,
        strings.restaurantGoneTitle,
        strings.restaurantGoneBody,
      ),
      RestaurantDetailFailure.notFound => (
        Icons.storefront_outlined,
        strings.restaurantGoneTitle,
        strings.restaurantGoneBody,
      ),
      RestaurantDetailFailure.outsideRoute => (
        Icons.alt_route_rounded,
        strings.restaurantOutsideRouteTitle,
        strings.restaurantOutsideRouteBody,
      ),
      RestaurantDetailFailure.routeNotReady => (
        Icons.alt_route_rounded,
        strings.discoveryRouteNotReadyTitle,
        strings.discoveryRouteNotReadyBody,
      ),
      RestaurantDetailFailure.rateLimited => (
        Icons.hourglass_top_rounded,
        strings.discoveryRateLimitedTitle,
        strings.discoveryRateLimitedBody,
      ),
      RestaurantDetailFailure.network => (
        Icons.cloud_off_rounded,
        strings.discoveryOfflineTitle,
        strings.discoveryOfflineBody,
      ),
      RestaurantDetailFailure.tripGone => (
        Icons.link_off_rounded,
        strings.restaurantErrorTitle,
        strings.tripErrorGone,
      ),
      _ => (
        Icons.error_outline_rounded,
        strings.restaurantErrorTitle,
        strings.restaurantErrorBody,
      ),
    };

    return EmptyStateView(
      icon: icon,
      title: title,
      body: body,
      action: state.isRetryable
          ? PrimaryButton(
              label: strings.restaurantTryAgain,
              expand: false,
              onPressed: controller.retry,
            )
          : SecondaryButton(
              label: strings.restaurantBackToList,
              onPressed: () => context.pop(),
            ),
    );
  }
}
