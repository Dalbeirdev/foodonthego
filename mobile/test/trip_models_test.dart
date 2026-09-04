import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/core/time/journey_time.dart';
import 'package:foodonthego/domain/models/saved_address.dart';
import 'package:foodonthego/domain/models/trip.dart';

import 'support/harness.dart';

void main() {
  group('Trip.fromJson', () {
    Map<String, dynamic> payload({Map<String, dynamic> overrides = const {}}) =>
        <String, dynamic>{
          'id': 'a1b2',
          'status': 'PLANNED',
          'origin': <String, dynamic>{
            'label': 'Home',
            'formatted_address': 'Hauz Khas, New Delhi, Delhi',
            'city': 'New Delhi',
            'country_code': 'IN',
            'latitude': null,
            'longitude': null,
            'place_id': null,
          },
          'destination': <String, dynamic>{
            'label': 'Jaipur',
            'formatted_address': 'MI Road, Jaipur, Rajasthan',
            'city': 'Jaipur',
            'country_code': 'IN',
          },
          'departure_at': '2026-09-05T09:00:00+00:00',
          'expected_arrival_at': null,
          'traveller_count': 2,
          'note': 'Collecting my sister',
          'is_editable': true,
          'has_departed': false,
          ...overrides,
        };

    test('reads the journey the server sent', () {
      final Trip trip = Trip.fromJson(payload());

      expect(trip.id, 'a1b2');
      expect(trip.status, TripStatus.planned);
      expect(trip.origin.city, 'New Delhi');
      expect(trip.destination.city, 'Jaipur');
      expect(trip.travellerCount, 2);
      expect(trip.note, 'Collecting my sister');
    });

    test('keeps times in UTC', () {
      final Trip trip = Trip.fromJson(payload());

      expect(trip.departureAt.isUtc, isTrue);
    });

    test('a null arrival stays null rather than becoming a guess', () {
      expect(Trip.fromJson(payload()).expectedArrivalAt, isNull);
    });

    test(
      'coordinates come through as null when nothing geocoded the place',
      () {
        final Trip trip = Trip.fromJson(payload());

        expect(trip.origin.latitude, isNull);
        expect(trip.origin.hasCoordinates, isFalse);
      },
    );

    test('a real coordinate string parses to a number', () {
      final Trip trip = Trip.fromJson(
        payload(
          overrides: <String, dynamic>{
            'origin': <String, dynamic>{
              'label': 'Home',
              'formatted_address': 'Hauz Khas, New Delhi, Delhi',
              'city': 'New Delhi',
              'country_code': 'IN',
              // The API sends decimals as strings so precision survives.
              'latitude': '28.5602000',
              'longitude': '77.2100000',
            },
          },
        ),
      );

      expect(trip.origin.latitude, closeTo(28.5602, 0.0000001));
      expect(trip.origin.hasCoordinates, isTrue);
    });

    test('is_editable is taken from the server, not recomputed', () {
      // A handset with a slow clock must not decide this for itself, or it will
      // offer an edit the server then refuses.
      final Trip trip = Trip.fromJson(
        payload(
          overrides: <String, dynamic>{
            'is_editable': false,
            'has_departed': true,
          },
        ),
      );

      expect(trip.isEditable, isFalse);
      expect(trip.hasDeparted, isTrue);
    });

    test('an unknown status degrades instead of crashing an older build', () {
      final Trip trip = Trip.fromJson(
        payload(overrides: <String, dynamic>{'status': 'ON_THE_ROAD'}),
      );

      expect(trip.status, TripStatus.planned);
    });

    test('a cancelled journey is neither upcoming nor editable', () {
      final Trip trip = Trip.fromJson(
        payload(
          overrides: <String, dynamic>{
            'status': 'CANCELLED',
            'is_editable': false,
            'cancellation_reason': 'Train booked instead',
          },
        ),
      );

      expect(trip.isCancelled, isTrue);
      expect(trip.isUpcoming, isFalse);
      expect(trip.cancellationReason, 'Train booked instead');
    });

    test('the route summary is the two ends', () {
      expect(Trip.fromJson(payload()).routeSummary, 'Home → Jaipur');
    });

    test('a place with no label falls back to its city', () {
      final JourneyPlace place = JourneyPlace.fromJson(<String, dynamic>{
        'label': '   ',
        'city': 'Agra',
      });

      expect(place.shortName, 'Agra');
    });
  });

  group('JourneyPlaceDraft', () {
    test('a saved address sends its id and nothing else', () {
      final Map<String, dynamic> json = const JourneyPlaceDraft.saved('addr-1')
          .toJson();

      // Sending typed fields alongside would create a request in which the two
      // could disagree about where the customer meant.
      expect(json, <String, dynamic>{'address_id': 'addr-1'});
    });

    test('a saved address can be built straight from the model', () {
      final SavedAddress address = sampleAddress(id: 'addr-9');

      expect(
        JourneyPlaceDraft.fromSavedAddress(address).savedAddressId,
        'addr-9',
      );
    });

    test('a typed place sends the city and an upper-cased country', () {
      final Map<String, dynamic> json = const JourneyPlaceDraft.typed(
        city: ' Jaipur ',
        countryCode: 'in',
      ).toJson();

      expect(json['city'], 'Jaipur');
      expect(json['country_code'], 'IN');
    });

    test('a blank optional field is absent rather than an empty string', () {
      final Map<String, dynamic> json = const JourneyPlaceDraft.typed(
        city: 'Jaipur',
        countryCode: 'IN',
        label: '   ',
        addressLine: '',
      ).toJson();

      expect(json.containsKey('label'), isFalse);
      expect(json.containsKey('address_line'), isFalse);
    });

    test('coordinates travel only as a complete pair', () {
      final Map<String, dynamic> half = const JourneyPlaceDraft.typed(
        city: 'Jaipur',
        countryCode: 'IN',
        latitude: 26.9124,
      ).toJson();

      // The server refuses half a coordinate, and no field on the form could
      // have produced it — so sending it would be an error nobody could act on.
      expect(half.containsKey('latitude'), isFalse);

      final Map<String, dynamic> both = const JourneyPlaceDraft.typed(
        city: 'Jaipur',
        countryCode: 'IN',
        latitude: 26.9124,
        longitude: 75.7873,
      ).toJson();

      expect(both['latitude'], 26.9124);
      expect(both['longitude'], 75.7873);
    });
  });

  group('TripDraft', () {
    test('sends departure as an ISO-8601 UTC instant', () {
      final Map<String, dynamic> json = TripDraft(
        origin: const JourneyPlaceDraft.typed(city: 'A', countryCode: 'IN'),
        destination: const JourneyPlaceDraft.typed(
          city: 'B',
          countryCode: 'IN',
        ),
        departureAt: DateTime.utc(2026, 9, 5, 9),
      ).toJson();

      expect(json['departure_at'], '2026-09-05T09:00:00.000Z');
    });

    test('a traveller count nobody set is omitted, not defaulted to 1', () {
      // The defect this test exists for: a default of 1 on the draft made every
      // partial update send traveller_count: 1, silently resetting a party of
      // three to one. Found by reading the database after an integration run,
      // not by the API assertions, which only checked the update that set it.
      final Map<String, dynamic> json = const TripDraft(
        origin: null,
        destination: null,
        departureAt: null,
        clearNote: true,
      ).toJson();

      expect(json.containsKey('traveller_count'), isFalse);
    });

    test('omits what it was not given', () {
      final Map<String, dynamic> json = const TripDraft(
        origin: null,
        destination: null,
        departureAt: null,
        travellerCount: 3,
      ).toJson();

      expect(json.keys, <String>['traveller_count']);
    });

    test('an explicit clear is different from an omission', () {
      final Map<String, dynamic> cleared = const TripDraft(
        origin: null,
        destination: null,
        departureAt: null,
        clearArrival: true,
        clearNote: true,
      ).toJson();

      // Null means "clear it"; absent means "leave it". A client that could not
      // say the first would make removing an arrival time impossible.
      expect(cleared.containsKey('expected_arrival_at'), isTrue);
      expect(cleared['expected_arrival_at'], isNull);
      expect(cleared.containsKey('note'), isTrue);
      expect(cleared['note'], isNull);
    });

    test('a blank note is omitted rather than sent as an empty string', () {
      final Map<String, dynamic> json = const TripDraft(
        origin: null,
        destination: null,
        departureAt: null,
        note: '   ',
      ).toJson();

      expect(json.containsKey('note'), isFalse);
    });
  });

  group('JourneyTime', () {
    final DateTime now = DateTime(2026, 9, 4, 10);

    test('names today, tomorrow and yesterday', () {
      expect(
        JourneyTime.relativeDay(DateTime(2026, 9, 4, 18), now: now),
        'Today',
      );
      expect(
        JourneyTime.relativeDay(DateTime(2026, 9, 5, 6), now: now),
        'Tomorrow',
      );
      expect(
        JourneyTime.relativeDay(DateTime(2026, 9, 3, 22), now: now),
        'Yesterday',
      );
    });

    test('falls back to a dated form further out', () {
      expect(
        JourneyTime.relativeDay(DateTime(2026, 9, 12, 9), now: now),
        'Sat 12 Sep',
      );
    });

    test('keeps the year when it is not the current one', () {
      expect(
        JourneyTime.date(DateTime(2027, 1, 2, 9), now: now),
        contains('2027'),
      );
    });

    test('renders twelve-hour times, midnight and noon included', () {
      expect(JourneyTime.time(DateTime(2026, 9, 4, 6, 30)), '6:30 am');
      expect(JourneyTime.time(DateTime(2026, 9, 4, 18, 5)), '6:05 pm');
      expect(JourneyTime.time(DateTime(2026, 9, 4, 0, 0)), '12:00 am');
      expect(JourneyTime.time(DateTime(2026, 9, 4, 12, 0)), '12:00 pm');
    });

    test('combines a picked day and time into one instant', () {
      final DateTime combined = JourneyTime.combine(
        DateTime(2026, 9, 12),
        18,
        45,
      );

      expect(combined, DateTime(2026, 9, 12, 18, 45));
    });
  });
}
