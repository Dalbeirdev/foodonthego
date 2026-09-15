import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/core/network/api_error_code.dart';
import 'package:foodonthego/core/network/api_exception.dart';
import 'package:foodonthego/domain/models/restaurant_detail.dart';
import 'package:foodonthego/shared/state/providers.dart';
import 'package:foodonthego/shared/state/restaurant_detail_controller.dart';

import 'support/harness.dart';

/// The restaurant detail screen's state.
///
/// Judged mostly on two things: that the newest request wins, and that a
/// restaurant which has been withdrawn stops being shown.
void main() {
  late FakeRestaurantRepository restaurants;
  late ProviderContainer container;

  ProviderContainer build(FakeRestaurantRepository repository) {
    final ProviderContainer c = ProviderContainer(
      overrides: [restaurantRepositoryProvider.overrideWithValue(repository)],
    );

    // The provider auto-disposes and the screen keeps it alive; a test with no
    // listener would tear the controller down between one read and the next.
    c.listen(
      restaurantDetailControllerProvider,
      (RestaurantDetailState? _, RestaurantDetailState _) {},
      fireImmediately: true,
    );

    addTearDown(c.dispose);

    return c;
  }

  RestaurantDetailController controller() =>
      container.read(restaurantDetailControllerProvider.notifier);

  RestaurantDetailState state() =>
      container.read(restaurantDetailControllerProvider);

  Future<void> openOne({
    FakeRestaurantRepository? repository,
    String restaurantId = 'restaurant-1',
  }) async {
    restaurants = repository ?? FakeRestaurantRepository();
    container = build(restaurants);

    await controller().open(tripId: 'trip-1', restaurantId: restaurantId);
  }

  group('opening', () {
    test('it asks for the restaurant on the trip it was given', () async {
      await openOne();

      expect(restaurants.calls, 1);
      expect(restaurants.lastRequest!.tripId, 'trip-1');
      expect(restaurants.lastRequest!.restaurantId, 'restaurant-1');
      expect(state().hasDetail, isTrue);
    });

    test('reopening the same restaurant does not ask again', () async {
      await openOne();

      await controller().open(tripId: 'trip-1', restaurantId: 'restaurant-1');

      // A rebuild is not a new question.
      expect(restaurants.calls, 1);
    });

    test('a preview is shown immediately and then replaced', () async {
      restaurants = FakeRestaurantRepository()
        ..delay = const Duration(milliseconds: 40);
      container = build(restaurants);

      final Future<void> opening = controller().open(
        tripId: 'trip-1',
        restaurantId: 'restaurant-1',
        preview: sampleRestaurant(name: 'From The Card'),
      );

      // The transition has a name in it before the server answers.
      expect(state().name, 'From The Card');
      expect(state().hasDetail, isFalse);

      await opening;

      // And the server's answer takes over. A preview that stayed would go on
      // claiming a restaurant is open long after it stopped being.
      expect(state().hasDetail, isTrue);
    });

    test('opening a different restaurant clears the previous one', () async {
      await openOne();

      restaurants.delay = const Duration(milliseconds: 40);

      final Future<void> opening = controller().open(
        tripId: 'trip-1',
        restaurantId: 'restaurant-2',
      );

      // The old photographs must not sit under the new name.
      expect(state().hasDetail, isFalse);

      await opening;

      expect(restaurants.lastRequest!.restaurantId, 'restaurant-2');
    });
  });

  group('answers arriving out of order', () {
    test('a slow first restaurant never overwrites a fast second', () async {
      restaurants =
          FakeRestaurantRepository(
              responder: (String _, String restaurantId) =>
                  sampleRestaurantDetail(
                    restaurant: sampleRestaurant(
                      id: restaurantId,
                      name: restaurantId == 'slow'
                          ? 'Slow Kitchen'
                          : 'Fast Kitchen',
                    ),
                  ),
            )
            ..delayFor = ((String restaurantId) => restaurantId == 'slow'
                ? const Duration(milliseconds: 80)
                : const Duration(milliseconds: 10));

      container = build(restaurants);

      unawaitedOpen(controller(), 'slow');
      unawaitedOpen(controller(), 'fast');

      await Future<void>.delayed(const Duration(milliseconds: 150));

      // Without the generation check the slow one lands last, putting one
      // restaurant's page under another restaurant's name.
      expect(state().detail!.name, 'Fast Kitchen');
    });

    test('a stale failure does not put an error over a good page', () async {
      restaurants = FakeRestaurantRepository()
        ..delayFor = ((String restaurantId) => restaurantId == 'slow'
            ? const Duration(milliseconds: 80)
            : const Duration(milliseconds: 10))
        // Only the request the customer has navigated away from fails.
        ..errorFor = ((String restaurantId) => restaurantId == 'slow'
            ? ApiException(code: ApiErrorCode.serverError, message: 'boom')
            : null);

      container = build(restaurants);

      unawaitedOpen(controller(), 'slow');
      unawaitedOpen(controller(), 'fast');

      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(state().hasDetail, isTrue);
    });
  });

  group('failures', () {
    Future<void> failWith(ApiErrorCode code) async {
      restaurants = FakeRestaurantRepository()
        ..nextError = ApiException(code: code, message: 'no');
      container = build(restaurants);

      await controller().open(tripId: 'trip-1', restaurantId: 'restaurant-1');
    }

    test(
      'a withdrawn restaurant is its own failure, not a generic error',
      () async {
        await failWith(ApiErrorCode.restaurantUnavailable);

        expect(state().failure, RestaurantDetailFailure.withdrawn);
        // And it is not retryable: it will not come back because the customer
        // pressed a button, and offering the button implies it might.
        expect(state().isRetryable, isFalse);
      },
    );

    test('a restaurant on another road says so', () async {
      await failWith(ApiErrorCode.restaurantOutsideRoute);

      expect(state().failure, RestaurantDetailFailure.outsideRoute);
      expect(state().isRetryable, isFalse);
    });

    test(
      'a missing restaurant and an unauthorised one look the same',
      () async {
        await failWith(ApiErrorCode.restaurantNotFound);

        expect(state().failure, RestaurantDetailFailure.notFound);
      },
    );

    test(
      'a route that is not ready sends the customer to the route screen',
      () async {
        await failWith(ApiErrorCode.routeNotReady);

        expect(state().failure, RestaurantDetailFailure.routeNotReady);
      },
    );

    test('an outage is retryable', () async {
      await failWith(ApiErrorCode.serverError);

      expect(state().failure, RestaurantDetailFailure.serverError);
      expect(state().isRetryable, isTrue);
    });

    test('an unreadable body is ours and unexplained, not a crash', () async {
      restaurants = FakeRestaurantRepository(
        responder: (String _, String _) =>
            throw StateError('unreadable response'),
      );
      container = build(restaurants);

      await controller().open(tripId: 'trip-1', restaurantId: 'restaurant-1');

      expect(state().failure, RestaurantDetailFailure.serverError);
    });
  });

  group('refreshing', () {
    test('a failed refresh keeps the page and says it is offline', () async {
      await openOne();

      restaurants.nextError = ApiException(
        code: ApiErrorCode.network,
        message: 'offline',
      );

      await controller().refresh();

      // Losing what a customer already has because a refresh failed punishes
      // them for our outage.
      expect(state().hasDetail, isTrue);
      expect(state().isOffline, isTrue);
    });

    test(
      'a refresh that finds the restaurant withdrawn takes the page away',
      () async {
        await openOne();

        restaurants.nextError = ApiException(
          code: ApiErrorCode.restaurantUnavailable,
          message: 'gone',
        );

        await controller().refresh();

        // The opposite of the case above, and deliberately so: leaving it up
        // would present a suspended business as though it were trading.
        expect(state().hasDetail, isFalse);
        expect(state().failure, RestaurantDetailFailure.withdrawn);
      },
    );

    test('a successful refresh replaces what was on screen', () async {
      restaurants = FakeRestaurantRepository(
        responder: (String _, String _) => sampleRestaurantDetail(
          ordering: RestaurantOrderingState.openPaused,
        ),
      );
      container = build(restaurants);

      await controller().open(tripId: 'trip-1', restaurantId: 'restaurant-1');
      await controller().refresh();

      expect(restaurants.calls, 2);
      expect(state().detail!.ordering, RestaurantOrderingState.openPaused);
    });
  });

  group('screen state', () {
    test('the hours section remembers whether it is open', () async {
      await openOne();

      expect(state().hoursExpanded, isFalse);
      controller().toggleHours();
      expect(state().hoursExpanded, isTrue);
    });

    test('the gallery remembers which photograph is showing', () async {
      await openOne();

      controller().galleryMovedTo(2);

      expect(state().galleryIndex, 2);
    });
  });
}

/// Starts an open without awaiting it, so two can be in flight at once.
void unawaitedOpen(RestaurantDetailController controller, String id) {
  controller.open(tripId: 'trip-1', restaurantId: id);
}
