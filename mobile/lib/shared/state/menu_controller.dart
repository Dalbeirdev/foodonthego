import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_error_code.dart';
import '../../core/network/api_exception.dart';
import '../../domain/models/restaurant_menu.dart';
import '../../domain/repositories/menu_repository.dart';
import 'providers.dart';

/// Why the menu screen has nothing to show.
///
/// Separate cases because the customer's next move differs for each: a
/// withdrawn restaurant sends them back to the list, an outage asks them to try
/// again, and a restaurant that has simply not published a menu is not a
/// failure at all — it is [RestaurantMenu.isMenuEmpty], handled as content.
enum MenuFailure {
  /// The request never left the device.
  network,

  /// No such restaurant, or not one this customer may see. One case on
  /// purpose: telling them apart is how a prober maps the platform.
  notFound,

  /// It was on the route a minute ago and has since been suspended or closed
  /// for good.
  withdrawn,

  /// Real, trading, and not on this journey.
  outsideRoute,

  /// The trip has no usable selected route.
  routeNotReady,

  /// The trip is gone, or was never this customer's.
  tripGone,

  /// The search string was refused — today, only for being too long.
  searchRejected,

  rateLimited,

  unauthorized,

  /// Ours, and unexplained.
  serverError,

  unknown,
}

/// Why an item preview has nothing to show.
enum MenuItemFailure { network, notFound, unavailable, serverError, unknown }

/// What the item preview sheet is showing.
class MenuItemPreviewState {
  const MenuItemPreviewState({
    this.itemId,
    this.summary,
    this.preview,
    this.isLoading = false,
    this.failure,
  });

  /// Which item the sheet was opened for.
  final String? itemId;

  /// What the card already knew, drawn immediately so the sheet is never
  /// blank. Replaced the moment the server answers — never left standing
  /// alone, because a card cached before a price change would keep quoting it.
  final MenuItem? summary;

  final MenuItemPreview? preview;

  final bool isLoading;
  final MenuItemFailure? failure;

  bool get isOpen => itemId != null;

  /// Whichever half has arrived. The fresh one wins.
  MenuItem? get item => preview?.item ?? summary;

  bool get isRetryable =>
      failure != null &&
      failure != MenuItemFailure.notFound &&
      failure != MenuItemFailure.unavailable;
}

/// What the menu screen is showing.
class MenuState {
  const MenuState({
    this.menu,
    this.isLoading = false,
    this.isRefreshing = false,
    this.isSearching = false,
    this.failure,
    this.isOffline = false,
    this.searchTerm = '',
    this.selectedCategoryId,
    this.preview = const MenuItemPreviewState(),
  });

  final RestaurantMenu? menu;

  final bool isLoading;

  /// A pull-to-refresh over content already on screen.
  final bool isRefreshing;

  /// A search request is in flight. Distinct from [isLoading]: the menu the
  /// customer is already reading stays put underneath, because replacing it
  /// with a spinner on every keystroke makes the screen flicker.
  final bool isSearching;

  final MenuFailure? failure;

  /// The last load failed for want of a network and there is something on
  /// screen. The screen says so, and says how old it is, rather than implying
  /// these prices are live.
  final bool isOffline;

  /// What is in the box right now — not necessarily what the server has
  /// applied. [RestaurantMenu.appliedSearch] is the applied one.
  final String searchTerm;

  /// Which category heading the selector is highlighting.
  final String? selectedCategoryId;

  final MenuItemPreviewState preview;

  bool get hasMenu => menu != null;

  bool get hasItems => menu?.hasItems ?? false;

  /// The restaurant has published nothing a customer may see.
  bool get isMenuEmpty => menu?.isMenuEmpty ?? false;

  /// There is a menu; this search found none of it.
  bool get isSearchEmpty => menu?.isSearchEmpty ?? false;

  List<MenuCategory> get categories => menu?.categories ?? const [];

  /// Whether offering "Try again" would be honest.
  ///
  /// A withdrawn restaurant is not retryable: it will not come back because
  /// the customer pressed a button, and the button implies it might.
  bool get isRetryable =>
      failure != null &&
      failure != MenuFailure.notFound &&
      failure != MenuFailure.withdrawn &&
      failure != MenuFailure.outsideRoute &&
      failure != MenuFailure.tripGone &&
      failure != MenuFailure.unauthorized;

  MenuState copyWith({
    RestaurantMenu? menu,
    bool clearMenu = false,
    bool? isLoading,
    bool? isRefreshing,
    bool? isSearching,
    MenuFailure? failure,
    bool clearFailure = false,
    bool? isOffline,
    String? searchTerm,
    String? selectedCategoryId,
    bool clearSelectedCategory = false,
    MenuItemPreviewState? preview,
  }) => MenuState(
    menu: clearMenu ? null : (menu ?? this.menu),
    isLoading: isLoading ?? this.isLoading,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    isSearching: isSearching ?? this.isSearching,
    failure: clearFailure ? null : (failure ?? this.failure),
    isOffline: isOffline ?? this.isOffline,
    searchTerm: searchTerm ?? this.searchTerm,
    selectedCategoryId: clearSelectedCategory
        ? null
        : (selectedCategoryId ?? this.selectedCategoryId),
    preview: preview ?? this.preview,
  );
}

/// The menu screen's state.
///
/// Two rules, both of which exist because a customer types faster than a
/// network answers:
///
/// 1. **The newest request wins.** Three keystrokes produce three requests that
///    can return in any order; without the generation check the slowest lands
///    last and the screen shows results for "pan" under the word "paneer".
///
/// 2. **A search does not blank the menu.** The previous results stay on screen
///    with a quiet progress indicator, because a list that empties and refills
///    on every letter is unreadable.
///
/// The third rule is not enforced here at all and is worth saying anyway:
/// opening a menu calls no routing provider. That is a property of the
/// endpoint, not of this class — but it is why a customer can open five menus
/// while deciding where to stop.
class MenuScreenController extends Notifier<MenuState> {
  String? _tripId;
  String? _restaurantId;

  bool _disposed = false;

  /// Which menu request the state belongs to. Only the newest may write.
  int _generation = 0;

  /// The same, for the preview sheet, which races independently.
  int _previewGeneration = 0;

  Timer? _debounce;

  /// How long to wait after the last keystroke.
  ///
  /// Long enough that typing "paneer" is one request rather than six, short
  /// enough that a customer who has stopped typing does not notice waiting.
  static const Duration searchDebounce = Duration(milliseconds: 350);

  /// Below this the server treats the term as no search at all, so sending it
  /// would fetch the whole menu and label it a result.
  static const int minimumSearchLength = 2;

  late final MenuRepository _menus;

  @override
  MenuState build() {
    _menus = ref.read(menuRepositoryProvider);

    ref.onDispose(() {
      _disposed = true;
      _debounce?.cancel();
    });

    return const MenuState();
  }

  /// Opens the menu for one restaurant on one trip.
  Future<void> open({
    required String tripId,
    required String restaurantId,
  }) async {
    final bool same = _tripId == tripId && _restaurantId == restaurantId;

    if (same && (state.hasMenu || state.isLoading)) return;

    _tripId = tripId;
    _restaurantId = restaurantId;

    // A different restaurant means everything on screen belongs to the
    // previous one. Clearing it is what stops one kitchen's prices sitting
    // under another kitchen's name while the request is in flight.
    state = const MenuState(isLoading: true);

    await _load(reason: _LoadReason.initial);
  }

  Future<void> retry() => _load(reason: _LoadReason.initial);

  Future<void> refresh() => _load(reason: _LoadReason.refresh);

  /// A keystroke. Debounced; the request goes out when the typing stops.
  void searchChanged(String term) {
    _debounce?.cancel();

    state = state.copyWith(searchTerm: term);

    final String trimmed = term.trim();

    // One character is not a search. Sending it would return the whole menu
    // and the screen would present it as a result for "p".
    if (trimmed.isNotEmpty && trimmed.length < minimumSearchLength) {
      return;
    }

    _debounce = Timer(searchDebounce, () {
      if (_disposed) return;

      unawaited(_load(reason: _LoadReason.search));
    });
  }

  /// The clear button, and the "clear search" action on the empty state.
  Future<void> clearSearch() {
    _debounce?.cancel();

    if (state.searchTerm.isEmpty && state.menu?.appliedSearch == null) {
      return Future<void>.value();
    }

    state = state.copyWith(searchTerm: '');

    return _load(reason: _LoadReason.search);
  }

  /// The customer tapped a category chip, or scrolled one into view.
  void categorySelected(String? categoryId) {
    if (state.selectedCategoryId == categoryId) return;

    state = categoryId == null
        ? state.copyWith(clearSelectedCategory: true)
        : state.copyWith(selectedCategoryId: categoryId);
  }

  // --- the item preview ----------------------------------------------------

  /// Opens the read-only preview for one item.
  ///
  /// [summary] is what the card already knew, so the sheet has a name and a
  /// price the instant it appears. The server is asked all the same, because
  /// the card may have been drawn ten minutes ago.
  Future<void> openItem(MenuItem summary) async {
    final String? tripId = _tripId;
    final String? restaurantId = _restaurantId;

    if (tripId == null || restaurantId == null) return;

    final int generation = ++_previewGeneration;

    state = state.copyWith(
      preview: MenuItemPreviewState(
        itemId: summary.id,
        summary: summary,
        isLoading: true,
      ),
    );

    try {
      final MenuItemPreview preview = await _menus.item(
        tripId: tripId,
        restaurantId: restaurantId,
        itemId: summary.id,
      );

      if (_disposed || generation != _previewGeneration) return;

      state = state.copyWith(
        preview: MenuItemPreviewState(
          itemId: summary.id,
          summary: summary,
          preview: preview,
        ),
      );
    } on ApiException catch (error) {
      if (_disposed || generation != _previewGeneration) return;

      final MenuItemFailure failure = _itemFailureFor(error);

      state = state.copyWith(
        preview: MenuItemPreviewState(
          itemId: summary.id,
          // An item that has been withdrawn since the list was drawn loses its
          // summary too: leaving the card's copy on screen would present a
          // dish the kitchen has taken off as though it were still available.
          summary: failure == MenuItemFailure.notFound ? null : summary,
          failure: failure,
        ),
      );
    } catch (_) {
      if (_disposed || generation != _previewGeneration) return;

      state = state.copyWith(
        preview: MenuItemPreviewState(
          itemId: summary.id,
          summary: summary,
          failure: MenuItemFailure.serverError,
        ),
      );
    }
  }

  /// "Try again" inside the sheet.
  Future<void> retryItem() {
    final MenuItem? summary = state.preview.summary;

    if (summary == null) return Future<void>.value();

    return openItem(summary);
  }

  void closeItem() {
    // Bumped so an answer still in flight for the sheet the customer has just
    // dismissed cannot reopen it.
    _previewGeneration++;

    state = state.copyWith(preview: const MenuItemPreviewState());
  }

  // --- loading -------------------------------------------------------------

  Future<void> _load({required _LoadReason reason}) async {
    final String? tripId = _tripId;
    final String? restaurantId = _restaurantId;

    if (tripId == null || restaurantId == null) return;

    final int generation = ++_generation;

    final String term = state.searchTerm.trim();
    final String? search = term.length >= minimumSearchLength ? term : null;

    state = state.copyWith(
      isLoading: reason == _LoadReason.initial && !state.hasMenu,
      isRefreshing: reason == _LoadReason.refresh,
      isSearching: reason == _LoadReason.search,
      clearFailure: true,
    );

    try {
      final RestaurantMenu menu = await _menus.menu(
        tripId: tripId,
        restaurantId: restaurantId,
        search: search,
      );

      // A slower earlier request finishing after a later one. Its answer is
      // about a search the customer has already typed past.
      if (_disposed || generation != _generation) return;

      state = state.copyWith(
        menu: menu,
        isLoading: false,
        isRefreshing: false,
        isSearching: false,
        clearFailure: true,
        isOffline: false,
        // The category the selector was on may not be in these results at all
        // — a search usually removes most of them.
        selectedCategoryId: _categoryStillPresent(menu)
            ? state.selectedCategoryId
            : menu.categories.firstOrNull?.id,
        clearSelectedCategory: menu.categories.isEmpty,
      );
    } on ApiException catch (error) {
      if (_disposed || generation != _generation) return;

      final MenuFailure failure = _failureFor(error);

      state = state.copyWith(
        isLoading: false,
        isRefreshing: false,
        isSearching: false,
        failure: failure,
        // Keeping what the customer already has because a refresh failed is
        // kinder than punishing them for our outage — but only while the
        // restaurant is still theirs to see. A withdrawn one loses its menu,
        // because leaving it up would present a suspended kitchen as trading.
        clearMenu:
            failure == MenuFailure.withdrawn || failure == MenuFailure.notFound,
        isOffline: error.code == ApiErrorCode.network && state.hasMenu,
      );
    } catch (_) {
      if (_disposed || generation != _generation) return;

      // A 200 whose body could not be read. Ours, and unexplained.
      state = state.copyWith(
        isLoading: false,
        isRefreshing: false,
        isSearching: false,
        failure: MenuFailure.serverError,
      );
    }
  }

  bool _categoryStillPresent(RestaurantMenu menu) {
    final String? selected = state.selectedCategoryId;

    if (selected == null) return false;

    return menu.categories.any((MenuCategory c) => c.id == selected);
  }

  MenuFailure _failureFor(ApiException error) => switch (error.code) {
    ApiErrorCode.network => MenuFailure.network,
    ApiErrorCode.restaurantNotFound ||
    ApiErrorCode.notFound => MenuFailure.notFound,
    ApiErrorCode.restaurantUnavailable ||
    ApiErrorCode.menuNotAvailable => MenuFailure.withdrawn,
    ApiErrorCode.restaurantOutsideRoute => MenuFailure.outsideRoute,
    ApiErrorCode.routeNotReady ||
    ApiErrorCode.routeStale ||
    ApiErrorCode.routeNotFound => MenuFailure.routeNotReady,
    ApiErrorCode.tripNotFound => MenuFailure.tripGone,
    ApiErrorCode.validationFailed => MenuFailure.searchRejected,
    ApiErrorCode.discoveryRateLimited ||
    ApiErrorCode.rateLimited => MenuFailure.rateLimited,
    ApiErrorCode.unauthenticated => MenuFailure.unauthorized,
    ApiErrorCode.serverError ||
    ApiErrorCode.detailLoadFailed ||
    ApiErrorCode.discoveryFailed => MenuFailure.serverError,
    _ => MenuFailure.unknown,
  };

  MenuItemFailure _itemFailureFor(ApiException error) => switch (error.code) {
    ApiErrorCode.network => MenuItemFailure.network,
    ApiErrorCode.itemNotFound ||
    ApiErrorCode.restaurantNotFound ||
    ApiErrorCode.notFound => MenuItemFailure.notFound,
    ApiErrorCode.itemUnavailable ||
    ApiErrorCode.restaurantUnavailable => MenuItemFailure.unavailable,
    ApiErrorCode.serverError => MenuItemFailure.serverError,
    _ => MenuItemFailure.unknown,
  };
}

enum _LoadReason { initial, refresh, search }

/// Auto-disposed: one restaurant's menu belongs to one visit to one screen.
/// Closing it should take the prices with it rather than leaving one kitchen's
/// menu in memory behind the next.
final menuControllerProvider =
    NotifierProvider.autoDispose<MenuScreenController, MenuState>(
      MenuScreenController.new,
    );
