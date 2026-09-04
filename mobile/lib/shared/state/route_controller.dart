import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_error_code.dart';
import '../../core/network/api_exception.dart';
import '../../domain/models/trip_route.dart';
import '../../domain/repositories/route_repository.dart';
import 'providers.dart';
import 'trips_controller.dart';

/// Why the route screen has nothing to show.
///
/// Six cases rather than one, because the customer's next move differs for each
/// and a single "something went wrong" would offer the same useless button to
/// all of them.
enum RouteFailure {
  /// The request never left the device.
  network,

  /// The provider was unreachable or refused us. Retrying may work.
  providerUnavailable,

  /// The provider is throttling. Retrying *immediately* will not work.
  rateLimited,

  /// The provider took too long.
  timeout,

  /// The provider looked and there is no driving route between these places.
  /// Retrying will be told the same thing.
  noRoute,

  /// The provider answered and we could not use the answer. Ours, not theirs.
  responseInvalid,

  /// The trip is gone, or was never this customer's.
  tripGone,

  /// The endpoints moved since this route was worked out.
  stale,

  unknown,
}

/// What the route screen is showing.
class RouteViewState {
  const RouteViewState({
    this.routes,
    this.isLoading = false,
    this.isCalculating = false,
    this.selectingRouteId,
    this.failure,
    this.isOffline = false,
  });

  /// What the server last told us. Kept through a failure, so a customer who
  /// loses signal keeps the route they already had.
  final TripRoutes? routes;

  /// The initial read. Distinct from [isCalculating] because one is a database
  /// lookup and the other may be a provider call — they deserve different words.
  final bool isLoading;

  final bool isCalculating;

  /// The route whose selection is in flight, so its card can show it.
  final String? selectingRouteId;

  final RouteFailure? failure;

  /// The last operation failed for want of a network, and there is something
  /// stored to show. The screen says so rather than implying the traffic figure
  /// on screen is current.
  final bool isOffline;

  bool get hasRoutes => routes?.hasRoutes ?? false;

  TripRoute? get selected => routes?.selected;

  /// Whether offering "Try again" would be honest.
  bool get isRetryable =>
      failure != null &&
      failure != RouteFailure.noRoute &&
      failure != RouteFailure.tripGone;

  RouteViewState copyWith({
    TripRoutes? routes,
    bool? isLoading,
    bool? isCalculating,
    String? selectingRouteId,
    bool clearSelecting = false,
    RouteFailure? failure,
    bool clearFailure = false,
    bool? isOffline,
  }) => RouteViewState(
    routes: routes ?? this.routes,
    isLoading: isLoading ?? this.isLoading,
    isCalculating: isCalculating ?? this.isCalculating,
    selectingRouteId: clearSelecting
        ? null
        : (selectingRouteId ?? this.selectingRouteId),
    failure: clearFailure ? null : (failure ?? this.failure),
    isOffline: isOffline ?? this.isOffline,
  );
}

/// The route screen's state.
///
/// The rule this class exists to enforce: **a rebuild never costs money.**
/// Opening the screen reads what the server has; a provider call happens only
/// when there is nothing calculated yet, and then exactly once, or when the
/// customer explicitly asks for it. Riverpod rebuilds a widget for all sorts of
/// reasons — a theme change, a keyboard, a parent's state — and a calculation
/// wired to `build()` would bill for every one of them.
class RouteController extends Notifier<RouteViewState> {
  /// Set once, by the screen, on its first frame.
  String? _tripId;

  /// Whether the automatic first calculation has been attempted for this trip.
  /// A screen open is one attempt, not one per rebuild.
  bool _autoCalculationAttempted = false;

  bool _disposed = false;

  late final RouteRepository _routes;

  /// Incremented on every selection, so a slow answer to an abandoned tap
  /// cannot land on top of a newer one.
  int _selectionGeneration = 0;

  @override
  RouteViewState build() {
    _routes = ref.read(routeRepositoryProvider);
    ref.onDispose(() => _disposed = true);

    return const RouteViewState();
  }

  /// Opens the screen for a trip.
  ///
  /// Idempotent: calling it again for the same trip does nothing, which is what
  /// makes it safe to call from a widget's first frame.
  Future<void> open(String tripId, {bool calculateIfMissing = true}) async {
    if (_tripId == tripId && (state.hasRoutes || state.isLoading)) {
      return;
    }

    _tripId = tripId;
    _autoCalculationAttempted = false;
    state = const RouteViewState(isLoading: true);

    final bool loaded = await _read();

    if (_disposed || !loaded) return;

    // Calculated only when there is nothing to show and the server says asking
    // again could help. A trip whose provider already answered "no route" is
    // not asked twice.
    final bool shouldCalculate =
        calculateIfMissing &&
        !state.hasRoutes &&
        (state.routes?.trip.routeStatus.isRetryable ?? false);

    if (shouldCalculate && !_autoCalculationAttempted) {
      _autoCalculationAttempted = true;
      await calculate();
    }
  }

  /// Reads what the server has. Never calculates.
  Future<bool> _read() async {
    final String? tripId = _tripId;
    if (tripId == null) return false;

    try {
      final TripRoutes routes = await _routes.routes(tripId);

      if (_disposed) return false;

      state = state.copyWith(
        routes: routes,
        isLoading: false,
        clearFailure: true,
        isOffline: false,
      );

      return true;
    } on ApiException catch (error) {
      if (_disposed) return false;

      state = state.copyWith(
        isLoading: false,
        failure: _failureFor(error),
        isOffline: error.code == ApiErrorCode.network && state.hasRoutes,
      );

      return false;
    }
  }

  /// Asks the server to work the route out.
  ///
  /// [refresh] forces a new provider call past the freshness window — for an
  /// explicit "recalculate", never for a screen open.
  Future<void> calculate({bool refresh = false}) async {
    final String? tripId = _tripId;
    if (tripId == null || state.isCalculating) {
      // A second tap while one is in flight does nothing. The server would
      // serialise them anyway; not sending the second is cheaper still.
      return;
    }

    state = state.copyWith(isCalculating: true, clearFailure: true);

    try {
      final TripRoutes routes = await _routes.calculate(
        tripId,
        refresh: refresh,
      );

      if (_disposed) return;

      state = state.copyWith(
        routes: routes,
        isCalculating: false,
        clearFailure: true,
        isOffline: false,
      );

      // The trips list and the home card carry the route summary, so they are
      // now out of date. Read through notifiers taken here rather than through
      // `ref` after the await, which would throw if the screen has closed.
      _refreshTripSurfaces();
    } on ApiException catch (error) {
      if (_disposed) return;

      state = state.copyWith(
        isCalculating: false,
        failure: _failureFor(error),
        // Whatever was already on screen stays there. Losing a working route
        // because a refresh failed punishes the customer for our outage.
        isOffline: error.code == ApiErrorCode.network && state.hasRoutes,
      );
    }
  }

  /// Chooses one of the calculated routes.
  ///
  /// The server is authoritative and its answer replaces the whole set, so
  /// nothing is applied optimistically: a selection the server refused must not
  /// linger on screen looking accepted.
  Future<void> select(String routeId) async {
    final String? tripId = _tripId;
    if (tripId == null) return;

    final int generation = ++_selectionGeneration;

    state = state.copyWith(selectingRouteId: routeId, clearFailure: true);

    try {
      final TripRoutes routes = await _routes.select(tripId, routeId);

      // A slow answer to a tap the customer has already changed their mind
      // about must not land on top of the newer one.
      if (_disposed || generation != _selectionGeneration) return;

      state = state.copyWith(
        routes: routes,
        clearSelecting: true,
        clearFailure: true,
      );

      _refreshTripSurfaces();
    } on ApiException catch (error) {
      if (_disposed || generation != _selectionGeneration) return;

      state = state.copyWith(clearSelecting: true, failure: _failureFor(error));
    }
  }

  /// Re-reads the surfaces that carry a route summary.
  ///
  /// Best-effort, and deliberately unable to fail the thing that called it. The
  /// customer's route has already been calculated or selected and the server has
  /// already agreed; a stale trips list is a cosmetic problem on a screen nobody
  /// is looking at, and turning it into a failed selection would undo work that
  /// actually succeeded.
  void _refreshTripSurfaces() {
    if (_disposed) return;

    try {
      ref.read(tripsControllerProvider.notifier).refreshQuietly();
      ref.read(currentTripControllerProvider.notifier).refreshQuietly();
    } catch (_) {
      // Includes the case where those providers have already been disposed
      // because the customer left the tab.
    }
  }

  RouteFailure _failureFor(ApiException error) => switch (error.code) {
    ApiErrorCode.network => RouteFailure.network,
    ApiErrorCode.routeNoRouteFound => RouteFailure.noRoute,
    ApiErrorCode.routeProviderRateLimited => RouteFailure.rateLimited,
    ApiErrorCode.routeTimeout => RouteFailure.timeout,
    ApiErrorCode.routeProviderUnavailable ||
    ApiErrorCode.dependencyUnavailable => RouteFailure.providerUnavailable,
    ApiErrorCode.routeResponseInvalid => RouteFailure.responseInvalid,
    ApiErrorCode.routeStale => RouteFailure.stale,
    ApiErrorCode.tripNotFound ||
    ApiErrorCode.routeNotFound => RouteFailure.tripGone,
    _ => RouteFailure.unknown,
  };
}

/// Auto-disposed: the route screen is one trip's, and closing it should take
/// the geometry with it rather than leaving a stranger's journey in memory
/// behind the next screen.
final routeControllerProvider =
    NotifierProvider.autoDispose<RouteController, RouteViewState>(
      RouteController.new,
    );
