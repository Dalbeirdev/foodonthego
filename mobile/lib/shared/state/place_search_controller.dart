import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_error_code.dart';
import '../../core/network/api_exception.dart';
import '../../domain/models/place.dart';
import '../../domain/repositories/place_repository.dart';
import 'providers.dart';

/// How long typing has to stop before a request goes out.
///
/// 350 ms — long enough that a whole word costs one call rather than six, short
/// enough that it does not feel like lag. Sending on every keystroke would spend
/// a metered provider request per letter and would produce exactly the race this
/// controller exists to prevent.
const Duration kPlaceSearchDebounce = Duration(milliseconds: 350);

/// The shortest query worth sending. Matches the server's own minimum.
const int kPlaceSearchMinimumLength = 2;

/// Why a search did not produce results.
enum PlaceSearchFailure {
  /// The request never left, or never came back.
  network,

  /// The provider answered with a failure. Retrying may work; changing the
  /// query will not.
  lookupUnavailable,

  /// Anything else, including a response that was not the documented envelope.
  unknown,
}

/// What the search field is showing.
class PlaceSearchState {
  const PlaceSearchState({
    this.query = '',
    this.results = const <PlaceSuggestion>[],
    this.isSearching = false,
    this.failure,
    this.hasSearched = false,
  });

  final String query;
  final List<PlaceSuggestion> results;

  /// True from the moment a request is dispatched until its answer is applied
  /// or superseded.
  final bool isSearching;

  final PlaceSearchFailure? failure;

  /// Whether a search has actually completed for the current query.
  ///
  /// Distinguishes "no results for Atlantis" from "you have not typed anything
  /// yet", which are the same empty list and need different screens.
  final bool hasSearched;

  bool get isTooShort =>
      query.trim().length < kPlaceSearchMinimumLength &&
      query.trim().isNotEmpty;

  bool get isEmptyResult =>
      hasSearched && !isSearching && failure == null && results.isEmpty;

  PlaceSearchState copyWith({
    String? query,
    List<PlaceSuggestion>? results,
    bool? isSearching,
    PlaceSearchFailure? failure,
    bool clearFailure = false,
    bool? hasSearched,
  }) => PlaceSearchState(
    query: query ?? this.query,
    results: results ?? this.results,
    isSearching: isSearching ?? this.isSearching,
    failure: clearFailure ? null : (failure ?? this.failure),
    hasSearched: hasSearched ?? this.hasSearched,
  );
}

/// Place autocomplete: debounced, session-scoped, and immune to slow answers.
///
/// Three things happen here that all have to happen together, and any one of
/// them alone is not enough:
///
/// **Debounce.** Nothing is dispatched until typing pauses for
/// [kPlaceSearchDebounce]. A metered provider request per keystroke is a bill
/// and a rate limit.
///
/// **Generation guard.** Every dispatch carries the generation it was issued
/// under, and the answer is dropped unless it is still current. Without this, a
/// slow response for "jai" arriving after a fast one for "jaipur airport" would
/// overwrite the correct list with a stale one — and the customer would see the
/// results of a query they finished typing seconds ago. This is the race the
/// module's test matrix requires be demonstrated.
///
/// **Session token.** One token spans a whole search — every keystroke plus the
/// details call that ends it — so the provider bills a session rather than a
/// request per letter.
///
/// ### Session token lifecycle
/// Minted by [beginSession] when a search UI opens. Sent with every
/// autocomplete request and with the single details call that resolves the
/// chosen place. Discarded by [endSession] the moment that details call is made
/// or the search is abandoned. It is never reused for a second search and never
/// regenerated mid-search: a token per keystroke bills like no token at all, and
/// a token that lives forever is a session that never closes.
class PlaceSearchController extends Notifier<PlaceSearchState> {
  Timer? _debounce;

  /// Incremented on every query change and every reset. An in-flight request
  /// whose generation no longer matches is stale by definition.
  int _generation = 0;

  String? _sessionToken;

  /// The sheet can close while a request is in flight. Once that happens this
  /// notifier is disposed, and both `ref` and `state` become unusable — so the
  /// answer, when it eventually arrives, must find a closed door rather than
  /// throw inside a completed future nobody is watching.
  bool _disposed = false;

  /// Captured at build time rather than read on demand, for the same reason.
  late final PlaceRepository _places;

  @override
  PlaceSearchState build() {
    _places = ref.read(placeRepositoryProvider);

    ref.onDispose(() {
      _disposed = true;
      _debounce?.cancel();
    });

    return const PlaceSearchState();
  }

  /// The token for the search currently in progress, if any.
  String? get sessionToken => _sessionToken;

  /// Opens a search. Mints the token that will span it.
  void beginSession() {
    _sessionToken ??= _mintToken();
  }

  /// Closes a search. The next one gets a fresh token.
  void endSession() {
    _sessionToken = null;
  }

  /// Called on every keystroke.
  void query(String value) {
    final String trimmed = value.trim();

    // Bump first. Anything already in flight is now answering a question the
    // customer has moved on from.
    _generation++;
    _debounce?.cancel();

    if (trimmed.length < kPlaceSearchMinimumLength) {
      // Not an error and not a request. A single letter is not a search, and
      // sending it would spend a metered call on nothing.
      state = state.copyWith(
        query: value,
        results: const <PlaceSuggestion>[],
        isSearching: false,
        hasSearched: false,
        clearFailure: true,
      );
      return;
    }

    state = state.copyWith(query: value, isSearching: true, clearFailure: true);

    final int generation = _generation;
    _debounce = Timer(
      kPlaceSearchDebounce,
      () => _dispatch(trimmed, generation),
    );
  }

  /// Re-runs the current query. For the "Try again" the failure state offers.
  void retry() {
    final String trimmed = state.query.trim();
    if (trimmed.length < kPlaceSearchMinimumLength) return;

    _generation++;
    _debounce?.cancel();
    state = state.copyWith(isSearching: true, clearFailure: true);
    _dispatch(trimmed, _generation);
  }

  /// Empties the field and abandons anything in flight.
  void clear() {
    _generation++;
    _debounce?.cancel();
    state = const PlaceSearchState();
  }

  Future<void> _dispatch(String query, int generation) async {
    try {
      final List<PlaceSuggestion> results = await _places.search(
        query,
        sessionToken: _sessionToken,
      );

      // The guard. A slow answer to an old query is discarded rather than
      // rendered, so what is on screen always belongs to what is in the field.
      if (_disposed || generation != _generation) return;

      state = state.copyWith(
        results: results,
        isSearching: false,
        hasSearched: true,
        clearFailure: true,
      );
    } on ApiException catch (error) {
      if (_disposed || generation != _generation) return;

      state = state.copyWith(
        results: const <PlaceSuggestion>[],
        isSearching: false,
        hasSearched: true,
        failure: switch (error.code) {
          ApiErrorCode.network => PlaceSearchFailure.network,
          ApiErrorCode.placeLookupFailed ||
          ApiErrorCode.dependencyUnavailable =>
            PlaceSearchFailure.lookupUnavailable,
          _ => PlaceSearchFailure.unknown,
        },
      );
    } catch (_) {
      if (_disposed || generation != _generation) return;

      state = state.copyWith(
        results: const <PlaceSuggestion>[],
        isSearching: false,
        hasSearched: true,
        failure: PlaceSearchFailure.unknown,
      );
    }
  }

  /// A 128-bit random token.
  ///
  /// `Random.secure()` rather than the default generator: this identifier groups
  /// one person's searches, and a predictable one would let anybody holding the
  /// sequence correlate them.
  static String _mintToken() {
    final Random random = Random.secure();
    final StringBuffer buffer = StringBuffer();

    for (int i = 0; i < 32; i++) {
      buffer.write(random.nextInt(16).toRadixString(16));
    }

    return buffer.toString();
  }
}

/// Auto-disposed on purpose.
///
/// The search UI is a sheet. When it closes, the query, the results and the
/// session token go with it — so what somebody typed is not sitting in memory
/// behind the next screen, and the next search starts from nothing rather than
/// from somebody else's last one.
final placeSearchControllerProvider =
    NotifierProvider.autoDispose<PlaceSearchController, PlaceSearchState>(
      PlaceSearchController.new,
    );
