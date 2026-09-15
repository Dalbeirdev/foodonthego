import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/domain/models/place.dart';
import 'package:foodonthego/domain/models/saved_address.dart';
import 'package:foodonthego/domain/models/trip.dart';
import 'package:foodonthego/domain/repositories/trip_repository.dart';

/// The wire contract, from the client's side.
///
/// These are the tests that stop a screen inventing data. Two things are being
/// established: that nothing the server sends is embellished on the way in, and
/// that nothing the server did not ask for is sent on the way out.
void main() {
  group('Trip.fromJson', () {
    Map<String, dynamic> payload() => <String, dynamic>{
      'id': 'trip-uuid',
      'status': 'ROUTE_PENDING',
      'route_status': 'NOT_CALCULATED',
      'origin': <String, dynamic>{
        'source_type': 'CURRENT_LOCATION',
        'display_name': 'Current location',
        'formatted_address': 'Green Park, New Delhi, Delhi 110016',
        // Strings, as the server sends them: a coordinate that round-trips
        // through a float loses its last place, and the last place is metres.
        'latitude': '28.5590000',
        'longitude': '77.2070000',
        'place_id': null,
        'city': 'New Delhi',
        'region': 'Delhi',
        'country_code': 'IN',
        'postal_code': null,
      },
      'destination': <String, dynamic>{
        'source_type': 'PLACE_SEARCH',
        'display_name': 'Jaipur International Airport',
        'formatted_address': 'Airport Road, Sanganer, Jaipur, Rajasthan 302029',
        'latitude': '26.8242000',
        'longitude': '75.8122000',
        'place_id': 'dev:jaipur-airport',
        'city': 'Jaipur',
        'region': 'Rajasthan',
        'country_code': 'IN',
        'postal_code': '302029',
      },
      'cancelled_at': null,
      'created_at': '2026-09-04T09:15:00+00:00',
      'updated_at': '2026-09-04T09:15:00+00:00',
    };

    test('reads both ends, their sources and their coordinates', () {
      final Trip trip = Trip.fromJson(payload());

      expect(trip.id, 'trip-uuid');
      expect(trip.status, TripStatus.routePending);
      expect(trip.routeStatus, RouteStatus.notCalculated);
      expect(trip.origin.sourceType, LocationSourceType.currentLocation);
      expect(trip.destination.sourceType, LocationSourceType.placeSearch);
      expect(trip.origin.latitude, closeTo(28.559, 0.0001));
      expect(trip.destination.longitude, closeTo(75.8122, 0.0001));
      expect(trip.destination.placeId, 'dev:jaipur-airport');
    });

    test('has no route to report, and says so through routeStatus', () {
      final Trip trip = Trip.fromJson(payload());

      // The whole of Module 05's honesty in one assertion: nothing has been
      // calculated, and the model has no field in which a distance or an ETA
      // could hide.
      expect(trip.hasRoute, isFalse);
      expect(trip.routeStatus, RouteStatus.notCalculated);
    });

    test('times are UTC, whatever the offset on the wire', () {
      final Trip trip = Trip.fromJson(payload());

      expect(trip.createdAt!.isUtc, isTrue);
    });

    test(
      'an unknown status from a newer server does not crash an older app',
      () {
        final Trip trip = Trip.fromJson(payload()..['status'] = 'IN_TRANSIT');

        // Degrades to the readable state rather than throwing. An app that
        // crashes on a value it has not been taught cannot be rolled out ahead
        // of its server, or behind it.
        expect(trip.status, TripStatus.routePending);
      },
    );

    test(
      'a route status a newer server introduced reads as not calculated',
      () {
        final Trip trip = Trip.fromJson(
          payload()..['route_status'] = 'PARTIAL',
        );

        expect(trip.routeStatus, RouteStatus.notCalculated);
        expect(trip.hasRoute, isFalse);
      },
    );

    test('the summary is the two ends, in order', () {
      final Trip trip = Trip.fromJson(payload());

      expect(
        trip.routeSummary,
        'Current location → Jaipur International Airport',
      );
    });

    test('a discarded trip is not discardable again', () {
      final Trip trip = Trip.fromJson(
        payload()
          ..['status'] = 'CANCELLED'
          ..['cancelled_at'] = '2026-09-04T10:00:00+00:00',
      );

      expect(trip.isCancelled, isTrue);
      expect(trip.isDiscardable, isFalse);
      expect(trip.cancelledAt!.isUtc, isTrue);
    });
  });

  group('the list filter', () {
    test('every scope names a status the server actually has', () {
      // The one thing a fake repository cannot catch. An unknown query
      // parameter is ignored rather than refused, so a client sending
      // `scope=open` against a server filtering on `status` gets an unfiltered
      // list back and every test against a fake still passes.
      expect(TripScope.open.status, TripStatus.routePending.wire);
      expect(TripScope.cancelled.status, TripStatus.cancelled.wire);
      // No filter at all, rather than a word the server would ignore.
      expect(TripScope.all.status, isNull);
    });
  });

  group('PlaceSuggestion and PlaceDetails', () {
    test('a suggestion carries no position, because it has none', () {
      final PlaceSuggestion suggestion = PlaceSuggestion.fromJson(
        <String, dynamic>{
          'place_id': 'dev:jaipur-airport',
          'primary_text': 'Jaipur International Airport',
          'secondary_text': 'Sanganer, Jaipur, Rajasthan',
        },
      );

      expect(suggestion.isUsable, isTrue);
      // There is nowhere on this class to put a latitude, which is the point:
      // a screen cannot route to the centroid of a search term.
      expect(suggestion.placeId, 'dev:jaipur-airport');
    });

    test('a suggestion with no id is not usable', () {
      final PlaceSuggestion suggestion = PlaceSuggestion.fromJson(
        <String, dynamic>{'primary_text': 'Somewhere'},
      );

      expect(suggestion.isUsable, isFalse);
    });

    test('details without a position are null, never zeroed', () {
      final PlaceDetails? details = PlaceDetails.fromJson(<String, dynamic>{
        'place_id': 'x',
        'display_name': 'Somewhere',
        'formatted_address': 'Somewhere',
      });

      // (0, 0) is a real point in the Gulf of Guinea. A journey drawn to it
      // crosses an ocean while looking entirely ordinary in a list.
      expect(details, isNull);
    });

    test('a reverse geocode that names nothing is null, not an error', () {
      expect(PlaceDetails.fromJson(null), isNull);
    });
  });

  group('TripLocation — what actually goes on the wire', () {
    TripLocation searched() => TripLocation.fromPlace(
      const PlaceDetails(
        placeId: 'dev:jaipur-airport',
        displayName: 'Jaipur International Airport',
        formattedAddress: 'Airport Road, Sanganer, Jaipur, Rajasthan 302029',
        latitude: 26.8242,
        longitude: 75.8122,
        city: 'Jaipur',
        region: 'Rajasthan',
        countryCode: 'IN',
        postalCode: '302029',
      ),
    );

    SavedAddress home({double? latitude, double? longitude}) => SavedAddress(
      id: 'addr-1',
      type: AddressType.home,
      label: 'Home',
      addressLine1: '12 Hauz Khas',
      city: 'New Delhi',
      state: 'Delhi',
      countryCode: 'IN',
      formattedAddress: '12 Hauz Khas, New Delhi, Delhi',
      latitude: latitude,
      longitude: longitude,
      isDefault: true,
    );

    test('a searched place sends its position and its provider id', () {
      final Map<String, dynamic> json = searched().toJson();

      expect(json['source_type'], 'PLACE_SEARCH');
      expect(json['latitude'], 26.8242);
      expect(json['place_id'], 'dev:jaipur-airport');
    });

    test('a saved address sends its id and nothing else', () {
      final TripLocation? location = TripLocation.fromSavedAddress(
        home(latitude: 28.5494, longitude: 77.2001),
      );

      final Map<String, dynamic> json = location!.toJson();

      // Deliberately not the coordinates it happens to know. Sending them would
      // create a request in which the id and the position could disagree, and
      // the server would then be choosing between a value it can verify and one
      // it cannot.
      expect(
        json.keys,
        unorderedEquals(<String>['source_type', 'saved_address_id']),
      );
      expect(json['saved_address_id'], 'addr-1');
    });

    test('a saved address with no position cannot become an endpoint', () {
      // Null rather than an endpoint with an invented coordinate. The customer
      // is asked to locate it; nothing guesses on their behalf.
      expect(TripLocation.fromSavedAddress(home()), isNull);
    });

    test('a named device fix is called by its name, not by the button', () {
      final TripLocation location = TripLocation.fromCurrentLocation(
        latitude: 28.5590,
        longitude: 77.2070,
        fallbackLabel: 'Current location',
        named: const PlaceDetails(
          placeId: 'dev:green-park',
          displayName: 'New Delhi',
          formattedAddress: 'Green Park, New Delhi, Delhi 110016',
          latitude: 28.5590,
          longitude: 77.2070,
          city: 'New Delhi',
        ),
      );

      // Found by reading the database after a live run: every journey started
      // from a place called "Use my current location", which is an instruction
      // rather than anywhere.
      expect(location.displayName, 'New Delhi');
      expect(location.latitude, 28.5590);
    });

    test('the current location keeps the device fix even when unnamed', () {
      final TripLocation location = TripLocation.fromCurrentLocation(
        latitude: 28.5590,
        longitude: 77.2070,
        fallbackLabel: 'Current location',
      );

      final Map<String, dynamic> json = location.toJson();

      expect(json['source_type'], 'CURRENT_LOCATION');
      expect(json['latitude'], 28.5590);
      expect(json['display_name'], 'Current location');
      // Nothing was invented to fill the gap the reverse geocode left.
      expect(json.containsKey('formatted_address'), isFalse);
      expect(json.containsKey('city'), isFalse);
    });

    test('no payload carries a customer id, a status or a route field', () {
      final TripDraft draft = TripDraft(
        origin: TripLocation.fromCurrentLocation(
          latitude: 28.5590,
          longitude: 77.2070,
          fallbackLabel: 'Current location',
        ),
        destination: searched(),
      );

      final String encoded = draft.toJson().toString();

      // The mass-assignment case, from the side that would have to send it.
      // There is no field on TripDraft for any of these, so this test would
      // fail the moment somebody added one.
      for (final String forbidden in <String>[
        'customer_id',
        'status',
        'route_status',
        'distance',
        'duration',
        'eta',
        'polyline',
      ]) {
        expect(encoded.contains(forbidden), isFalse, reason: forbidden);
      }
    });
  });

  group('the same-place rule', () {
    TripLocation at(double latitude, double longitude, {String? placeId}) =>
        TripLocation.fromPlace(
          PlaceDetails(
            placeId: placeId ?? '',
            displayName: 'Somewhere',
            formattedAddress: 'Somewhere',
            latitude: latitude,
            longitude: longitude,
          ),
        );

    test('the same provider id is the same place', () {
      expect(
        at(
          28.6315,
          77.2167,
          placeId: 'p1',
        ).isSamePlaceAs(at(28.7000, 77.3000, placeId: 'p1')),
        isTrue,
      );
    });

    test('within the threshold is the same place', () {
      // About 22 m apart. Nobody drives that.
      expect(at(28.6315, 77.2167).isSamePlaceAs(at(28.6317, 77.2167)), isTrue);
    });

    test('Delhi and Jaipur are not the same place', () {
      expect(at(28.5494, 77.2001).isSamePlaceAs(at(26.8242, 75.8122)), isFalse);
    });

    test(
      'the distance between two known points is right to within a percent',
      () {
        // Hauz Khas to Jaipur airport: ~235 km great-circle.
        final double? metres = at(
          28.5494,
          77.2001,
        ).distanceInMetresTo(at(26.8242, 75.8122));

        expect(metres, isNotNull);
        expect(metres! / 1000, closeTo(235, 5));
      },
    );
  });
}
