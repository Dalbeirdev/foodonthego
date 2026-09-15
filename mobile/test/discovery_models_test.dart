import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/domain/models/discovered_restaurant.dart';

/// The discovery contract, from the client's side.
///
/// The theme, as with routes: **nothing is invented on the way in**. A
/// restaurant with no position, no name or no route relation is not a result,
/// and the app refuses to build one rather than putting an unlabelled marker on
/// a map.
void main() {
  Map<String, dynamic> payload() => <String, dynamic>{
    'id': 'restaurant-1',
    'name': 'Highway Spice Kitchen',
    'short_name': 'Highway Spice',
    'city': 'Behror',
    'location': <String, dynamic>{
      'latitude': '27.6916000',
      'longitude': '76.5096000',
    },
    'cuisines': <String>['North Indian', 'Vegetarian'],
    'facilities': <String>['Parking', 'Restroom'],
    'price_level': 2,
    'rating': null,
    'review_count': null,
    'availability': 'OPEN',
    'is_accepting_orders': true,
    'route': <String, dynamic>{
      'proximity_meters': 1800,
      'detour_distance_meters': 1700,
      'detour_duration_seconds': 240,
      'distance_ahead_meters': 68400,
      'time_ahead_seconds': 3600,
      'progress_fraction': 0.42,
      'requires_backtracking': false,
    },
  };

  group('DiscoveredRestaurant.fromJson', () {
    test('reads every figure as a number', () {
      final DiscoveredRestaurant r = DiscoveredRestaurant.fromJson(payload())!;

      expect(r.id, 'restaurant-1');
      expect(r.route.proximityMetres, 1800);
      expect(r.route.detourDurationSeconds, 240);
      expect(r.route.distanceAheadMetres, 68400);
      expect(r.route.timeAheadSeconds, 3600);
      expect(r.cuisines, <String>['North Indian', 'Vegetarian']);
    });

    test('prefers the short name for a marker or a narrow card', () {
      expect(
        DiscoveredRestaurant.fromJson(payload())!.displayName,
        'Highway Spice',
      );
      expect(
        DiscoveredRestaurant.fromJson(payload()..remove('short_name'))!
            .displayName,
        'Highway Spice Kitchen',
      );
    });

    test('rejects a restaurant with no position', () {
      // The map is about to draw this.
      expect(
        DiscoveredRestaurant.fromJson(payload()..remove('location')),
        isNull,
      );
      expect(
        DiscoveredRestaurant.fromJson(
          payload()..['location'] = <String, dynamic>{'latitude': '27.6'},
        ),
        isNull,
      );
    });

    test('rejects the (0, 0) sentinel', () {
      // Null Island is what a half-populated record looks like, not a
      // restaurant.
      expect(
        DiscoveredRestaurant.fromJson(
          payload()
            ..['location'] = <String, dynamic>{'latitude': 0, 'longitude': 0},
        ),
        isNull,
      );
    });

    test('rejects a restaurant with no name or no id', () {
      expect(DiscoveredRestaurant.fromJson(payload()..['name'] = ''), isNull);
      expect(DiscoveredRestaurant.fromJson(payload()..['id'] = ''), isNull);
    });

    test('rejects a restaurant with no relation to the route', () {
      // Without it the card has no "68 km ahead" to show, which is the whole
      // reason the card exists.
      expect(DiscoveredRestaurant.fromJson(payload()..remove('route')), isNull);
      expect(
        DiscoveredRestaurant.fromJson(
          payload()..['route'] = <String, dynamic>{'proximity_meters': 100},
        ),
        isNull,
      );
    });

    test('an absent detour stays absent rather than becoming zero', () {
      final DiscoveredRestaurant r = DiscoveredRestaurant.fromJson(
        payload()
          ..['route'] = <String, dynamic>{
            'proximity_meters': 1800,
            'distance_ahead_meters': 68400,
            'detour_distance_meters': null,
            'detour_duration_seconds': null,
          },
      )!;

      // A zero would be a claim that stopping is free.
      expect(r.route.detourDurationSeconds, isNull);
      expect(r.route.hasDetour, isFalse);
    });

    test('an absent rating is null, not a hopeful number', () {
      final DiscoveredRestaurant r = DiscoveredRestaurant.fromJson(payload())!;

      expect(r.rating, isNull);
      expect(r.hasRating, isFalse);
    });

    test('a rating that exists is read', () {
      final DiscoveredRestaurant r = DiscoveredRestaurant.fromJson(
        payload()
          ..['rating'] = '4.5'
          ..['review_count'] = 214,
      )!;

      expect(r.rating, 4.5);
      expect(r.reviewCount, 214);
    });

    test('a paused restaurant carries its own flag', () {
      final DiscoveredRestaurant r = DiscoveredRestaurant.fromJson(
        payload()
          ..['availability'] = 'NOT_ACCEPTING_ORDERS'
          ..['is_accepting_orders'] = false,
      )!;

      expect(r.availability, RestaurantAvailability.notAcceptingOrders);
      expect(r.isAcceptingOrders, isFalse);
      // Never actionable, whatever the clock says.
      expect(r.availability.isActionable, isFalse);
    });

    test('backtracking survives the wire', () {
      final DiscoveredRestaurant r = DiscoveredRestaurant.fromJson(
        payload()
          ..['route'] = <String, dynamic>{
            'proximity_meters': 2900,
            'distance_ahead_meters': 0,
            'requires_backtracking': true,
          },
      )!;

      expect(r.route.requiresBacktracking, isTrue);
    });
  });

  group('availability', () {
    test('every documented state is understood', () {
      expect(
        RestaurantAvailability.fromWire('OPEN'),
        RestaurantAvailability.open,
      );
      expect(
        RestaurantAvailability.fromWire('CLOSED'),
        RestaurantAvailability.closed,
      );
      expect(
        RestaurantAvailability.fromWire('OPENING_SOON'),
        RestaurantAvailability.openingSoon,
      );
      expect(
        RestaurantAvailability.fromWire('CLOSING_SOON'),
        RestaurantAvailability.closingSoon,
      );
      expect(
        RestaurantAvailability.fromWire('NOT_ACCEPTING_ORDERS'),
        RestaurantAvailability.notAcceptingOrders,
      );
    });

    test('a state a newer server invented degrades to unknown', () {
      // Never to "open". A confident wrong answer sends somebody to a locked
      // door.
      expect(
        RestaurantAvailability.fromWire('SOMETHING_NEW'),
        RestaurantAvailability.unknown,
      );
      expect(
        RestaurantAvailability.fromWire(null),
        RestaurantAvailability.unknown,
      );
    });

    test('only open and closing soon are actionable', () {
      expect(RestaurantAvailability.open.isActionable, isTrue);
      expect(RestaurantAvailability.closingSoon.isActionable, isTrue);
      expect(RestaurantAvailability.openingSoon.isActionable, isFalse);
      expect(RestaurantAvailability.closed.isActionable, isFalse);
      expect(RestaurantAvailability.notAcceptingOrders.isActionable, isFalse);
      expect(RestaurantAvailability.unknown.isActionable, isFalse);
    });
  });

  group('RestaurantDiscovery.fromJson', () {
    Map<String, dynamic> result({
      List<dynamic>? restaurants,
    }) => <String, dynamic>{
      'route': <String, dynamic>{'route_id': 'route-1', 'provider': 'google'},
      'restaurants': restaurants ?? <dynamic>[],
      'meta': <String, dynamic>{
        'returned': 0,
        'closed_only': false,
        'from_cache': false,
        'corridor_meters': 5000,
        'candidates_considered': 42,
      },
    };

    test('an unreadable restaurant is dropped, not half-built', () {
      final RestaurantDiscovery d = RestaurantDiscovery.fromJson(
        result(
          restaurants: <dynamic>[
            payload(),
            <String, dynamic>{'id': 'broken'},
          ],
        ),
      );

      expect(d.restaurants, hasLength(1));
      expect(d.restaurants.first.id, 'restaurant-1');
    });

    test('an empty result is a result', () {
      final RestaurantDiscovery d = RestaurantDiscovery.fromJson(result());

      expect(d.isEmpty, isTrue);
      // So the empty state can say "within 5 km of your route".
      expect(d.corridorMetres, 5000);
    });

    test('a development route is marked as not from a real provider', () {
      final Map<String, dynamic> raw = result();
      (raw['route'] as Map<String, dynamic>)['provider'] = 'development';

      expect(RestaurantDiscovery.fromJson(raw).isFromRealProvider, isFalse);
      expect(RestaurantDiscovery.fromJson(result()).isFromRealProvider, isTrue);
    });

    test('closed-only travels as its own fact', () {
      final Map<String, dynamic> raw = result(
        restaurants: <dynamic>[payload()],
      );
      (raw['meta'] as Map<String, dynamic>)['closed_only'] = true;

      expect(RestaurantDiscovery.fromJson(raw).closedOnly, isTrue);
    });
  });
}
