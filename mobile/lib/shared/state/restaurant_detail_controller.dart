import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_error_code.dart';
import '../../core/network/api_exception.dart';
import '../../domain/models/discovered_restaurant.dart';
import '../../domain/models/restaurant_detail.dart';
import '../../domain/repositories/restaurant_repository.dart';
import 'providers.dart';

/// Why the restaurant detail screen has nothing to show.
///
/// Separate cases because the customer's next move differs for each: a
/// restaurant that has been withdrawn sends them back to the list, one that is
/// on a different road tells them so, and an outage asks them to try again.
enum RestaurantDetailFailure {
  /// The request never left the device.
  network,

  /// No such restaurant, or not one this customer may see. The two are one
  /// case on purpose — telling them apart is how a prober maps the platform.
  notFound,

  /// It was on the route a minute ago and has since been suspended, disabled
  /// or closed for good.
  withdrawn,

  /// Real, trading, and not on this journey.
  outsideRoute,

  /// The trip has no usable selected route.
  routeNotReady,

  /// The trip is gone, or was never this customer's.
  tripGone,

  rateLimited,

  unauthorized,

  /// Ours, and unexplained.
  serverError,

  unknown,
}

/// What the restaurant detail screen is showing.
class RestaurantDetailState {
  const RestaurantDetailState({
    this.preview,
    this.detail,
    this.isLoading = false,
    this.isRefreshing = false,
    this.failure,
    this.isOffline = false,
    this.hoursExpanded = false,
    this.galleryIndex = 0,
  });

  /// What the discovery card already knew, handed over at the moment of the
  /// tap so the screen has a name and a detour to draw immediately.
  ///
  /// Never treated as authoritative and never left on screen alone: the server
  /// is asked, and what it says replaces this. A preview that stayed would go
  /// on claiming a restaurant is open long after it stopped being.
  final DiscoveredRestaurant? preview;

  final RestaurantDetail? detail;

  final bool isLoading;

  /// A pull-to-refresh over content already on screen.
  final bool isRefreshing;

  final RestaurantDetailFailure? failure;

  /// The last load failed for want of a network and there is something stored.
  /// The screen says so, and says how old it is, rather than implying the open
  /// sign is live.
  final bool isOffline;

  final bool hoursExpanded;
  final int galleryIndex;

  bool get hasDetail => detail != null;

  /// Enough to draw a screen with — either the real thing or the card's
  /// preview underneath a skeleton.
  bool get hasSomething => detail != null || preview != null;

  /// The name to show in the app bar, from whichever half has arrived.
  String get name => detail?.name ?? preview?.name ?? '';

  /// Whether offering "Try again" would be honest.
  ///
  /// A withdrawn restaurant is not retryable: it will not come back because
  /// the customer pressed a button, and offering the button implies it might.
  bool get isRetryable =>
      failure != null &&
      failure != RestaurantDetailFailure.notFound &&
      failure != RestaurantDetailFailure.withdrawn &&
      failure != RestaurantDetailFailure.outsideRoute &&
      failure != RestaurantDetailFailure.tripGone &&
      failure != RestaurantDetailFailure.unauthorized;

  RestaurantDetailState copyWith({
    DiscoveredRestaurant? preview,
    RestaurantDetail? detail,
    bool clearDetail = false,
    bool? isLoading,
    bool? isRefreshing,
    RestaurantDetailFailure? failure,
    bool clearFailure = false,
    bool? isOffline,
    bool? hoursExpanded,
    int? galleryIndex,
  }) => RestaurantDetailState(
    preview: preview ?? this.preview,
    detail: clearDetail ? null : (detail ?? this.detail),
    isLoading: isLoading ?? this.isLoading,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    failure: clearFailure ? null : (failure ?? this.failure),
    isOffline: isOffline ?? this.isOffline,
    hoursExpanded: hoursExpanded ?? this.hoursExpanded,
    galleryIndex: galleryIndex ?? this.galleryIndex,
  );
}

/// The restaurant detail screen's state.
///
/// The rule this class exists to enforce: **the newest request wins, and an
/// older one never overwrites it.** A customer tapping through three
/// restaurants generates three requests that can return in any order, and
/// without the generation check below the slowest one lands last — putting one
/// restaurant's photographs under another restaurant's name.
///
/// The second rule is quieter and matters as much: opening this screen calls no
/// routing provider. The route figures come from the discovery result Module 07
/// already cached, which is a property of the endpoint rather than of this
/// class — but it is why tapping through a list is free.
class RestaurantDetailController extends Notifier<RestaurantDetailState> {
  String? _tripId;
  String? _restaurantId;

  bool _disposed = false;

  /// Which request the state belongs to. Only the newest may write.
  int _generation = 0;

  late final RestaurantRepository _restaurants;

  @override
  RestaurantDetailState build() {
    _restaurants = ref.read(restaurantRepositoryProvider);
    ref.onDispose(() => _disposed = true);

    return const RestaurantDetailState();
  }

  /// Opens the screen for one restaurant on one trip.
  ///
  /// [preview] is what the card already knew. It is drawn immediately so the
  /// transition has something in it, and it is replaced the moment the server
  /// answers.
  Future<void> open({
    required String tripId,
    required String restaurantId,
    DiscoveredRestaurant? preview,
  }) async {
    final bool sameRestaurant =
        _tripId == tripId && _restaurantId == restaurantId;

    if (sameRestaurant && (state.hasDetail || state.isLoading)) {
      return;
    }

    _tripId = tripId;
    _restaurantId = restaurantId;

    // A different restaurant means everything on screen belongs to the
    // previous one. Clearing it is what stops the old photographs sitting
    // under the new name while the request is in flight.
    state = RestaurantDetailState(preview: preview, isLoading: true);

    await _load(refreshing: false);
  }

  /// An explicit "try again".
  Future<void> retry() => _load(refreshing: false);

  /// Pull to refresh. Keeps what is on screen underneath.
  Future<void> refresh() => _load(refreshing: true);

  void toggleHours() =>
      state = state.copyWith(hoursExpanded: !state.hoursExpanded);

  void galleryMovedTo(int index) => state = state.copyWith(galleryIndex: index);

  Future<void> _load({required bool refreshing}) async {
    final String? tripId = _tripId;
    final String? restaurantId = _restaurantId;

    if (tripId == null || restaurantId == null) return;

    final int generation = ++_generation;

    state = state.copyWith(
      isLoading: !refreshing && !state.hasDetail,
      isRefreshing: refreshing,
      clearFailure: true,
    );

    try {
      final RestaurantDetail detail = await _restaurants.detail(
        tripId: tripId,
        restaurantId: restaurantId,
      );

      // A slower earlier request finishing after a later one. Its answer is
      // about a restaurant the customer has already navigated away from.
      if (_disposed || generation != _generation) return;

      state = state.copyWith(
        detail: detail,
        isLoading: false,
        isRefreshing: false,
        clearFailure: true,
        isOffline: false,
      );
    } on ApiException catch (error) {
      if (_disposed || generation != _generation) return;

      final RestaurantDetailFailure failure = _failureFor(error);

      state = state.copyWith(
        isLoading: false,
        isRefreshing: false,
        failure: failure,
        // Keeping what a customer already has because a refresh failed is
        // kinder than punishing them for our outage — but only when the
        // restaurant is still theirs to see. A withdrawn one loses its
        // content, because leaving it up would present a suspended business
        // as though it were trading.
        clearDetail:
            failure == RestaurantDetailFailure.withdrawn ||
            failure == RestaurantDetailFailure.notFound,
        isOffline: error.code == ApiErrorCode.network && state.hasDetail,
      );
    } catch (_) {
      if (_disposed || generation != _generation) return;

      // A 200 whose body could not be read. Ours, and unexplained.
      state = state.copyWith(
        isLoading: false,
        isRefreshing: false,
        failure: RestaurantDetailFailure.serverError,
      );
    }
  }

  RestaurantDetailFailure _failureFor(ApiException error) =>
      switch (error.code) {
        ApiErrorCode.network => RestaurantDetailFailure.network,
        ApiErrorCode.restaurantNotFound ||
        ApiErrorCode.notFound => RestaurantDetailFailure.notFound,
        ApiErrorCode.restaurantUnavailable => RestaurantDetailFailure.withdrawn,
        ApiErrorCode.restaurantOutsideRoute =>
          RestaurantDetailFailure.outsideRoute,
        ApiErrorCode.routeNotReady ||
        ApiErrorCode.routeStale ||
        ApiErrorCode.routeNotFound => RestaurantDetailFailure.routeNotReady,
        ApiErrorCode.tripNotFound => RestaurantDetailFailure.tripGone,
        ApiErrorCode.discoveryRateLimited ||
        ApiErrorCode.rateLimited => RestaurantDetailFailure.rateLimited,
        ApiErrorCode.unauthenticated => RestaurantDetailFailure.unauthorized,
        ApiErrorCode.serverError ||
        ApiErrorCode.detailLoadFailed ||
        ApiErrorCode.discoveryFailed => RestaurantDetailFailure.serverError,
        _ => RestaurantDetailFailure.unknown,
      };
}

/// Auto-disposed: one restaurant's detail belongs to one visit to one screen,
/// and closing it should take the photographs with it rather than leaving one
/// customer's route context in memory behind the next.
final restaurantDetailControllerProvider =
    NotifierProvider.autoDispose<
      RestaurantDetailController,
      RestaurantDetailState
    >(RestaurantDetailController.new);
