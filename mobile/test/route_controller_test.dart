import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/core/network/api_error_code.dart';
import 'package:foodonthego/core/network/api_exception.dart';
import 'package:foodonthego/data/auth/session_store.dart';
import 'package:foodonthego/shared/state/providers.dart';
import 'package:foodonthego/shared/state/route_controller.dart';

import 'support/harness.dart';

/// The route screen's state.
///
/// Judged above all on **not spending money**. Every provider call is billed,
/// and the screen that shows a route is the one people reopen — so a great many
/// of these tests do nothing but count calls.
void main() {
  late FakeRouteRepository routes;
  late ProviderContainer container;

  ProviderContainer build(FakeRouteRepository repository) {
    final ProviderContainer c = ProviderContainer(
      // The list type is inferred: `Override` is not exported from
      // flutter_riverpod, and importing it from a transitive package to write
      // an annotation the compiler can work out itself is not worth the
      // coupling.
      //
      // The trips and session overrides are here because a successful
      // calculation re-reads the surfaces that carry a route summary — the
      // trips list and the home card. Without them the controller would reach
      // the real API client, and through it the secure-storage platform
      // channel, which does not exist in a pure Dart test.
      overrides: [
        routeRepositoryProvider.overrideWithValue(repository),
        tripRepositoryProvider.overrideWithValue(FakeTripRepository()),
        sessionStoreProvider.overrideWithValue(InMemorySessionStore()),
      ],
    );

    // The provider auto-disposes and in the app the screen keeps it alive. A
    // test with no listener would tear the controller down between one read and
    // the next.
    c.listen(
      routeControllerProvider,
      (RouteViewState? _, RouteViewState _) {},
      fireImmediately: true,
    );

    addTearDown(c.dispose);

    return c;
  }

  RouteController controller() =>
      container.read(routeControllerProvider.notifier);

  RouteViewState state() => container.read(routeControllerProvider);

  group('opening the screen', () {
    test('reads what the server has before deciding anything', () async {
      routes = FakeRouteRepository(calculated: true);
      container = build(routes);

      await controller().open('trip-1');

      expect(routes.readCalls, 1);
      // Already calculated, so nothing is asked of the provider.
      expect(routes.calculateCalls, 0);
      expect(state().hasRoutes, isTrue);
    });

    test('calculates once when there is nothing yet', () async {
      routes = FakeRouteRepository();
      container = build(routes);

      await controller().open('trip-1');

      expect(routes.calculateCalls, 1);
      expect(state().hasRoutes, isTrue);
    });

    test('opening the same trip again does not calculate again', () async {
      routes = FakeRouteRepository();
      container = build(routes);

      await controller().open('trip-1');
      await controller().open('trip-1');
      await controller().open('trip-1');

      // The single most important assertion in this file. A screen that
      // recalculates whenever the framework rebuilds it is a bill.
      expect(routes.calculateCalls, 1);
      expect(routes.readCalls, 1);
    });

    test(
      'a trip the provider has already refused is not asked about again',
      () async {
        routes = FakeRouteRepository()
          ..nextCalculateError = const ApiException(
            code: ApiErrorCode.routeNoRouteFound,
            message: 'no route',
            status: 422,
          );
        container = build(routes);

        await controller().open('trip-1');
        expect(routes.calculateCalls, 1);
        expect(state().failure, RouteFailure.noRoute);

        // Reopening asks the server what it knows, and the answer is still
        // NO_ROUTE — which is not retryable, so no second provider call.
        await controller().open('trip-2');
        expect(routes.calculateCalls, 1);
      },
    );

    test('calculation can be suppressed entirely', () async {
      routes = FakeRouteRepository();
      container = build(routes);

      await controller().open('trip-1', calculateIfMissing: false);

      expect(routes.readCalls, 1);
      expect(routes.calculateCalls, 0);
    });
  });

  group('calculating', () {
    test('a second tap while one is in flight is ignored', () async {
      routes = FakeRouteRepository()
        ..calculateDelay = const Duration(milliseconds: 200);
      container = build(routes);

      await controller().open('trip-1', calculateIfMissing: false);

      final Future<void> first = controller().calculate();
      // The rapid-CTA case: one logical request.
      final Future<void> second = controller().calculate();
      final Future<void> third = controller().calculate();

      await Future.wait(<Future<void>>[first, second, third]);

      expect(routes.calculateCalls, 1);
    });

    test('a refresh asks again', () async {
      routes = FakeRouteRepository(calculated: true);
      container = build(routes);

      await controller().open('trip-1');
      await controller().calculate(refresh: true);

      expect(routes.calculateCalls, 1);
    });

    test('a failure keeps whatever was already on screen', () async {
      routes = FakeRouteRepository(calculated: true);
      container = build(routes);

      await controller().open('trip-1');
      expect(state().hasRoutes, isTrue);

      routes.nextCalculateError = const ApiException(
        code: ApiErrorCode.routeProviderUnavailable,
        message: 'down',
        status: 503,
      );
      await controller().calculate(refresh: true);

      // Losing a working route because a refresh failed punishes the customer
      // for our outage.
      expect(state().hasRoutes, isTrue);
      expect(state().failure, RouteFailure.providerUnavailable);
    });
  });

  group('what the screen is told about a failure', () {
    Future<RouteFailure?> failureFor(ApiErrorCode code, int status) async {
      routes = FakeRouteRepository()
        ..nextCalculateError = ApiException(
          code: code,
          message: 'x',
          status: status,
        );
      container = build(routes);

      await controller().open('trip-1');

      return state().failure;
    }

    test('each provider failure is told apart from the others', () async {
      // Six cases rather than one, because the customer's next move differs for
      // each and a single "something went wrong" offers the same useless button
      // to all of them.
      expect(
        await failureFor(ApiErrorCode.routeNoRouteFound, 422),
        RouteFailure.noRoute,
      );
      expect(
        await failureFor(ApiErrorCode.routeProviderRateLimited, 429),
        RouteFailure.rateLimited,
      );
      expect(
        await failureFor(ApiErrorCode.routeTimeout, 504),
        RouteFailure.timeout,
      );
      expect(
        await failureFor(ApiErrorCode.routeProviderUnavailable, 503),
        RouteFailure.providerUnavailable,
      );
      expect(
        await failureFor(ApiErrorCode.routeResponseInvalid, 502),
        RouteFailure.responseInvalid,
      );
      expect(await failureFor(ApiErrorCode.network, 0), RouteFailure.network);
      expect(
        await failureFor(ApiErrorCode.tripNotFound, 404),
        RouteFailure.tripGone,
      );
    });

    test(
      'retrying is not offered for the two that cannot be retried',
      () async {
        await failureFor(ApiErrorCode.routeNoRouteFound, 422);
        expect(state().isRetryable, isFalse);

        await failureFor(ApiErrorCode.tripNotFound, 404);
        expect(state().isRetryable, isFalse);

        await failureFor(ApiErrorCode.routeTimeout, 504);
        expect(state().isRetryable, isTrue);
      },
    );

    test(
      'an unknown code from a newer server degrades rather than crashing',
      () async {
        expect(
          await failureFor(ApiErrorCode.unknown, 500),
          RouteFailure.unknown,
        );
      },
    );
  });

  group('offline', () {
    test(
      'losing the network with a route in hand keeps it, and says so',
      () async {
        routes = FakeRouteRepository(calculated: true);
        container = build(routes);

        await controller().open('trip-1');

        routes.nextCalculateError = const ApiException(
          code: ApiErrorCode.network,
          message: 'offline',
          status: 0,
        );
        await controller().calculate(refresh: true);

        expect(state().hasRoutes, isTrue);
        // The screen shows a banner rather than implying the traffic figure is
        // current.
        expect(state().isOffline, isTrue);
      },
    );

    test(
      'losing the network with nothing in hand is not an offline route',
      () async {
        routes = FakeRouteRepository()
          ..nextReadError = const ApiException(
            code: ApiErrorCode.network,
            message: 'offline',
            status: 0,
          );
        container = build(routes);

        await controller().open('trip-1');

        expect(state().hasRoutes, isFalse);
        expect(state().isOffline, isFalse);
        expect(state().failure, RouteFailure.network);
      },
    );
  });

  group('selecting', () {
    test('the server’s answer replaces the set', () async {
      routes = FakeRouteRepository(alternatives: 3, calculated: true);
      container = build(routes);

      await controller().open('trip-1');
      await controller().select('route-1');

      expect(state().selected!.id, 'route-1');
      expect(state().routes!.routes.where((r) => r.isSelected).length, 1);
    });

    test('nothing is applied optimistically', () async {
      routes = FakeRouteRepository(alternatives: 2, calculated: true)
        ..nextSelectError = const ApiException(
          code: ApiErrorCode.routeStale,
          message: 'stale',
          status: 409,
        );
      container = build(routes);

      await controller().open('trip-1');
      await controller().select('route-1');

      // A selection the server refused must not linger on screen looking
      // accepted.
      expect(state().selected!.id, 'route-0');
      expect(state().failure, RouteFailure.stale);
    });

    test('a slow answer to an abandoned tap never lands', () async {
      routes = FakeRouteRepository(alternatives: 3, calculated: true)
        ..selectDelay = const Duration(milliseconds: 300);
      container = build(routes);

      await controller().open('trip-1');

      // Rapid A to B to C: the final state must match the last confirmed
      // action, not whichever request happened to finish last.
      final Future<void> first = controller().select('route-1');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final Future<void> second = controller().select('route-2');

      await Future.wait(<Future<void>>[first, second]);

      expect(state().selected!.id, 'route-2');
      expect(state().selectingRouteId, isNull);
    });
  });
}
