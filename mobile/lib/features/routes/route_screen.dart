import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/maps_config.dart';
import '../../core/format/journey_measures.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/routing/routes.dart';
import '../../core/theme/tokens.dart';
import '../../domain/models/trip.dart';
import '../../domain/models/trip_route.dart';
import '../../shared/state/route_controller.dart';
import '../../shared/widgets/app_skeleton.dart';
import '../../shared/widgets/buttons.dart';
import 'widgets/route_map_view.dart';
import 'widgets/route_option_card.dart';

/// The route review screen: a map above, the journey's numbers below.
///
/// Everything on it comes from the server, which got it from a routing provider.
/// Nothing here computes a distance, estimates a duration or draws a line
/// between two points because it seemed about right — and where there is no
/// route, the screen says which of the several reasons applies rather than
/// showing an empty map.
class RouteScreen extends ConsumerStatefulWidget {
  const RouteScreen({required this.tripId, super.key});

  final String tripId;

  @override
  ConsumerState<RouteScreen> createState() => _RouteScreenState();
}

class _RouteScreenState extends ConsumerState<RouteScreen> {
  final GlobalKey<State<RouteMapView>> _mapKey =
      GlobalKey<State<RouteMapView>>();

  @override
  void initState() {
    super.initState();

    // Once, after the first frame — not from `build()`. A calculation wired to
    // a build method bills for every rebuild the framework decides to do, and
    // this screen rebuilds whenever the sheet is dragged.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(routeControllerProvider.notifier).open(widget.tripId);
      }
    });
  }

  void _recentre() {
    final State<RouteMapView>? map = _mapKey.currentState;

    if (map is RouteMapRecentre) {
      (map as RouteMapRecentre).recentre();
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final RouteViewState state = ref.watch(routeControllerProvider);
    final Trip? trip = state.routes?.trip;

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.routeTitle),
        actions: <Widget>[
          // Only where there is a map to recentre. On a build that cannot draw
          // one the button is inert, and an offered control that does nothing
          // when tapped reads as a broken app rather than as an absent feature.
          if (state.hasRoutes && MapsConfig.canRenderMap)
            IconButton(
              icon: const Icon(Icons.my_location_rounded),
              tooltip: strings.routeRecenterHint,
              onPressed: _recentre,
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: switch (state) {
          RouteViewState(isLoading: true) => const _RouteSkeleton(),
          RouteViewState(hasRoutes: true) => _RouteBody(
            state: state,
            mapKey: _mapKey,
            onRecentre: _recentre,
          ),
          _ => _RouteProblem(state: state, trip: trip),
        },
      ),
    );
  }
}

/// Map, summary, alternatives.
class _RouteBody extends ConsumerWidget {
  const _RouteBody({
    required this.state,
    required this.mapKey,
    required this.onRecentre,
  });

  final RouteViewState state;
  final GlobalKey<State<RouteMapView>> mapKey;
  final VoidCallback onRecentre;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppStrings strings = AppStrings.of(context);
    final Trip trip = state.routes!.trip;
    final List<TripRoute> routes = state.routes!.routes;
    final TripRoute? selected = state.selected ?? state.routes!.recommended;

    final Widget map = RouteMapView(
      key: mapKey,
      trip: trip,
      routes: routes,
      selectedRouteId: selected?.id,
      onRouteTapped: (String id) =>
          ref.read(routeControllerProvider.notifier).select(id),
    );

    final Widget? offlineBanner = state.isOffline
        ? _Banner(
            icon: Icons.cloud_off_rounded,
            message: strings.routeOfflineCached,
          )
        : null;

    final Widget? providerBanner = state.routes!.isFromRealProvider
        ? null
        : _Banner(
            icon: Icons.science_outlined,
            message: strings.routeDevelopmentProvider,
            isWarning: true,
          );

    return Column(
      children: <Widget>[
        // The map takes what is left after the sheet, rather than the sheet
        // floating over a map that has already framed itself for the whole
        // screen — the route would sit under the panel on a short phone.
        Expanded(
          flex: 4,
          // A banner floats over map tiles, which lose nothing by being partly
          // covered. It must not float over the map-unavailable state, whose
          // whole content is the words the customer is there to read — on a
          // 320-wide phone the notice landed squarely on top of "New Delhi →
          // Jaipur International Airport".
          child: MapsConfig.canRenderMap
              ? Stack(
                  children: <Widget>[
                    Positioned.fill(child: map),
                    if (offlineBanner != null)
                      Positioned(
                        left: FotgSpacing.x4,
                        right: FotgSpacing.x4,
                        top: FotgSpacing.x4,
                        child: offlineBanner,
                      ),
                    if (providerBanner != null)
                      Positioned(
                        left: FotgSpacing.x4,
                        right: FotgSpacing.x4,
                        bottom: FotgSpacing.x4,
                        child: providerBanner,
                      ),
                  ],
                )
              : Column(
                  children: <Widget>[
                    Expanded(child: map),
                    if (offlineBanner != null || providerBanner != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          FotgSpacing.x4,
                          FotgSpacing.x3,
                          FotgSpacing.x4,
                          0,
                        ),
                        child: Column(
                          children: <Widget>[
                            ?offlineBanner,
                            if (offlineBanner != null && providerBanner != null)
                              const SizedBox(height: FotgSpacing.x2),
                            ?providerBanner,
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        Expanded(
          flex: 5,
          child: _SummarySheet(
            state: state,
            trip: trip,
            routes: routes,
            selected: selected,
          ),
        ),
      ],
    );
  }
}

/// The numbers, the alternatives and the way onwards.
class _SummarySheet extends ConsumerWidget {
  const _SummarySheet({
    required this.state,
    required this.trip,
    required this.routes,
    required this.selected,
  });

  final RouteViewState state;
  final Trip trip;
  final List<TripRoute> routes;
  final TripRoute? selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AppStrings strings = AppStrings.of(context);
    final TripRoute? route = selected;

    if (route == null) return const SizedBox.shrink();

    final String? delay = JourneyMeasures.trafficDelay(
      route.trafficDelaySeconds,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.colorScheme.outline)),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          FotgSpacing.x5,
          FotgSpacing.x4,
          FotgSpacing.x5,
          FotgSpacing.x8,
        ),
        children: <Widget>[
          _Endpoints(trip: trip),
          const SizedBox(height: FotgSpacing.x4),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: _Measure(
                  label: strings.routeDurationLabel,
                  value: JourneyMeasures.duration(
                    route.effectiveDurationSeconds,
                  ),
                ),
              ),
              Expanded(
                child: _Measure(
                  label: strings.routeDistanceLabel,
                  value: JourneyMeasures.distance(route.distanceMeters),
                ),
              ),
              if (delay != null)
                Expanded(
                  child: _Measure(
                    label: strings.routeTrafficLabel,
                    value: delay,
                  ),
                ),
            ],
          ),

          const SizedBox(height: FotgSpacing.x3),
          Text(
            // Said plainly, because a travel time is not a pickup time and the
            // difference is the whole of what this product does.
            strings.routeTravelTimeOnly,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),

          if (route.calculatedAt != null) ...<Widget>[
            const SizedBox(height: FotgSpacing.x1),
            Text(
              // Nothing is refreshing the traffic figure, so nothing implies it
              // is live.
              '${JourneyMeasures.calculatedAgo(route.calculatedAt!)}'
              '${delay != null ? ' · ${strings.routeTrafficNotLive}' : ''}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],

          if (routes.length > 1) ...<Widget>[
            const SizedBox(height: FotgSpacing.x6),
            Text(
              strings.routeAlternativesTitle,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: FotgSpacing.x3),
            for (final TripRoute option in routes)
              RouteOptionCard(
                route: option,
                isSelected: option.id == route.id,
                comparedWith: state.routes!.recommended,
                isBusy: state.selectingRouteId == option.id,
                onSelect: () => ref
                    .read(routeControllerProvider.notifier)
                    .select(option.id),
              ),
          ],

          const SizedBox(height: FotgSpacing.x5),

          // The way onwards, and the primary action on this screen from Module
          // 07: a route exists to be eaten along. Offered only where the route
          // is genuinely usable — the discovery endpoint refuses anything else,
          // and a button that leads straight to a refusal is not an offer.
          PrimaryButton(
            label: strings.routeContinueCta,
            icon: Icons.restaurant_rounded,
            onPressed: () => context.push(Routes.tripRestaurantsPath(trip.id)),
          ),

          const SizedBox(height: FotgSpacing.x3),
          SecondaryButton(
            label: strings.routeRecalculate,
            isLoading: state.isCalculating,
            onPressed: state.isCalculating
                ? null
                : () => ref
                      .read(routeControllerProvider.notifier)
                      .calculate(refresh: true),
          ),
        ],
      ),
    );
  }
}

class _Endpoints extends StatelessWidget {
  const _Endpoints({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppStrings strings = AppStrings.of(context);

    return Semantics(
      container: true,
      label:
          '${strings.routeOriginMarker} ${trip.origin.shortName}, '
          '${strings.routeDestinationMarker} ${trip.destination.shortName}',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Column(
            children: <Widget>[
              Icon(
                Icons.trip_origin_rounded,
                size: 14,
                color: theme.colorScheme.secondary,
              ),
              Container(width: 2, height: 18, color: theme.colorScheme.outline),
              Icon(
                Icons.place_rounded,
                size: 16,
                color: theme.colorScheme.primary,
              ),
            ],
          ),
          const SizedBox(width: FotgSpacing.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  trip.origin.shortName,
                  style: theme.textTheme.bodyLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: FotgSpacing.x2),
                Text(
                  trip.destination.shortName,
                  style: theme.textTheme.bodyLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Measure extends StatelessWidget {
  const _Measure({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Semantics(
      label: '$label $value',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 2),
          Text(value, style: theme.textTheme.titleMedium, maxLines: 2),
        ],
      ),
    );
  }
}

/// Everything that is not a route: not calculated, no route, and every failure.
///
/// Each one says which of the several reasons applies and offers the action that
/// can actually help. A single "something went wrong" with a retry button would
/// be wrong for three of these — retrying a no-route answer spends a request to
/// be told the same thing.
class _RouteProblem extends ConsumerWidget {
  const _RouteProblem({required this.state, required this.trip});

  final RouteViewState state;
  final Trip? trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AppStrings strings = AppStrings.of(context);
    final RouteController controller = ref.read(
      routeControllerProvider.notifier,
    );

    if (state.isCalculating) {
      return _Busy(message: strings.routeCalculating);
    }

    final RouteStatus status = trip?.routeStatus ?? RouteStatus.notCalculated;

    final (
      IconData icon,
      String title,
      String body,
      Widget? action,
    ) = switch (state.failure) {
      RouteFailure.noRoute => (
        Icons.wrong_location_outlined,
        strings.routeNoRouteTitle,
        strings.routeNoRouteBody,
        null,
      ),
      RouteFailure.rateLimited => (
        Icons.hourglass_top_rounded,
        strings.routeRateLimitedTitle,
        strings.routeRateLimitedBody,
        SecondaryButton(
          label: strings.routeRetry,
          onPressed: () => controller.calculate(refresh: true),
        ),
      ),
      RouteFailure.timeout => (
        Icons.timer_off_outlined,
        strings.routeTimeoutTitle,
        strings.routeTimeoutBody,
        SecondaryButton(
          label: strings.routeRetry,
          onPressed: () => controller.calculate(refresh: true),
        ),
      ),
      RouteFailure.network => (
        Icons.cloud_off_rounded,
        strings.routeOfflineTitle,
        strings.routeOfflineBody,
        SecondaryButton(
          label: strings.routeRetry,
          onPressed: () => controller.calculate(),
        ),
      ),
      RouteFailure.stale => (
        Icons.update_rounded,
        strings.routeStaleTitle,
        strings.routeStaleBody,
        PrimaryButton(
          label: strings.routeRecalculate,
          onPressed: () => controller.calculate(refresh: true),
        ),
      ),
      RouteFailure.tripGone => (
        Icons.error_outline_rounded,
        strings.tripErrorGone,
        strings.routeFailedBody,
        null,
      ),
      // Provider unavailable, an unusable response, and anything a newer
      // server sends that this build has not been taught.
      RouteFailure.providerUnavailable ||
      RouteFailure.responseInvalid ||
      RouteFailure.unknown => (
        Icons.error_outline_rounded,
        strings.routeFailedTitle,
        strings.routeFailedBody,
        SecondaryButton(
          label: strings.routeRetry,
          onPressed: () => controller.calculate(refresh: true),
        ),
      ),
      // No failure at all: nothing has been worked out yet.
      null => (
        Icons.alt_route_rounded,
        status == RouteStatus.noRoute
            ? strings.routeNoRouteTitle
            : strings.routeNotCalculatedTitle,
        status == RouteStatus.noRoute
            ? strings.routeNoRouteBody
            : strings.routeNotCalculatedBody,
        status == RouteStatus.noRoute
            ? null
            : PrimaryButton(
                label: strings.routeCalculate,
                icon: Icons.alt_route_rounded,
                expand: false,
                onPressed: controller.calculate,
              ),
      ),
    };

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(FotgSpacing.x6),
        child: Semantics(
          liveRegion: true,
          container: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 40, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: FotgSpacing.x4),
              Text(
                title,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: FotgSpacing.x2),
              Text(
                body,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              if (trip != null) ...<Widget>[
                const SizedBox(height: FotgSpacing.x5),
                // The journey is still on screen, whatever went wrong with the
                // route. Losing it as well would be two failures.
                Text(
                  '${trip!.origin.shortName}  →  ${trip!.destination.shortName}',
                  style: theme.textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
              ],
              if (action != null) ...<Widget>[
                const SizedBox(height: FotgSpacing.x6),
                action,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Says what is happening, rather than spinning without explanation.
class _Busy extends StatelessWidget {
  const _Busy({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Center(
      child: Semantics(
        liveRegion: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const CircularProgressIndicator.adaptive(),
            const SizedBox(height: FotgSpacing.x4),
            Text(message, style: theme.textTheme.bodyLarge),
          ],
        ),
      ),
    );
  }
}

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

    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: FotgSpacing.x3,
          vertical: FotgSpacing.x2,
        ),
        decoration: BoxDecoration(
          color: isWarning
              ? theme.colorScheme.errorContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: FotgRadius.control,
        ),
        child: Row(
          children: <Widget>[
            Icon(
              icon,
              size: FotgSizing.iconSm,
              color: isWarning
                  ? theme.colorScheme.onErrorContainer
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: FotgSpacing.x2),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isWarning
                      ? theme.colorScheme.onErrorContainer
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Content-shaped, so nothing jumps when the route lands.
class _RouteSkeleton extends StatelessWidget {
  const _RouteSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        const Expanded(flex: 4, child: AppSkeleton(height: double.infinity)),
        Expanded(
          flex: 5,
          child: Padding(
            padding: const EdgeInsets.all(FotgSpacing.x5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const <Widget>[
                AppSkeleton(width: 200, height: 18),
                SizedBox(height: FotgSpacing.x3),
                AppSkeleton(width: 160, height: 18),
                SizedBox(height: FotgSpacing.x6),
                AppSkeleton(height: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
