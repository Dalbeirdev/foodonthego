import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/data/auth/session_store.dart';
import 'package:foodonthego/domain/models/auth_models.dart';
import 'package:foodonthego/domain/models/trip.dart';
import 'package:foodonthego/shared/state/auth_controller.dart';
import 'package:foodonthego/shared/state/providers.dart';
import 'package:foodonthego/shared/state/trips_controller.dart';

import 'support/harness.dart';

/// Whether a discarded journey can come back.
///
/// `refreshQuietly()` is called from two places, and one of them does not wait
/// for it: `RouteController._refreshTripSurfaces()` fires it and moves on,
/// because a selection that succeeded must not be reported as failed just
/// because the list behind it was slow to re-read. That is right, and it means
/// a read of the journeys can be in flight while the customer discards one.
///
/// If the older read is allowed to land, the discarded journey reappears in the
/// list — over a server that has already cancelled it.
void main() {
  late FakeTripRepository trips;
  late ProviderContainer container;

  setUp(() async {
    trips = FakeTripRepository(
      trips: <Trip>[
        sampleTrip(id: 'trip-1'),
        sampleTrip(id: 'trip-2'),
      ],
    );

    final InMemorySessionStore store = InMemorySessionStore();
    await store.write(
      AuthSession(
        accessToken: 'stored-token',
        expiresAt: DateTime.now().toUtc().add(const Duration(days: 7)),
        customer: FakeAuthRepository.sampleCustomer,
      ),
    );

    container = ProviderContainer(
      // Inferred rather than annotated: flutter_riverpod does not export
      // `Override`, so naming the element type does not compile.
      //
      // The session is real-shaped because this controller's `build()` watches
      // it: signed out, it returns an empty list and none of this is reachable.
      overrides: [
        tripRepositoryProvider.overrideWithValue(trips),
        authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
        sessionStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<void> settle() async {
    for (int i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  List<String> idsOnScreen() => container
      .read(tripsControllerProvider)
      .value!
      .map((Trip trip) => trip.id)
      .toList();

  TripsController notifier() =>
      container.read(tripsControllerProvider.notifier);

  /// Signs the session in, then loads the list.
  ///
  /// Both halves are needed and the order matters: this controller's `build()`
  /// watches the session and returns an empty list while it is still
  /// restoring. A first draft read the list first and asserted against `[]`
  /// — which made its control pass while testing nothing at all.
  Future<void> signedInWithTrips() async {
    container.read(authControllerProvider);
    await settle();
    await container.read(tripsControllerProvider.future);
    await settle();
  }

  test('a read that answers after a discard does not bring it back', () async {
    await signedInWithTrips();

    expect(idsOnScreen(), containsAll(<String>['trip-1', 'trip-2']));

    // The route screen fires one of these and does not wait for it.
    final Completer<void> slowAnswer = Completer<void>();
    trips.holdTrips = slowAnswer;

    final Future<void> fanOut = notifier().refreshQuietly();

    // The customer discards a journey while it is in the air.
    await notifier().discard('trip-1');

    expect(
      idsOnScreen(),
      isNot(contains('trip-1')),
      reason: 'the discard did not take even before the race',
    );

    slowAnswer.complete();
    await fanOut;
    await settle();

    expect(
      idsOnScreen(),
      isNot(contains('trip-1')),
      reason:
          'a read issued before the discard put the journey back on a list '
          'the server has already cancelled it from',
    );
  });

  // ------------------------------------------------------------- the control
  //
  // This would pass on a controller that discarded every answer after the
  // first, which is a worse fault wearing the fix's clothes.

  test('a read with nothing newer behind it is still applied', () async {
    await signedInWithTrips();

    // Something else cancels a journey — another device, or the server itself.
    await trips.discardTrip('trip-2');

    await notifier().refreshQuietly();

    expect(
      idsOnScreen(),
      isNot(contains('trip-2')),
      reason: 'a later answer was discarded, which is the opposite failure',
    );
    expect(
      idsOnScreen(),
      contains('trip-1'),
      reason:
          'the list is empty, so the assertion above holds for the wrong '
          'reason — the session probably never restored',
    );
  });
}
