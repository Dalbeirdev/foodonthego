import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_error_code.dart';
import '../../core/network/api_exception.dart';
import '../../domain/models/discovered_restaurant.dart';
import '../../domain/models/discovery_facets.dart';
import '../../domain/models/discovery_query.dart';
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

  /// The server refused the filters. A bug in this build rather than in the
  /// customer's typing — there is no filter combination the sheet can produce
  /// that the server should reject.
  filtersRejected,

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
    this.isRefining = false,
    this.isLoadingMore = false,
    this.failure,
    this.isOffline = false,
    this.view = DiscoveryView.list,
    this.selectedRestaurantId,
    this.query = DiscoveryQuery.unfiltered,
    this.searchText = '',
  });

  /// What the server last told us. Kept through a failure, so a customer who
  /// loses signal keeps the restaurants they already had.
  final RestaurantDiscovery? discovery;

  /// The first load of the screen, with nothing to show underneath.
  final bool isLoading;

  /// A filter, a search or a sort is being applied over results already on
  /// screen. A different thing from [isLoading]: the old list stays visible and
  /// dimmed rather than being replaced by a skeleton, because a list that
  /// vanishes on every keystroke is unreadable.
  final bool isRefining;

  /// Another page is on its way.
  final bool isLoadingMore;

  final DiscoveryFailure? failure;

  /// The last search failed for want of a network, and there is something
  /// stored. The screen says so rather than implying availability is current.
  final bool isOffline;

  final DiscoveryView view;

  /// The restaurant whose marker and card are highlighted. One value drives
  /// both, which is what keeps them synchronised: there is no second place for
  /// the map's idea of "selected" to disagree with the list's.
  final String? selectedRestaurantId;

  /// What has been asked of the server, and what the chips describe.
  final DiscoveryQuery query;

  /// What is in the search field right now.
  ///
  /// Separate from `query.search`, which is what the server was last asked. The
  /// two differ for as long as the debounce runs, and conflating them would
  /// either lose keystrokes or send a request per character.
  final String searchText;

  List<DiscoveredRestaurant> get restaurants =>
      discovery?.restaurants ?? const <DiscoveredRestaurant>[];

  bool get hasResults => restaurants.isNotEmpty;

  /// The options this route can offer.
  DiscoveryFacets get facets => discovery?.facets ?? const DiscoveryFacets();

  /// There are restaurants and none can take an order right now.
  bool get isClosedOnly => discovery?.closedOnly ?? false;

  bool get isEmptyResult =>
      discovery != null && restaurants.isEmpty && failure == null;

  /// The two empty screens, told apart.
  ///
  /// "Nothing on this road" is our problem and offers a way back to the
  /// journey; "your filters hid everything" is the customer's and offers a way
  /// to undo them. Showing the first when it is the second tells a customer
  /// there is no food on a road that has six restaurants on it.
  bool get isFilteredEmpty =>
      isEmptyResult && (discovery?.isFilteredEmpty ?? false);

  bool get isSearchEmpty => isFilteredEmpty && query.hasSearch;

  /// How many match, across every page.
  int get totalCount => discovery?.total ?? restaurants.length;

  /// How many are on the route before the customer narrowed it.
  int get eligibleCount => discovery?.eligibleTotal ?? totalCount;

  bool get hasMore => discovery?.hasMore ?? false;

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
    bool? isRefining,
    bool? isLoadingMore,
    DiscoveryFailure? failure,
    bool clearFailure = false,
    bool? isOffline,
    DiscoveryView? view,
    String? selectedRestaurantId,
    bool clearSelection = false,
    DiscoveryQuery? query,
    String? searchText,
  }) => DiscoveryState(
    discovery: discovery ?? this.discovery,
    isLoading: isLoading ?? this.isLoading,
    isRefining: isRefining ?? this.isRefining,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    failure: clearFailure ? null : (failure ?? this.failure),
    isOffline: isOffline ?? this.isOffline,
    view: view ?? this.view,
    selectedRestaurantId: clearSelection
        ? null
        : (selectedRestaurantId ?? this.selectedRestaurantId),
    query: query ?? this.query,
    searchText: searchText ?? this.searchText,
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
///
/// Module 08 added filtering, which looks like a threat to that rule and is
/// not. A filtered request reaches the same cached corridor on the server and
/// calls no provider; what it costs is one HTTP round trip. The debounce below
/// is about that round trip and about the rate limit, not about the routing
/// bill.
class DiscoveryController extends Notifier<DiscoveryState> {
  /// How long the customer must stop typing before the search is sent.
  ///
  /// Long enough that a word typed at speed is one request rather than seven,
  /// short enough that the list feels like it is following along. Measured
  /// against the rate limit: the discovery endpoint allows a small number of
  /// calls a minute, and a request per keystroke exhausts it inside one word.
  static const Duration searchDebounce = Duration(milliseconds: 350);

  String? _tripId;

  bool _disposed = false;

  /// Guards against two searches in flight at once — a rapid double tap on the
  /// CTA, or a retry pressed twice.
  bool _inFlight = false;

  /// Which request the state belongs to.
  ///
  /// Every request takes a number; only the newest one is allowed to write. Two
  /// searches sent a second apart can return in either order, and without this
  /// the slower one lands last and puts the results for "spi" under the word
  /// "spice".
  int _generation = 0;

  Timer? _debounce;

  late final DiscoveryRepository _discovery;

  @override
  DiscoveryState build() {
    _discovery = ref.read(discoveryRepositoryProvider);
    ref.onDispose(() {
      _disposed = true;
      _debounce?.cancel();
    });

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

  // --- search --------------------------------------------------------------

  /// A keystroke.
  ///
  /// The field updates immediately and the request waits. Anything shorter than
  /// [DiscoveryQuery.minSearchLength] is not a search — it matches most of the
  /// corridor — so it clears the term rather than sending it.
  void searchChanged(String text) {
    if (state.searchText == text) return;

    state = state.copyWith(searchText: text);

    _debounce?.cancel();
    _debounce = Timer(searchDebounce, () => _applySearch(text));
  }

  /// The customer pressed the search key. Skips the debounce.
  void submitSearch() {
    _debounce?.cancel();
    _applySearch(state.searchText);
  }

  /// The clear button in the field.
  void clearSearch() {
    _debounce?.cancel();

    if (!state.query.hasSearch && state.searchText.isEmpty) {
      state = state.copyWith(searchText: '');
      return;
    }

    state = state.copyWith(searchText: '');
    _apply(state.query.copyWith(clearSearch: true));
  }

  void _applySearch(String text) {
    final String trimmed = text.trim();
    final bool longEnough = trimmed.length >= DiscoveryQuery.minSearchLength;

    _apply(
      longEnough
          ? state.query.copyWith(search: trimmed)
          : state.query.copyWith(clearSearch: true),
    );
  }

  // --- filters and sort ----------------------------------------------------

  /// Applies a whole query at once — what the filter sheet's "Apply" does.
  ///
  /// The sheet edits a draft and hands the finished thing over. Applying each
  /// toggle as it happened would send a request per checkbox and re-sort the
  /// list under the customer's finger while they were still choosing.
  void applyQuery(DiscoveryQuery query) => _apply(query);

  void sortBy(DiscoverySort sort) => _apply(state.query.copyWith(sort: sort));

  /// Removes one chip.
  void removeCuisine(String slug) => _apply(
    state.query.copyWith(cuisines: _without(state.query.cuisines, slug)),
  );

  void removeFacility(String slug) => _apply(
    state.query.copyWith(facilities: _without(state.query.facilities, slug)),
  );

  void removePriceLevel(int level) => _apply(
    state.query.copyWith(priceLevels: _without(state.query.priceLevels, level)),
  );

  void removeAvailability() =>
      _apply(state.query.copyWith(clearAvailability: true));

  void removeMaxDetour() => _apply(state.query.copyWith(clearMaxDetour: true));

  void removeMaxDistanceAhead() =>
      _apply(state.query.copyWith(clearMaxDistanceAhead: true));

  void removeMinRating() => _apply(state.query.copyWith(clearMinRating: true));

  /// "Clear all". Keeps the search — the chips are not an undo for the text the
  /// customer is still looking at.
  void clearFilters() => _apply(state.query.cleared());

  /// Everything back to how the screen opened.
  void resetAll() {
    _debounce?.cancel();
    state = state.copyWith(searchText: '');
    _apply(DiscoveryQuery.unfiltered);
  }

  static Set<T> _without<T>(Set<T> values, T value) =>
      Set<T>.of(values)..remove(value);

  void _apply(DiscoveryQuery query) {
    // Nothing changed — a chip removed twice, or "Apply" on an untouched sheet.
    // Spending a request to receive the list already on screen is a request
    // against the rate limit for no result.
    if (query == state.query) return;

    state = state.copyWith(query: query);

    unawaited(_search(initial: false, refining: true));
  }

  // --- pagination ----------------------------------------------------------

  /// Fetches the next page and appends it.
  ///
  /// Appends rather than replaces: the customer is reading a list, and taking
  /// away what they have already scrolled past to show them the next twenty is
  /// not paging, it is losing their place.
  Future<void> loadMore() async {
    if (!state.hasMore || state.isLoadingMore || _inFlight) return;

    final String? tripId = _tripId;
    if (tripId == null) return;

    final DiscoveryQuery next = state.query.copyWith(
      page: state.query.page + 1,
    );

    _inFlight = true;
    final int generation = ++_generation;

    state = state.copyWith(isLoadingMore: true);

    try {
      final RestaurantDiscovery page = await _discovery.discover(
        tripId,
        query: next,
      );

      if (_disposed || generation != _generation) return;

      final RestaurantDiscovery? current = state.discovery;

      state = state.copyWith(
        discovery: current == null
            ? page
            : page.appendedTo(current.restaurants),
        query: next,
        isLoadingMore: false,
        clearFailure: true,
      );
    } on ApiException catch (error) {
      if (_disposed || generation != _generation) return;

      // The page that failed is not kept: the customer stays where they were,
      // with the button still offering to try.
      state = state.copyWith(isLoadingMore: false, failure: _failureFor(error));
    } finally {
      _inFlight = false;
    }
  }

  Future<void> _search({required bool initial, bool refining = false}) async {
    final String? tripId = _tripId;

    if (tripId == null) return;

    final int generation = ++_generation;

    // Not blocked on `_inFlight` the way the pre-Module-08 version was: a
    // customer typing a second letter must not have it dropped because the
    // first letter's request is still open. The generation check below is what
    // makes the older answer harmless.
    _inFlight = true;

    state = state.copyWith(
      isLoading: initial,
      isRefining: refining,
      clearFailure: true,
      // A first open has nothing to keep. A refine keeps the old list visible
      // underneath, because a list that empties on every keystroke cannot be
      // read.
      discovery: initial ? null : state.discovery,
    );

    final DiscoveryQuery query = state.query;

    try {
      final RestaurantDiscovery found = await _discovery.discover(
        tripId,
        query: query,
      );

      // A slower earlier request finishing after a later one. Its answer is for
      // a search the customer has already moved on from.
      if (_disposed || generation != _generation) return;

      state = state.copyWith(
        discovery: found,
        isLoading: false,
        isRefining: false,
        isLoadingMore: false,
        clearFailure: true,
        isOffline: false,
        // Any previous selection belonged to a previous result set.
        clearSelection: true,
      );
    } on ApiException catch (error) {
      if (_disposed || generation != _generation) return;

      state = state.copyWith(
        isLoading: false,
        isRefining: false,
        isLoadingMore: false,
        failure: _failureFor(error),
        // Losing the restaurants a customer already has because a refresh
        // failed punishes them for our outage.
        isOffline: error.code == ApiErrorCode.network && state.hasResults,
      );
    } finally {
      if (generation == _generation) _inFlight = false;
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
    ApiErrorCode.validationFailed => DiscoveryFailure.filtersRejected,
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
