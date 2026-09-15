import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/core/format/journey_measures.dart';
import 'package:foodonthego/core/geo/polyline_codec.dart';
import 'package:foodonthego/domain/models/trip.dart';
import 'package:foodonthego/domain/models/trip_route.dart';

import 'support/harness.dart';

/// The route contract, from the client's side.
///
/// The theme throughout: **nothing is invented on the way in**. A route with no
/// distance, no duration or no geometry is not a route, and the app refuses to
/// build one rather than rendering a confident "0 km".
void main() {
  group('the polyline codec', () {
    test("decodes the example from Google's own specification", () {
      final List<GeoPoint> points = PolylineCodec.decode(
        '_p~iF~ps|U_ulLnnqC_mqNvxq`@',
      );

      expect(points, hasLength(3));
      expect(points[0].latitude, closeTo(38.5, 0.00001));
      expect(points[0].longitude, closeTo(-120.2, 0.00001));
      expect(points[2].latitude, closeTo(43.252, 0.00001));
    });

    test('round trips', () {
      const List<GeoPoint> original = <GeoPoint>[
        GeoPoint(28.5494, 77.2001),
        GeoPoint(26.8242, 75.8122),
      ];

      final List<GeoPoint> decoded = PolylineCodec.decode(
        PolylineCodec.encode(original),
      );

      expect(decoded[0].latitude, closeTo(28.5494, 0.00001));
      expect(decoded[1].longitude, closeTo(75.8122, 0.00001));
    });

    test('refuses an empty polyline', () {
      expect(
        () => PolylineCodec.decode(''),
        throwsA(isA<PolylineFormatException>()),
      );
    });

    test('refuses a truncated polyline rather than reading half of it', () {
      // Truncation is what a proxy or a length limit produces, and half a route
      // drawn confidently on a map is worse than none.
      expect(
        () => PolylineCodec.decode('_p~iF~ps|U_ulLnnq'),
        throwsA(isA<PolylineFormatException>()),
      );
    });

    test('measures the distance between two known points', () {
      // Hauz Khas to Jaipur airport as the crow flies: about 235 km. Used to
      // sanity-check geometry, never to derive a route's length — the road is
      // some forty kilometres longer.
      final double metres = PolylineCodec.metresBetween(
        const GeoPoint(28.5494, 77.2001),
        const GeoPoint(26.8242, 75.8122),
      );

      expect(metres / 1000, closeTo(235, 5));
    });
  });

  group('TripRoute.fromJson', () {
    Map<String, dynamic> payload() => <String, dynamic>{
      'route_id': 'route-1',
      'provider': 'google',
      'provider_route_index': 0,
      'summary': 'via NH 48',
      'distance_meters': 278000,
      'duration_seconds': 16200,
      'traffic_duration_seconds': 17100,
      'traffic_delay_seconds': 900,
      'encoded_polyline': sampleRouteGeometry(),
      'bounds': <String, dynamic>{
        'north': '28.5494000',
        'south': '26.8242000',
        'east': '77.2001000',
        'west': '75.8122000',
      },
      'is_recommended': true,
      'is_selected': true,
      'calculated_at': '2026-09-05T09:00:00+00:00',
    };

    test('reads the figures as numbers', () {
      final TripRoute route = TripRoute.fromJson(payload())!;

      expect(route.distanceMeters, 278000);
      expect(route.durationSeconds, 16200);
      expect(route.trafficDurationSeconds, 17100);
      expect(route.trafficDelaySeconds, 900);
      expect(route.isRecommended, isTrue);
      expect(route.calculatedAt!.isUtc, isTrue);
    });

    test('leads with the traffic-aware duration when there is one', () {
      final TripRoute route = TripRoute.fromJson(payload())!;

      expect(route.effectiveDurationSeconds, 17100);
      expect(route.hasTraffic, isTrue);
    });

    test('falls back to the base duration when there is no traffic figure', () {
      final TripRoute route = TripRoute.fromJson(
        payload()
          ..['traffic_duration_seconds'] = null
          ..['traffic_delay_seconds'] = null,
      )!;

      // Absence of a traffic reading is not a claim that traffic costs nothing.
      expect(route.effectiveDurationSeconds, 16200);
      expect(route.hasTraffic, isFalse);
    });

    test('rejects a route with no distance', () {
      expect(TripRoute.fromJson(payload()..['distance_meters'] = 0), isNull);
      expect(TripRoute.fromJson(payload()..['distance_meters'] = -1), isNull);
      expect(TripRoute.fromJson(payload()..remove('distance_meters')), isNull);
    });

    test('rejects a route with no duration', () {
      expect(TripRoute.fromJson(payload()..['duration_seconds'] = 0), isNull);
    });

    test('rejects a route with no geometry', () {
      // The map is about to draw this.
      expect(TripRoute.fromJson(payload()..['encoded_polyline'] = ''), isNull);
    });

    test(
      'geometry that will not decode draws nothing rather than throwing',
      () {
        final TripRoute route = TripRoute.fromJson(
          payload()..['encoded_polyline'] = 'not-a-polyline-at-all',
        )!;

        // Degrades to "no line on the map" rather than taking the screen down.
        expect(() => route.points(), returnsNormally);
      },
    );

    test('bounds with crossed corners are dropped', () {
      final TripRoute route = TripRoute.fromJson(
        payload()
          ..['bounds'] = <String, dynamic>{
            'north': '10.0',
            'south': '40.0',
            'east': '77.0',
            'west': '75.0',
          },
      )!;

      // A box with its corners crossed frames nothing, and asking a map to fit
      // it puts the camera over the ocean.
      expect(route.bounds, isNull);
    });

    test('a development route is marked as not from a real provider', () {
      expect(
        TripRoute.fromJson(payload()..['provider'] = 'development')!
            .isFromRealProvider,
        isFalse,
      );
      expect(TripRoute.fromJson(payload())!.isFromRealProvider, isTrue);
    });
  });

  group('a trip carrying a route summary', () {
    Map<String, dynamic> trip({Object? selectedRoute}) => <String, dynamic>{
      'id': 't1',
      'status': 'ROUTE_PENDING',
      'route_status': 'READY',
      'origin': <String, dynamic>{'latitude': '28.5', 'longitude': '77.2'},
      'destination': <String, dynamic>{'latitude': '26.8', 'longitude': '75.8'},
      'selected_route': selectedRoute,
    };

    test('reports a route only when the server sent one', () {
      final Trip withRoute = Trip.fromJson(
        trip(
          selectedRoute: <String, dynamic>{
            'route_id': 'r1',
            'distance_meters': 278000,
            'duration_seconds': 16200,
          },
        ),
      );

      expect(withRoute.hasRoute, isTrue);
      expect(withRoute.selectedRoute!.distanceMeters, 278000);
    });

    test('a READY status with no summary is not a route', () {
      // This is what the server sends when the endpoints moved. Trusting the
      // status alone would render an empty distance.
      expect(Trip.fromJson(trip()).hasRoute, isFalse);
    });

    test('the new route states are understood', () {
      expect(RouteStatus.fromWire('NO_ROUTE'), RouteStatus.noRoute);
      expect(RouteStatus.fromWire('STALE'), RouteStatus.stale);
    });

    test('retrying a no-route answer is not offered', () {
      // The provider's considered answer. Asking again spends a request to be
      // told the same thing.
      expect(RouteStatus.noRoute.isRetryable, isFalse);
      expect(RouteStatus.failed.isRetryable, isTrue);
      expect(RouteStatus.stale.isRetryable, isTrue);
    });
  });

  group('formatting', () {
    test('distance reads the way a person would say it', () {
      expect(JourneyMeasures.distance(278000), '278 km');
      expect(JourneyMeasures.distance(4200), '4.2 km');
      // "0.85 km" is a number somebody has to convert in their head.
      expect(JourneyMeasures.distance(850), '850 m');
    });

    test('duration reads the way a person would say it', () {
      expect(JourneyMeasures.duration(16200), '4 hr 30 min');
      expect(JourneyMeasures.duration(2700), '45 min');
      expect(JourneyMeasures.duration(7200), '2 hr');
    });

    test('a journey that exists never takes zero minutes', () {
      // A zero reads as an error rather than as a very short drive.
      expect(JourneyMeasures.duration(20), '1 min');
    });

    test('a traffic delay under a minute is not a delay', () {
      // "+0 min" is a claim about the roads dressed up as a measurement.
      expect(JourneyMeasures.trafficDelay(30), isNull);
      expect(JourneyMeasures.trafficDelay(null), isNull);
      expect(JourneyMeasures.trafficDelay(900), '+15 min');
    });

    test('a comparison is only offered when it is worth saying', () {
      expect(
        JourneyMeasures.comparison(
          metres: 265000,
          seconds: 17040,
          againstMetres: 278000,
          againstSeconds: 16200,
        ),
        '14 min longer',
      );

      // A minute on a four-hour drive is noise the provider itself would not
      // stand behind.
      expect(
        JourneyMeasures.comparison(
          metres: 278200,
          seconds: 16230,
          againstMetres: 278000,
          againstSeconds: 16200,
        ),
        isNull,
      );
    });

    test('a shorter route is described as shorter', () {
      expect(
        JourneyMeasures.comparison(
          metres: 265000,
          seconds: 16210,
          againstMetres: 278000,
          againstSeconds: 16200,
        ),
        '13 km shorter',
      );
    });

    test('how old a calculation is, said plainly', () {
      final DateTime now = DateTime.utc(2026, 9, 5, 9, 30);

      expect(
        JourneyMeasures.calculatedAgo(
          DateTime.utc(2026, 9, 5, 9, 29, 30),
          now: now,
        ),
        'Calculated just now',
      );
      expect(
        JourneyMeasures.calculatedAgo(
          DateTime.utc(2026, 9, 5, 9, 24),
          now: now,
        ),
        'Calculated 6 minutes ago',
      );
      expect(
        JourneyMeasures.calculatedAgo(
          DateTime.utc(2026, 9, 5, 7, 30),
          now: now,
        ),
        'Calculated 2 hours ago',
      );
    });
  });
}
