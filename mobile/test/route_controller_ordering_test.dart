import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/data/auth/session_store.dart';
import 'package:foodonthego/domain/models/trip.dart';
import 'package:foodonthego/shared/state/providers.dart';
import 'package:foodonthego/shared/state/route_controller.dart';

import 'support/harness.dart';

/// Which route set the screen is allowed to believe.
///
/// `select()` already guarded itself against an abandoned tap of its own. It
/// did not guard against `calculate()`, and the screen leaves the alternatives
/// tappable while a recalculation is in flight — the body switches on
/// `hasRoutes`, not on `isCalculating`, and only the Recalculate button itself
/// is disabled.
///
/// So a customer can tap Recalculate, pick a different route while it works,
/// and watch their choice jump back to the recommended one when the older
/// answer lands.
void main() {
  late FakeRouteRepository routes;
  late ProviderContainer container;

  setUp(() {
    routes = FakeRouteRepository(alternatives: 3, calculated: true);
    container = ProviderContainer(
      // Inferred rather than annotated: flutter_riverpod does not export
      // `Override`, so naming the element type does not compile.
      //
      // Two overrides beyond the repository under test, and both are about the
      // same thing: a selection fans out to the trips list and the home card
      // through `_refreshTripSurfaces()`. Those controllers watch the session
      // and read the trip repository, and the real ones reach a Keychain
      // through a platform channel that does not exist in a plain `test()`.
      // Left out, every test here fails on "Binding has not yet been
      // initialized" and says nothing whatever about routes.
      overrides: [
        routeRepositoryProvider.overrideWithValue(routes),
        sessionStoreProvider.overrideWithValue(InMemorySessionStore()),
        tripRepositoryProvider.overrideWithValue(
          FakeTripRepository(trips: <Trip>[sampleTrip()]),
        ),
      ],
    );
    addTearDown(container.dispose);

    // Kept alive deliberately. This provider is autoDispose — alone among the
    // controllers in this family — so without a listener it is disposed and
    // rebuilt between awaits, and `read()` then returns a fresh, empty state.
    // The first draft of this file did exactly that and reported a route set
    // vanishing, which was the test watching a different controller than the
    // one it had driven.
    container.listen<RouteViewState>(
      routeControllerProvider,
      (RouteViewState? previous, RouteViewState next) {},
      fireImmediately: true,
    );
  });

  RouteViewState read() => container.read(routeControllerProvider);
  RouteController notifier() =>
      container.read(routeControllerProvider.notifier);

  String? selectedId() => read().routes?.trip.selectedRoute?.routeId;

  test(
    'a recalculation that answers after a selection does not undo it',
    () async {
      await notifier().open('trip-1');

      expect(selectedId(), 'route-0');

      // Recalculate, and the provider is slow about it.
      routes.calculateDelay = const Duration(milliseconds: 80);

      final Future<void> recalculating = notifier().calculate(refresh: true);

      // The customer picks an alternative while it works. That answer is quick.
      await notifier().select('route-1');

      expect(
        selectedId(),
        'route-1',
        reason: 'the selection did not take even before the race',
      );

      await recalculating;

      expect(
        selectedId(),
        'route-1',
        reason:
            'an answer issued before the customer chose put the recommended '
            'route back over their choice',
      );
    },
  );

  // ------------------------------------------------------------- the control
  //
  // This would pass on a controller that discarded every answer after the
  // first, which is a worse fault wearing the fix's clothes.

  test(
    'a recalculation with nothing newer behind it is still applied',
    () async {
      await notifier().open('trip-1');

      await notifier().select('route-2');
      expect(selectedId(), 'route-2');

      // A recalculation the customer asked for AFTER choosing is newer
      // information: it replaces the set, recommendation and all.
      await notifier().calculate(refresh: true);

      expect(
        selectedId(),
        'route-0',
        reason: 'a later answer was discarded, which is the opposite failure',
      );
    },
  );
}
