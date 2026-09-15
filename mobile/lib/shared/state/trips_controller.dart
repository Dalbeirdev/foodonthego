import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../domain/models/trip.dart';
import '../../domain/repositories/trip_repository.dart';
import 'auth_controller.dart';
import 'auth_state.dart';
import 'providers.dart';

/// Which slice of the trips list the Trips screen is showing.
///
/// Its own notifier rather than local widget state, because the list provider
/// watches it: changing the segment has to re-fetch, and a `setState` in the
/// screen would leave the two out of step on a rebuild.
class TripScopeNotifier extends Notifier<TripScope> {
  @override
  TripScope build() => TripScope.open;

  void select(TripScope scope) => state = scope;
}

final tripScopeProvider = NotifierProvider<TripScopeNotifier, TripScope>(
  TripScopeNotifier.new,
);

/// The customer's trips, for the scope currently selected.
///
/// Not optimistic. The server owns the lifecycle — whether a trip can still be
/// discarded, whether the open limit is reached — so a list updated before it
/// answers can show a change the server refused. Every write re-reads.
///
/// [build] watches the session, which is the whole of the cache-isolation story:
/// signing out disposes this state, so the next customer cannot see a frame of
/// the previous one's journeys. There is nothing to remember to clear.
class TripsController extends AsyncNotifier<List<Trip>> {
  @override
  Future<List<Trip>> build() async {
    final AuthState auth = ref.watch(authControllerProvider);
    final TripScope scope = ref.watch(tripScopeProvider);

    if (!auth.isAuthenticated) return const <Trip>[];

    return ref.read(tripRepositoryProvider).trips(scope: scope);
  }

  TripRepository get _repository => ref.read(tripRepositoryProvider);

  TripScope get _scope => ref.read(tripScopeProvider);

  /// Which read the list on screen is allowed to reflect.
  ///
  /// [refreshQuietly] has a caller that does not wait for it:
  /// `RouteController._refreshTripSurfaces()` fires it and moves on, so that a
  /// selection which succeeded is not reported as failed because the list
  /// behind it was slow. That is right, and it means a read can be in flight
  /// while the customer discards a journey — and an older read landing after
  /// puts the discarded journey back on a list the server has already cancelled
  /// it from.
  ///
  /// So every call that writes the list takes the next ticket and applies its
  /// answer only if no later one has been issued since. The same rule as the
  /// other controllers (KI-041 onwards).
  int _generation = 0;

  /// Re-fetches. Used by pull-to-refresh and after an error.
  Future<void> reload() async {
    final int ticket = ++_generation;

    state = const AsyncValue<List<Trip>>.loading();

    final AsyncValue<List<Trip>> answer = await AsyncValue.guard(
      () => _repository.trips(scope: _scope),
    );

    if (ticket != _generation) return;

    state = answer;
  }

  Future<Trip> discard(String id) async {
    // Claimed before the write, so a read already in flight cannot land on top
    // of the discard while its own re-read is still on its way.
    _generation++;

    final Trip discarded = await _repository.discardTrip(id);

    // A discarded trip leaves the open list entirely, so filtering locally would
    // be a second implementation of a server rule.
    await refreshQuietly();
    ref.invalidate(currentTripControllerProvider);

    return discarded;
  }

  /// Re-reads without flipping the screen back to a skeleton.
  ///
  /// A list that blanks out after every successful change reads as a failure.
  Future<void> refreshQuietly() async {
    final int ticket = ++_generation;

    try {
      final List<Trip> fresh = await _repository.trips(scope: _scope);

      if (ticket != _generation) return;

      state = AsyncValue<List<Trip>>.data(fresh);
    } on ApiException {
      // The write succeeded; only the re-read failed. Leaving the previous list
      // in place beats replacing a correct screen with an error about something
      // that already worked.
    }
  }
}

final tripsControllerProvider =
    AsyncNotifierProvider<TripsController, List<Trip>>(
      TripsController.new,
      // Riverpod 3 retries a failed provider on its own. Wrong here for the same
      // reason as everywhere else in this app: a traveller in a dead zone would
      // have the app quietly re-requesting while the "Try again" button in front
      // of them does nothing.
      retry: (int retryCount, Object error) => null,
    );

/// The customer's most recent open trip, for the home screen.
///
/// A separate read rather than "the first item of the list", because the home
/// screen is not the Trips screen: it must not depend on which scope that screen
/// happens to be showing, and it wants one trip rather than twenty.
class CurrentTripController extends AsyncNotifier<Trip?> {
  @override
  Future<Trip?> build() async {
    final AuthState auth = ref.watch(authControllerProvider);

    if (!auth.isAuthenticated) return null;

    return ref.read(tripRepositoryProvider).currentTrip();
  }

  /// The same ordering rule as [TripsController], and for the same caller:
  /// `RouteController._refreshTripSurfaces()` fires [refreshQuietly] without
  /// waiting for it, so a read can be in flight while the journey it describes
  /// is discarded.
  int _generation = 0;

  Future<void> reload() async {
    final int ticket = ++_generation;

    state = const AsyncValue<Trip?>.loading();

    final AsyncValue<Trip?> answer = await AsyncValue.guard(
      () => ref.read(tripRepositoryProvider).currentTrip(),
    );

    if (ticket != _generation) return;

    state = answer;
  }

  /// Re-reads without blanking the card first.
  Future<void> refreshQuietly() async {
    final int ticket = ++_generation;

    try {
      final Trip? fresh = await ref.read(tripRepositoryProvider).currentTrip();

      if (ticket != _generation) return;

      state = AsyncValue<Trip?>.data(fresh);
    } on ApiException {
      // The card on screen is still correct. Replacing it with an error about a
      // refresh is worse than showing it one change late.
    }
  }
}

final currentTripControllerProvider =
    AsyncNotifierProvider<CurrentTripController, Trip?>(
      CurrentTripController.new,
      retry: (int retryCount, Object error) => null,
    );
