import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/trip.dart';
import '../../domain/repositories/trip_repository.dart';
import 'providers.dart';
import 'trips_controller.dart';

/// Which end of the journey a picker is choosing.
enum TripEndpointSlot {
  origin,
  destination;

  bool get isOrigin => this == TripEndpointSlot.origin;
}

/// What is stopping the customer creating this trip.
///
/// Client-side and **advisory**. The server runs every one of these rules again
/// and its answer is the one that decides; doing them here as well is what turns
/// a round trip and a red banner into a message that is already on screen when
/// the customer looks up from the picker.
enum TripValidationIssue {
  originMissing,
  destinationMissing,

  /// Both ends are the same place. A journey from somewhere to itself has no
  /// route, and Module 06 would be asked to draw one.
  sameLocation,
}

/// The trip being planned.
///
/// Deliberately *not* held in text controllers. An origin is a place with a
/// position, not a string: a model built out of what is in two text fields
/// cannot tell "Jaipur" the search term from Jaipur the place, and the
/// difference is the whole of whether a route can be drawn.
class TripPlannerState {
  const TripPlannerState({
    this.origin,
    this.destination,
    this.isCreating = false,
  });

  final TripLocation? origin;
  final TripLocation? destination;

  /// True while the create request is in flight. The button is disabled from
  /// here rather than from a local flag, so a double tap cannot produce two
  /// trips.
  final bool isCreating;

  bool get hasAnything => origin != null || destination != null;

  /// The first thing wrong, or null when the trip is ready to create.
  ///
  /// Order matters: somebody who has chosen nothing should be told to choose a
  /// starting point, not that their two empty ends are the same place.
  TripValidationIssue? get issue {
    if (origin == null) return TripValidationIssue.originMissing;
    if (destination == null) return TripValidationIssue.destinationMissing;
    if (origin!.isSamePlaceAs(destination!)) {
      return TripValidationIssue.sameLocation;
    }
    return null;
  }

  bool get canCreate => issue == null && !isCreating;

  TripPlannerState copyWith({
    TripLocation? origin,
    TripLocation? destination,
    bool clearOrigin = false,
    bool clearDestination = false,
    bool? isCreating,
  }) => TripPlannerState(
    origin: clearOrigin ? null : (origin ?? this.origin),
    destination: clearDestination ? null : (destination ?? this.destination),
    isCreating: isCreating ?? this.isCreating,
  );
}

/// The trip planner's draft.
///
/// Lives for as long as the planner screen and no longer: [autoDispose] means a
/// half-planned journey does not survive leaving the screen, and — more to the
/// point — does not survive a sign-out into the next customer's session. There
/// is nothing to remember to clear because there is nothing kept.
class TripPlannerController extends Notifier<TripPlannerState> {
  /// The planner can be popped while a create is in flight. See
  /// [PlaceSearchController] — same reasoning, same fix.
  bool _disposed = false;

  late final TripRepository _trips;

  @override
  TripPlannerState build() {
    _trips = ref.read(tripRepositoryProvider);

    ref.onDispose(() => _disposed = true);

    return const TripPlannerState();
  }

  void select(TripEndpointSlot slot, TripLocation location) {
    state = slot.isOrigin
        ? state.copyWith(origin: location)
        : state.copyWith(destination: location);
  }

  void clear(TripEndpointSlot slot) {
    state = slot.isOrigin
        ? state.copyWith(clearOrigin: true)
        : state.copyWith(clearDestination: true);
  }

  /// Turns the journey round.
  ///
  /// Works with one end chosen or none: swapping a half-filled plan moves the
  /// one place the customer has picked to the other row, which is what somebody
  /// who realises they entered it in the wrong box expects.
  void swap() {
    final TripLocation? origin = state.origin;
    final TripLocation? destination = state.destination;

    state = TripPlannerState(
      origin: destination,
      destination: origin,
      isCreating: state.isCreating,
    );
  }

  void reset() => state = const TripPlannerState();

  /// Creates the trip.
  ///
  /// Throws on failure rather than folding the error into [state]: the screen
  /// needs to keep both chosen places and show the message against the right
  /// row, which it cannot do once the error has become the whole screen's.
  ///
  /// Sends two places and nothing else. There is no customer id in the payload —
  /// the session decides whose trip this is — and no status, route status,
  /// distance or ETA, because this app has no business proposing any of them.
  Future<Trip> create() async {
    final TripLocation? origin = state.origin;
    final TripLocation? destination = state.destination;

    if (origin == null || destination == null) {
      throw StateError('create() called with an incomplete plan');
    }

    // Taken before the await. These two live on providers that outlive this
    // screen, so refreshing through them still works if the customer navigates
    // away mid-request — and reaching for `ref` afterwards would not.
    final TripsController trips = ref.read(tripsControllerProvider.notifier);
    final CurrentTripController current = ref.read(
      currentTripControllerProvider.notifier,
    );

    state = state.copyWith(isCreating: true);

    try {
      final Trip trip = await _trips.createTrip(
        TripDraft(origin: origin, destination: destination),
      );

      // Re-read rather than patched: the server owns the limit and the
      // ordering, and a list assembled locally is a second implementation of
      // rules that already exist once.
      await trips.refreshQuietly();
      await current.refreshQuietly();

      return trip;
    } finally {
      if (!_disposed) state = state.copyWith(isCreating: false);
    }
  }
}

final tripPlannerControllerProvider =
    NotifierProvider.autoDispose<TripPlannerController, TripPlannerState>(
      TripPlannerController.new,
    );
