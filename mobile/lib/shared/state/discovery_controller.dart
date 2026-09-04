import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_error_code.dart';
import '../../core/network/api_exception.dart';
import '../../domain/models/discovered_restaurant.dart';
import '../../domain/repositories/discovery_repository.dart';
import 'providers.dart';

/// Why the discovery screen has nothing to show.
///
/// Separate cases because the customer's next move differs for each: a route
/// that is not ready sends them back to the route screen, a rate limit asks them
/// to wait, and an outage asks them to try again. One "something went wrong"
/// would offer the same useless button to all three.
enum DiscoveryFailure {
  /// The request never left the device.
  network,

  /// The trip has no usable selected route. Not an error the customer caused,
  /// and not one a retry fixes — they need the route screen.
  routeNotReady,

  /// The trip is gone, or was never this customer's.
  tripGone,

  /// Too many discovery requests. Retrying immediately will not work.
  rateLimited,

  /// The server could not complete the search.
  discoveryFailed,

  /// Ours, and unexplained.
  serverError,

  unauthorized,

  unknown,
}

/// How the results are being presented.
///
/// Held here rather than in the widget so that switching between them cannot
/// rebuild the controller and re-run the search. A customer flicking between map
/// and list is not asking for new restaurants.
enum DiscoveryView { map, list }

/// What the discovery screen is showing.
class DiscoveryState {
  const DiscoveryState({
    this.discovery,
    this.isLoading = false,
    this.failure,
    this.isOffline = false,
    this.view = DiscoveryView.list,
    this.selectedRestaurantId,
  });

  /// What the server last told us. Kept through a failure, so a customer who
  /// loses signal keeps the restaurants they already had.
  final RestaurantDiscovery? discovery;

  final bool isLoading;
  final DiscoveryFailure? failure;

  /// The last search failed for want of a network, and there is something
  /// stored. The screen says so rather than implying availability is current.
  final bool isOffline;

  final DiscoveryView view;

  /// The restaurant whose marker and card are highlighted. One value drives
  /// both, which is what keeps them synchronised: there is no second place for
  /// the map's idea of "selected" to disagree with the list's.
  final String? selectedRestaurantId;

  List<DiscoveredRestaurant> get restaurants =>
      discovery?.restaurants ?? const <DiscoveredRestaurant>[];

  bool get hasResults => restaurants.isNotEmpty;

  /// There are restaurants and none can take an order right now.
  bool get isClosedOnly => discovery?.closedOnly ?? false;

  bool get isEmptyResult =>
      discovery != null && restaurants.isEmpty && failure == null;

  DiscoveredRestaurant? get selected {
    final String? id = selectedRestaurantId;
    if (id == null) return null;

    for (final DiscoveredRestaurant r in restaurants) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// Whether offering "Try again" would be honest.
  bool get isRetryable =>
      failure != null &&
      failure != DiscoveryFailure.routeNotReady &&
      failure != DiscoveryFailure.tripGone &&
      failure != DiscoveryFailure.unauthorized;

  DiscoveryState copyWith({
    RestaurantDiscovery? discovery,
    bool? isLoading,
    DiscoveryFailure? failure,
    bool clearFailure = false,
    bool? isOffline,
    DiscoveryView? view,
    String? selectedRestaurantId,
    bool clearSelection = false,
  }) => DiscoveryState(
    discovery: discovery ?? this.discovery,
    isLoading: isLoading ?? this.isLoading,
    failure: clearFailure ? null : (failure ?? this.failure),
    isOffline: isOffline ?? this.isOffline,
    view: view ?? this.view,
    selectedRestaurantId: clearSelection
        ? null
        : (selectedRestaurantId ?? this.selectedRestaurantId),
  );
}

/// The discovery screen's state.
///
/// The rule this class exists to enforce, and it is the same one Module 06's
/// controller enforces for the same reason: **a rebuild never costs money.**
/// Discovery is the most expensive endpoint in the application — a corridor
/// query plus up to a dozen billed routing calls — and it runs once per trip
/// per screen open. Not once per rebuild, not when the map is panned, not when
/// the customer switches to the list and back.
class DiscoveryController extends Notifier<DiscoveryState> {
  String? _tripId;

  bool _disposed = false;

  /// Guards against two searches in flight at once — a rapid double tap on the
  /// CTA, or a retry pressed twice.
  bool _inFlight = false;

  late final DiscoveryRepository _discovery;

  @override
  DiscoveryState build() {
    _discovery = ref.read(discoveryRepositoryProvider);
    ref.onDispose(() => _disposed = true);

    return const DiscoveryState();
  }

  /// Opens the screen for a trip.
  ///
  /// Idempotent, which is what makes it safe to call from a widget's first
  /// frame: calling it again for the same trip with results already in hand
  /// does nothing at all.
  Future<void> open(String tripId) async {
    if (_tripId == tripId && (state.hasResults || state.isLoading)) {
      return;
    }

    // A trip that previously returned an empty result is not searched again on
    // a rebuild either — an empty answer is an answer, and it cost as much to
    // produce as a full one.
    if (_tripId == tripId && state.discovery != null && state.failure == null) {
      return;
    }

    _tripId = tripId;

    await _search(initial: true);
  }

  /// An explicit "try again". Always searches.
  Future<void> retry() => _search(initial: false);

  Future<void> _search({required bool initial}) async {
    final String? tripId = _tripId;

    if (tripId == null || _inFlight) return;

    _inFlight = true;

    state = state.copyWith(
      isLoading: true,
      clearFailure: true,
      // A retry keeps whatever is on screen underneath the skeleton; a first
      // open has nothing to keep.
      discovery: initial ? null : state.discovery,
    );

    try {
      final RestaurantDiscovery found = await _discovery.discover(tripId);

      if (_disposed) return;

      state = state.copyWith(
        discovery: found,
        isLoading: false,
        clearFailure: true,
        isOffline: false,
        // Any previous selection belonged to a previous result set.
        clearSelection: true,
      );
    } on ApiException catch (error) {
      if (_disposed) return;

      state = state.copyWith(
        isLoading: false,
        failure: _failureFor(error),
        // Losing the restaurants a customer already has because a refresh
        // failed punishes them for our outage.
        isOffline: error.code == ApiErrorCode.network && state.hasResults,
      );
    } finally {
      _inFlight = false;
    }
  }

  /// Switches presentation. Never re-searches.
  void showView(DiscoveryView view) {
    if (state.view == view) return;

    state = state.copyWith(view: view);
  }

  /// Selects a restaurant, from either the map or the list.
  ///
  /// One method for both, and one field behind it. Tapping a marker and tapping
  /// a card are the same act, and giving them separate state is how the two
  /// come to disagree about which restaurant is selected.
  void selectRestaurant(String? id) {
    if (id == null) {
      state = state.copyWith(clearSelection: true);
      return;
    }

    // Tapping the selected one again clears it, so a customer can get back to
    // the whole-route view without hunting for a close button.
    if (state.selectedRestaurantId == id) {
      state = state.copyWith(clearSelection: true);
      return;
    }

    state = state.copyWith(selectedRestaurantId: id);
  }

  DiscoveryFailure _failureFor(ApiException error) => switch (error.code) {
    ApiErrorCode.network => DiscoveryFailure.network,
    ApiErrorCode.routeNotReady ||
    ApiErrorCode.routeStale ||
    ApiErrorCode.routeNotFound => DiscoveryFailure.routeNotReady,
    ApiErrorCode.tripNotFound => DiscoveryFailure.tripGone,
    ApiErrorCode.discoveryRateLimited ||
    ApiErrorCode.rateLimited => DiscoveryFailure.rateLimited,
    ApiErrorCode.discoveryFailed ||
    ApiErrorCode.restaurantDataUnavailable ||
    ApiErrorCode.detourProviderUnavailable => DiscoveryFailure.discoveryFailed,
    ApiErrorCode.unauthenticated => DiscoveryFailure.unauthorized,
    ApiErrorCode.serverError => DiscoveryFailure.serverError,
    _ => DiscoveryFailure.unknown,
  };
}

/// Auto-disposed: these results belong to one journey, and closing the screen
/// should take them with it rather than leaving one customer's stops in memory
/// behind the next screen.
final discoveryControllerProvider =
    NotifierProvider.autoDispose<DiscoveryController, DiscoveryState>(
      DiscoveryController.new,
    );
