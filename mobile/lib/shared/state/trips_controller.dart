import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../domain/models/trip.dart';
import '../../domain/repositories/trip_repository.dart';
import 'auth_controller.dart';
import 'auth_state.dart';
import 'providers.dart';

/// Which slice of the journeys list the Trips screen is showing.
///
/// Its own notifier rather than local widget state, because the list provider
/// watches it: changing the segment has to re-fetch, and a `setState` in the
/// screen would leave the two out of step on a rebuild.
class TripScopeNotifier extends Notifier<TripScope> {
  @override
  TripScope build() => TripScope.upcoming;

  void select(TripScope scope) => state = scope;
}

final tripScopeProvider = NotifierProvider<TripScopeNotifier, TripScope>(
  TripScopeNotifier.new,
);

/// The customer's journeys, for the scope currently selected.
///
/// Not optimistic. The server owns the lifecycle — whether a journey can still
/// be changed, whether the limit is reached, whether cancelling is allowed — so
/// a list updated before it answers can show a cancellation the server refused.
/// Every write re-reads.
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

  /// Re-fetches. Used by pull-to-refresh and after an error.
  Future<void> reload() async {
    state = const AsyncValue<List<Trip>>.loading();
    state = await AsyncValue.guard(() => _repository.trips(scope: _scope));
  }

  /// Plans a journey and returns it.
  ///
  /// Throws on failure rather than folding the error into [state]: the form that
  /// called this needs to keep what the customer typed and show the message
  /// against the right field, which it cannot do once the error has become the
  /// whole screen's.
  Future<Trip> plan(TripDraft draft) async {
    final Trip created = await _repository.planTrip(draft);
    await _refreshQuietly();

    return created;
  }

  Future<Trip> edit(String id, TripDraft draft) async {
    final Trip updated = await _repository.updateTrip(id, draft);
    await _refreshQuietly();

    return updated;
  }

  Future<Trip> cancel(String id, {String? reason}) async {
    final Trip cancelled = await _repository.cancelTrip(id, reason: reason);

    // A cancelled journey leaves the upcoming list entirely, so filtering
    // locally would be a second implementation of a server rule.
    await _refreshQuietly();

    return cancelled;
  }

  /// Re-reads without flipping the screen back to a skeleton.
  ///
  /// A list that blanks out after every successful change reads as a failure.
  Future<void> _refreshQuietly() async {
    try {
      state = AsyncValue<List<Trip>>.data(
        await _repository.trips(scope: _scope),
      );
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

/// The soonest journey still ahead, for the home screen.
///
/// A separate read rather than "the first item of the list", because the home
/// screen is not the Trips screen: it must not depend on which scope that screen
/// happens to be showing, and it wants one journey rather than twenty.
class NextTripController extends AsyncNotifier<Trip?> {
  @override
  Future<Trip?> build() async {
    final AuthState auth = ref.watch(authControllerProvider);

    // Rebuilt whenever the journeys list changes, so planning or cancelling on
    // the Trips screen is reflected on Home without a manual invalidation
    // somebody could forget at a fourth call site.
    ref.watch(tripsControllerProvider);

    if (!auth.isAuthenticated) return null;

    return ref.read(tripRepositoryProvider).nextTrip();
  }

  Future<void> reload() async {
    state = const AsyncValue<Trip?>.loading();
    state = await AsyncValue.guard(
      () => ref.read(tripRepositoryProvider).nextTrip(),
    );
  }
}

final nextTripControllerProvider =
    AsyncNotifierProvider<NextTripController, Trip?>(
      NextTripController.new,
      retry: (int retryCount, Object error) => null,
    );
