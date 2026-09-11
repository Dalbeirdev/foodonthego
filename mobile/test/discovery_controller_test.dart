import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/core/network/api_error_code.dart';
import 'package:foodonthego/core/network/api_exception.dart';
import 'package:foodonthego/domain/models/discovered_restaurant.dart';
import 'package:foodonthego/shared/state/discovery_controller.dart';
import 'package:foodonthego/shared/state/providers.dart';

import 'support/harness.dart';

/// The discovery screen's state.
///
/// Judged, like Module 06's, mostly on **not spending money**. Discovery is the
/// most expensive endpoint in the application, and this is the screen a customer
/// flicks in and out of while deciding where to eat.
void main() {
  late FakeDiscoveryRepository discovery;
  late ProviderContainer container;

  ProviderContainer build(FakeDiscoveryRepository repository) {
    final ProviderContainer c = ProviderContainer(
      overrides: [discoveryRepositoryProvider.overrideWithValue(repository)],
    );

    // The provider auto-disposes and the screen keeps it alive; a test with no
    // listener would tear the controller down between one read and the next.
    c.listen(
      discoveryControllerProvider,
      (DiscoveryState? _, DiscoveryState _) {},
      fireImmediately: true,
    );

    addTearDown(c.dispose);

    return c;
  }

  DiscoveryController controller() =>
      container.read(discoveryControllerProvider.notifier);

  DiscoveryState state() => container.read(discoveryControllerProvider);

  group('opening the screen', () {
    test('searches once', () async {
      discovery = FakeDiscoveryRepository();
      container = build(discovery);

      await controller().open('trip-1');

      expect(discovery.discoverCalls, 1);
      expect(state().hasResults, isTrue);
    });

    test('opening the same trip again does not search again', () async {
      discovery = FakeDiscoveryRepository();
      container = build(discovery);

      await controller().open('trip-1');
      await controller().open('trip-1');
      await controller().open('trip-1');

      // The single most important assertion in this file. A screen that
      // re-searches whenever the framework rebuilds it is a bill, and this one
      // can reach a routing provider.
      expect(discovery.discoverCalls, 1);
    });

    test('an empty answer is not searched again either', () async {
      discovery = FakeDiscoveryRepository(
        restaurants: <DiscoveredRestaurant>[],
      );
      container = build(discovery);

      await controller().open('trip-1');
      await controller().open('trip-1');

      // An empty result is an answer, and it cost as much to produce as a full
      // one.
      expect(discovery.discoverCalls, 1);
      expect(state().isEmptyResult, isTrue);
    });

    test('a different trip does search again', () async {
      discovery = FakeDiscoveryRepository();
      container = build(discovery);

      await controller().open('trip-1');
      await controller().open('trip-2');

      expect(discovery.discoverCalls, 2);
    });

    test('two rapid opens make one request', () async {
      discovery = FakeDiscoveryRepository()
        ..delay = const Duration(milliseconds: 150);
      container = build(discovery);

      final Future<void> first = controller().open('trip-1');
      final Future<void> second = controller().open('trip-1');

      await Future.wait(<Future<void>>[first, second]);

      expect(discovery.discoverCalls, 1);
    });
  });

  group('presentation', () {
    test('switching between map and list never re-searches', () async {
      discovery = FakeDiscoveryRepository();
      container = build(discovery);

      await controller().open('trip-1');

      controller().showView(DiscoveryView.map);
      controller().showView(DiscoveryView.list);
      controller().showView(DiscoveryView.map);

      // Somebody changing how they are looking at results is not asking for new
      // ones.
      expect(discovery.discoverCalls, 1);
      expect(state().view, DiscoveryView.map);
      expect(state().hasResults, isTrue);
    });

    test('the results survive a view change', () async {
      discovery = FakeDiscoveryRepository(
        restaurants: <DiscoveredRestaurant>[
          sampleRestaurant(id: 'a'),
          sampleRestaurant(id: 'b'),
        ],
      );
      container = build(discovery);

      await controller().open('trip-1');
      controller().showView(DiscoveryView.map);

      expect(state().restaurants, hasLength(2));
    });
  });

  group('selection', () {
    test('one field drives both the map and the list', () async {
      discovery = FakeDiscoveryRepository(
        restaurants: <DiscoveredRestaurant>[
          sampleRestaurant(id: 'a'),
          sampleRestaurant(id: 'b'),
        ],
      );
      container = build(discovery);

      await controller().open('trip-1');
      controller().selectRestaurant('b');

      // There is no second place for the map's idea of "selected" to disagree
      // with the list's.
      expect(state().selectedRestaurantId, 'b');
      expect(state().selected!.id, 'b');
    });

    test('selecting the same one again clears it', () async {
      discovery = FakeDiscoveryRepository();
      container = build(discovery);

      await controller().open('trip-1');
      controller().selectRestaurant('restaurant-1');
      controller().selectRestaurant('restaurant-1');

      // So a customer can get back to the whole-route view without hunting for
      // a close button.
      expect(state().selectedRestaurantId, isNull);
    });

    test('a new search clears a selection from the old one', () async {
      discovery = FakeDiscoveryRepository();
      container = build(discovery);

      await controller().open('trip-1');
      controller().selectRestaurant('restaurant-1');

      await controller().open('trip-2');

      expect(state().selectedRestaurantId, isNull);
    });

    test(
      'selecting something that is not in the results yields null',
      () async {
        discovery = FakeDiscoveryRepository();
        container = build(discovery);

        await controller().open('trip-1');
        controller().selectRestaurant('not-in-the-list');

        expect(state().selected, isNull);
      },
    );
  });

  group('what the screen is told about a failure', () {
    Future<DiscoveryFailure?> failureFor(ApiErrorCode code, int status) async {
      discovery = FakeDiscoveryRepository()
        ..nextError = ApiException(code: code, message: 'x', status: status);
      container = build(discovery);

      await controller().open('trip-1');

      return state().failure;
    }

    test('each failure is told apart from the others', () async {
      // The customer's next move differs for each: a route that is not ready
      // sends them back a screen, a rate limit asks them to wait, an outage
      // asks them to try again.
      expect(
        await failureFor(ApiErrorCode.routeNotReady, 409),
        DiscoveryFailure.routeNotReady,
      );
      expect(
        await failureFor(ApiErrorCode.routeStale, 409),
        DiscoveryFailure.routeNotReady,
      );
      expect(
        await failureFor(ApiErrorCode.tripNotFound, 404),
        DiscoveryFailure.tripGone,
      );
      expect(
        await failureFor(ApiErrorCode.discoveryRateLimited, 429),
        DiscoveryFailure.rateLimited,
      );
      expect(
        await failureFor(ApiErrorCode.discoveryFailed, 500),
        DiscoveryFailure.discoveryFailed,
      );
      expect(
        await failureFor(ApiErrorCode.network, 0),
        DiscoveryFailure.network,
      );
      expect(
        await failureFor(ApiErrorCode.serverError, 500),
        DiscoveryFailure.serverError,
      );
    });

    test('retrying is not offered where it cannot help', () async {
      await failureFor(ApiErrorCode.routeNotReady, 409);
      expect(state().isRetryable, isFalse);

      await failureFor(ApiErrorCode.tripNotFound, 404);
      expect(state().isRetryable, isFalse);

      await failureFor(ApiErrorCode.discoveryFailed, 500);
      expect(state().isRetryable, isTrue);
    });

    test(
      'an unknown code from a newer server degrades rather than crashing',
      () async {
        expect(
          await failureFor(ApiErrorCode.unknown, 500),
          DiscoveryFailure.unknown,
        );
      },
    );

    test('a retry after a failure does search again', () async {
      discovery = FakeDiscoveryRepository()
        ..nextError = const ApiException(
          code: ApiErrorCode.discoveryFailed,
          message: 'x',
          status: 500,
        );
      container = build(discovery);

      await controller().open('trip-1');
      expect(state().failure, DiscoveryFailure.discoveryFailed);

      await controller().retry();

      expect(discovery.discoverCalls, 2);
      expect(state().hasResults, isTrue);
      expect(state().failure, isNull);
    });
  });

  group('offline', () {
    test(
      'losing the network with results in hand keeps them, and says so',
      () async {
        discovery = FakeDiscoveryRepository();
        container = build(discovery);

        await controller().open('trip-1');

        discovery.nextError = const ApiException(
          code: ApiErrorCode.network,
          message: 'offline',
          status: 0,
        );
        await controller().retry();

        // The screen shows a banner rather than implying opening times are
        // current.
        expect(state().hasResults, isTrue);
        expect(state().isOffline, isTrue);
      },
    );

    test(
      'losing the network with nothing in hand is not an offline result',
      () async {
        discovery = FakeDiscoveryRepository()
          ..nextError = const ApiException(
            code: ApiErrorCode.network,
            message: 'offline',
            status: 0,
          );
        container = build(discovery);

        await controller().open('trip-1');

        expect(state().hasResults, isFalse);
        expect(state().isOffline, isFalse);
        expect(state().failure, DiscoveryFailure.network);
      },
    );
  });

  group('closed only', () {
    test('is distinct from empty', () async {
      discovery = FakeDiscoveryRepository(
        restaurants: <DiscoveredRestaurant>[
          sampleRestaurant(availability: RestaurantAvailability.closed),
        ],
      );
      container = build(discovery);

      await controller().open('trip-1');

      // "There is nothing on this road" and "there are four places and all of
      // them are shut" call for different words.
      expect(state().isEmptyResult, isFalse);
      expect(state().isClosedOnly, isTrue);
      expect(state().hasResults, isTrue);
    });
  });
}
