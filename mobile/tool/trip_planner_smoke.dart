// The Module 05 end-to-end run: this app's own network layer against a running
// Laravel backend and a real MySQL database. No mocks, no fakes, no stubs.
//
// It walks the module's own example — Rahul searches for a place, resolves it,
// creates New Delhi → Jaipur from a saved address, reads it back, discards it —
// then Ananya's trip and Ananya's saved address are attacked from Rahul's
// session every way the API allows, including the one this module adds: creating
// a trip *from somebody else's saved address*.
//
// Run it with the backend serving and OTP_PROVIDER=log:
//
//   php artisan serve --host=127.0.0.1 --port=8000
//   dart run tool/trip_planner_smoke.dart
//
// Deliberately a `dart run` and not a `flutter test`: flutter_test replaces
// HttpClient with a mock, so a "test" there could never make a real request.

import 'dart:convert';
import 'dart:io';

import 'package:foodonthego/core/config/api_config.dart';
import 'package:foodonthego/core/network/api_client.dart';
import 'package:foodonthego/core/network/api_error_code.dart';
import 'package:foodonthego/core/network/api_exception.dart';
import 'package:foodonthego/data/repositories/api_auth_repository.dart';
import 'package:foodonthego/data/repositories/api_customer_repository.dart';
import 'package:foodonthego/data/repositories/api_place_repository.dart';
import 'package:foodonthego/data/repositories/api_trip_repository.dart';
import 'package:foodonthego/domain/models/auth_models.dart';
import 'package:foodonthego/domain/models/place.dart';
import 'package:foodonthego/domain/models/saved_address.dart';
import 'package:foodonthego/domain/models/trip.dart';
import 'package:foodonthego/domain/repositories/trip_repository.dart';

/// Numbers from the Indian range reserved for testing and documentation, so a
/// code can never reach a real handset even if a real provider were configured.
const String _rahulPhone = '9999900301';
const String _ananyaPhone = '9999900302';
const String _countryCode = '91';

const String _otpLog = '../backend/storage/logs/otp-development.log';

int _passed = 0;
int _failed = 0;

/// One signed-in customer: their own client, repositories and token.
class Session {
  Session(this.name, this.token)
    : client = ApiClient(tokenReader: () async => token);

  final String name;
  final String token;
  final ApiClient client;

  ApiCustomerRepository? _customer;
  ApiTripRepository? _trips;
  ApiPlaceRepository? _places;

  ApiCustomerRepository get customer =>
      _customer ??= ApiCustomerRepository(client);

  ApiTripRepository get trips => _trips ??= ApiTripRepository(client);

  ApiPlaceRepository get places => _places ??= ApiPlaceRepository(client);

  void close() => client.close();
}

void main(List<String> args) async {
  stdout.writeln('FoodOnTheGo — Module 05 integration run');
  stdout.writeln('Backend: ${ApiConfig.baseUrl}');
  stdout.writeln('');

  final Session rahul = await _signIn('Rahul', 'Sharma', _rahulPhone);
  final Session ananya = await _signIn('Ananya', 'Mehta', _ananyaPhone);

  await _discardEverything(rahul);
  await _discardEverything(ananya);
  await _clearAddresses(rahul);
  await _clearAddresses(ananya);

  // --- 1. an empty account -----------------------------------------------
  await _checkAsync('a new customer has no trips', () async {
    _expect((await rahul.trips.trips()).isEmpty, true);
    _expect(await rahul.trips.currentTrip(), null);
  });

  // --- 2. place search ----------------------------------------------------
  const String token = 'smoke-session-token';

  final List<PlaceSuggestion> jaipur = await rahul.places.search(
    'jaipur airport',
    sessionToken: token,
  );

  _check('search returns real suggestions', () {
    _expect(jaipur.isNotEmpty, true);
    _expect(jaipur.first.primaryText.contains('Jaipur'), true);
  });

  _check('a suggestion carries no coordinates', () {
    // Autocomplete answers "which place did you mean". Where it is comes from
    // the details call, and a suggestion that carried a position would invite a
    // client to route to the centroid of a search term.
    _expect(jaipur.first.placeId.isNotEmpty, true);
  });

  await _checkAsync(
    'one letter is refused before the provider is called',
    () async {
      try {
        await rahul.client.get(
          '/customer/places/search?q=J',
          authenticated: true,
        );
        throw StateError('a one-letter search was accepted');
      } on ApiException catch (error) {
        _expect(error.code, ApiErrorCode.validationFailed);
      }
    },
  );

  final PlaceDetails airport = await rahul.places.details(
    jaipur.first.placeId,
    sessionToken: token,
  );

  _check('details resolve a suggestion to a real position', () {
    // Jaipur International Airport's published position. Not fabricated, and
    // not derived from the address text.
    _expect(airport.latitude > 26.5 && airport.latitude < 27.2, true);
    _expect(airport.longitude > 75.5 && airport.longitude < 76.2, true);
  });

  await _checkAsync('reverse geocoding keeps the caller\'s own coordinates', () async {
    final PlaceDetails? named = await rahul.places.reverseGeocode(
      latitude: 28.5590,
      longitude: 77.2070,
    );

    // Snapping a device fix to the nearest known landmark would move somebody's
    // starting point by kilometres.
    if (named != null) {
      _expect((named.latitude - 28.5590).abs() < 0.0001, true);
    }
  });

  await _checkAsync('an impossible coordinate is refused', () async {
    try {
      await rahul.places.reverseGeocode(latitude: 91, longitude: 0);
      throw StateError('latitude 91 was accepted');
    } on ApiException catch (error) {
      _expect(error.code, ApiErrorCode.validationFailed);
    }
  });

  await _checkAsync('place lookup needs a session', () async {
    final ApiClient anonymous = ApiClient();
    try {
      await ApiPlaceRepository(anonymous).search('jaipur');
      throw StateError('an unauthenticated search succeeded');
    } on ApiException catch (error) {
      _expect(error.code, ApiErrorCode.unauthenticated);
    } finally {
      anonymous.close();
    }
  });

  // --- 3. creating a trip from a saved address ----------------------------
  final SavedAddress home = await rahul.customer.createAddress(
    const AddressDraft(
      type: AddressType.home,
      label: 'Home',
      addressLine1: '12 Green Park Road',
      city: 'New Delhi',
      state: 'Delhi',
      postalCode: '110016',
      countryCode: 'IN',
      latitude: 28.5590,
      longitude: 77.2070,
    ),
  );

  final Trip created = await rahul.trips.createTrip(
    TripDraft(
      origin: TripLocation.fromSavedAddress(home)!,
      destination: TripLocation.fromPlace(airport),
    ),
  );

  _check('a trip is created from a saved address and a searched place', () {
    _expect(created.status, TripStatus.routePending);
    _expect(created.origin.sourceType, LocationSourceType.savedAddress);
    _expect(created.destination.sourceType, LocationSourceType.placeSearch);
  });

  _check('no route is calculated, and none is claimed', () {
    // The boundary this module stops at. Module 06 is what moves this.
    _expect(created.routeStatus, RouteStatus.notCalculated);
    _expect(created.hasRoute, false);
  });

  _check('both ends carry usable coordinates', () {
    _expect(created.origin.latitude != 0, true);
    _expect(created.destination.latitude != 0, true);
    _expect(created.destination.latitude > 26.5, true);
  });

  await _checkAsync(
    'the saved address is snapshotted, not referenced',
    () async {
      await rahul.customer.updateAddress(
        home.id,
        const AddressDraft(
          type: AddressType.home,
          label: 'Home',
          addressLine1: 'Somewhere else entirely',
          city: 'Mumbai',
          state: 'Maharashtra',
          countryCode: 'IN',
          latitude: 18.9401,
          longitude: 72.8352,
        ),
      );

      final Trip reread = await rahul.trips.trip(created.id);

      // Editing the address the trip came from must not move the journey.
      _expect(reread.origin.city, 'New Delhi');
    },
  );

  await _checkAsync(
    'a deleted saved address does not take the trip with it',
    () async {
      await rahul.customer.deleteAddress(home.id);

      final Trip reread = await rahul.trips.trip(created.id);
      _expect(reread.origin.city, 'New Delhi');
    },
  );

  // --- 4. the response contains no route fields ---------------------------
  await _checkAsync(
    'the API sends no distance, duration, polyline or ETA',
    () async {
      final Map<String, dynamic> raw = await rahul.client.get(
        '/customer/trips/${created.id}',
        authenticated: true,
      );

      final String encoded = jsonEncode(raw);
      for (final String forbidden in <String>[
        'distance',
        'duration',
        'polyline',
        'eta',
        'travel_time',
        'customer_id',
        'saved_address_id',
      ]) {
        if (encoded.contains(forbidden)) {
          throw 'the trip payload contained "$forbidden"';
        }
      }
    },
  );

  // --- 5. validation ------------------------------------------------------
  await _expectRefused(
    'the same place at both ends is refused',
    () => rahul.trips.createTrip(
      TripDraft(
        origin: TripLocation.fromPlace(airport),
        destination: TripLocation.fromPlace(airport),
      ),
    ),
    ApiErrorCode.sameLocation,
  );

  await _expectRefused(
    'a latitude outside the possible range is refused',
    () => rahul.client.post(
      '/customer/trips',
      authenticated: true,
      body: <String, dynamic>{
        'origin': <String, dynamic>{
          'source_type': 'PLACE_SEARCH',
          'display_name': 'Nowhere',
          'latitude': 91.0,
          'longitude': 77.2,
        },
        'destination': <String, dynamic>{
          'source_type': 'PLACE_SEARCH',
          'display_name': 'Jaipur',
          'latitude': 26.8242,
          'longitude': 75.8122,
        },
      },
    ),
    ApiErrorCode.validationFailed,
  );

  await _expectRefused(
    'the (0, 0) sentinel is refused rather than routed to',
    () => rahul.client.post(
      '/customer/trips',
      authenticated: true,
      body: <String, dynamic>{
        'origin': <String, dynamic>{
          'source_type': 'PLACE_SEARCH',
          'display_name': 'Null Island',
          'latitude': 0,
          'longitude': 0,
        },
        'destination': <String, dynamic>{
          'source_type': 'PLACE_SEARCH',
          'display_name': 'Jaipur',
          'latitude': 26.8242,
          'longitude': 75.8122,
        },
      },
    ),
    ApiErrorCode.invalidCoordinates,
  );

  await _expectRefused(
    'a missing origin is refused',
    () => rahul.client.post(
      '/customer/trips',
      authenticated: true,
      body: <String, dynamic>{
        'destination': <String, dynamic>{
          'source_type': 'PLACE_SEARCH',
          'latitude': 26.8242,
          'longitude': 75.8122,
        },
      },
    ),
    ApiErrorCode.validationFailed,
  );

  // --- 6. mass assignment -------------------------------------------------
  await _checkAsync(
    'unauthorised fields in the payload have no effect',
    () async {
      final Map<String, dynamic> raw = await rahul.client.post(
        '/customer/trips',
        authenticated: true,
        body: <String, dynamic>{
          // Everything a caller might hope to seed, sent together.
          'customer_id': 1,
          'id': 99999,
          'uuid': '00000000-0000-0000-0000-000000000000',
          'status': 'ACTIVE',
          'route_status': 'READY',
          'distance': 1,
          'distance_metres': 1,
          'duration': 1,
          'eta': 1,
          'polyline': 'abcdef',
          'cancelled_at': '2020-01-01T00:00:00Z',
          'origin': <String, dynamic>{
            'source_type': 'CURRENT_LOCATION',
            'display_name': 'Green Park',
            'latitude': 28.5590,
            'longitude': 77.2070,
          },
          'destination': <String, dynamic>{
            'source_type': 'PLACE_SEARCH',
            'display_name': 'Hawa Mahal',
            'latitude': 26.9239,
            'longitude': 75.8267,
          },
        },
      );

      final Trip trip = Trip.fromJson(raw);

      // The trip was created, and every injected field was ignored.
      _expect(trip.status, TripStatus.routePending);
      _expect(trip.routeStatus, RouteStatus.notCalculated);
      _expect(trip.cancelledAt, null);
      _expect(trip.id == '00000000-0000-0000-0000-000000000000', false);

      // And it belongs to Rahul, not to customer 1.
      final List<Trip> his = await rahul.trips.trips();
      _expect(his.any((Trip t) => t.id == trip.id), true);

      await rahul.trips.discardTrip(trip.id);
    },
  );

  // --- 7. Ananya's data, attacked from Rahul's session --------------------
  final SavedAddress hers = await ananya.customer.createAddress(
    const AddressDraft(
      type: AddressType.work,
      label: 'Office',
      addressLine1: 'Tower B, Cyber City',
      city: 'Gurugram',
      state: 'Haryana',
      postalCode: '122002',
      countryCode: 'IN',
      latitude: 28.4949,
      longitude: 77.0886,
    ),
  );

  final Trip herTrip = await ananya.trips.createTrip(
    TripDraft(
      origin: TripLocation.fromSavedAddress(hers)!,
      destination: TripLocation.fromPlace(
        await ananya.places.details(
          (await ananya.places.search('sector 17')).first.placeId,
        ),
      ),
    ),
  );

  await _expectRefused(
    "Rahul cannot read Ananya's trip",
    () => rahul.trips.trip(herTrip.id),
    ApiErrorCode.tripNotFound,
  );

  await _expectRefused(
    "Rahul cannot discard Ananya's trip",
    () => rahul.trips.discardTrip(herTrip.id),
    ApiErrorCode.tripNotFound,
  );

  await _expectRefused(
    "Rahul cannot delete Ananya's trip",
    () => rahul.client.delete(
      '/customer/trips/${herTrip.id}',
      authenticated: true,
    ),
    ApiErrorCode.methodNotAllowed,
  );

  // The IDOR this module adds, and the reason `TripService` resolves saved
  // addresses through Module 04's ownership-scoped lookup rather than querying
  // the table itself.
  await _expectRefused(
    "Rahul cannot create a trip from Ananya's saved address",
    () => rahul.client.post(
      '/customer/trips',
      authenticated: true,
      body: <String, dynamic>{
        'origin': <String, dynamic>{
          'source_type': 'SAVED_ADDRESS',
          'saved_address_id': hers.id,
        },
        'destination': <String, dynamic>{
          'source_type': 'PLACE_SEARCH',
          'display_name': 'Jaipur',
          'latitude': 26.8242,
          'longitude': 75.8122,
        },
      },
    ),
    ApiErrorCode.addressNotFound,
  );

  await _checkAsync("no refusal leaks a word about Ananya's data", () async {
    for (final Future<Object?> Function() attempt
        in <Future<Object?> Function()>[
          () => rahul.trips.trip(herTrip.id),
          () => rahul.trips.discardTrip(herTrip.id),
        ]) {
      try {
        await attempt();
        throw StateError('an attack on Ananya succeeded');
      } on ApiException catch (error) {
        final String body = '${error.message} ${error.details}';
        for (final String secret in <String>[
          'Gurugram',
          'Cyber City',
          'Sector 17',
          'Haryana',
          '28.4949',
          hers.id,
        ]) {
          if (body.contains(secret)) {
            throw 'a refusal mentioned "$secret"';
          }
        }
      }
    }
  });

  await _checkAsync('a missing trip and a forbidden one are indistinguishable', () async {
    ApiErrorCode? forbidden;
    ApiErrorCode? missing;

    try {
      await rahul.trips.trip(herTrip.id);
    } on ApiException catch (error) {
      forbidden = error.code;
    }

    try {
      await rahul.trips.trip('00000000-0000-0000-0000-000000000000');
    } on ApiException catch (error) {
      missing = error.code;
    }

    // Both 404. A 403 for one and a 404 for the other is an oracle: it confirms
    // which ids are real.
    _expect(forbidden, ApiErrorCode.tripNotFound);
    _expect(missing, ApiErrorCode.tripNotFound);
  });

  await _checkAsync("Ananya's list is hers alone", () async {
    final List<Trip> his = await rahul.trips.trips(scope: TripScope.all);
    _expect(his.any((Trip t) => t.id == herTrip.id), false);
  });

  // --- 8. the lifecycle ---------------------------------------------------
  await _checkAsync('a trip can be discarded, and stays in history', () async {
    final Trip discarded = await rahul.trips.discardTrip(created.id);
    _expect(discarded.status, TripStatus.cancelled);
    _expect(discarded.cancelledAt != null, true);

    final List<Trip> open = await rahul.trips.trips();
    _expect(open.any((Trip t) => t.id == created.id), false);

    final List<Trip> gone = await rahul.trips.trips(scope: TripScope.cancelled);
    _expect(gone.any((Trip t) => t.id == created.id), true);
  });

  await _expectRefused(
    'a discarded trip cannot be discarded again',
    () => rahul.trips.discardTrip(created.id),
    ApiErrorCode.tripNotEditable,
  );

  // --- 9. authentication --------------------------------------------------
  await _checkAsync('an unauthenticated call reaches no trips', () async {
    final ApiClient anonymous = ApiClient();
    try {
      await ApiTripRepository(anonymous).trips();
      throw StateError('an unauthenticated list succeeded');
    } on ApiException catch (error) {
      _expect(error.code, ApiErrorCode.unauthenticated);
    } finally {
      anonymous.close();
    }
  });

  // Last, because it ends Rahul's session for good. Signing in a second time to
  // get a throwaway token would hit the OTP resend cooldown Module 03 enforces
  // — the server behaving correctly, reported as a failure here.
  await _checkAsync('a revoked session stops reaching trips', () async {
    await rahul.client.post('/auth/logout', authenticated: true);

    try {
      await rahul.trips.trips();
      throw StateError('a revoked token still reached trips');
    } on ApiException catch (error) {
      _expect(error.code, ApiErrorCode.unauthenticated);
    }
  });

  rahul.close();
  ananya.close();

  stdout.writeln('');
  stdout.writeln('$_passed passed, $_failed failed');
  exit(_failed == 0 ? 0 : 1);
}

Future<Session> _signIn(
  String firstName,
  String? lastName,
  String national,
) async {
  final ApiClient client = ApiClient();
  final ApiAuthRepository auth = ApiAuthRepository(client);

  final int offset = await _logLength();
  await _requestCode(auth, national);
  final String code = await _readCodeAfter(offset);

  final OtpVerifyResult result = await auth.verifyOtp(
    phone: national,
    countryCode: _countryCode,
    code: code,
  );

  final AuthSession session = switch (result) {
    OtpSignedIn(session: final AuthSession s) => s,
    OtpRegistrationRequired(registrationToken: final String token) =>
      await auth.register(
        registrationToken: token,
        firstName: firstName,
        lastName: lastName,
      ),
  };

  client.close();

  return Session(firstName, session.accessToken);
}

/// Leaves the account with no open trips the run could trip over.
///
/// Discarded rather than deleted, because there is no delete — a trip is
/// history, and a later module's orders point at it.
Future<void> _discardEverything(Session session) async {
  for (final Trip trip in await session.trips.trips(scope: TripScope.all)) {
    if (trip.isDiscardable) {
      await session.trips.discardTrip(trip.id);
    }
  }
}

Future<void> _clearAddresses(Session session) async {
  for (final SavedAddress address in await session.customer.addresses()) {
    await session.customer.deleteAddress(address.id);
  }
}

/// Asks for a code, waiting out the resend cooldown if a previous run just used
/// this number.
///
/// The cooldown is Module 03 working correctly, not a fault — so the tool waits
/// for it rather than the product being loosened to make a test convenient.
Future<void> _requestCode(ApiAuthRepository auth, String national) async {
  for (int attempt = 0; attempt < 3; attempt++) {
    try {
      await auth.requestOtp(phone: national, countryCode: _countryCode);
      return;
    } on ApiException catch (error) {
      final bool cooling =
          error.code == ApiErrorCode.otpResendTooSoon ||
          error.code == ApiErrorCode.otpRateLimited;

      if (!cooling || attempt == 2) rethrow;

      final Object? retryAfter = error.details?['retry_after_seconds'];
      final int seconds = retryAfter is num ? retryAfter.toInt() : 30;

      stdout.writeln('  ..    waiting ${seconds}s for the OTP cooldown');
      await Future<void>.delayed(Duration(seconds: seconds + 1));
    }
  }
}

Future<int> _logLength() async {
  final File file = File(_otpLog);
  return file.existsSync() ? file.lengthSync() : 0;
}

Future<String> _readCodeAfter(int offset) async {
  final File file = File(_otpLog);
  if (!file.existsSync()) {
    throw StateError('No development OTP log at $_otpLog.');
  }

  // Sliced as bytes then decoded: the mask characters in this log are three
  // bytes each in UTF-8 but one UTF-16 unit in a Dart string, so a byte offset
  // used as a string index drifts further with every masked number.
  final List<int> bytes = await file.readAsBytes();
  final String fresh = utf8.decode(
    bytes.sublist(offset.clamp(0, bytes.length)),
    allowMalformed: true,
  );

  final Iterable<RegExpMatch> matches = RegExp(r'"code":"(\d{6})"')
      .allMatches(fresh);

  if (matches.isEmpty) {
    throw StateError(
      'No OTP found in the development log since the run started.',
    );
  }

  return matches.last.group(1)!;
}

/// Asserts that a call fails, and fails with the right code.
///
/// A bare "it threw" would pass if the server 500ed, which is the opposite of
/// what these assertions are for.
Future<void> _expectRefused(
  String description,
  Future<Object?> Function() body,
  ApiErrorCode expected,
) async {
  try {
    await body();
    _failed++;
    stdout.writeln('  FAIL  $description\n        the call succeeded');
  } on ApiException catch (error) {
    if (error.code == expected) {
      _passed++;
      stdout.writeln('  PASS  $description');
    } else {
      _failed++;
      stdout.writeln(
        '  FAIL  $description\n        expected $expected, got ${error.code}',
      );
    }
  }
}

void _expect(Object? actual, Object? expected) {
  if (actual != expected) throw 'expected $expected, got $actual';
}

void _check(String description, void Function() body) {
  try {
    body();
    _passed++;
    stdout.writeln('  PASS  $description');
  } catch (error) {
    _failed++;
    stdout.writeln('  FAIL  $description\n        $error');
  }
}

Future<void> _checkAsync(
  String description,
  Future<void> Function() body,
) async {
  try {
    await body();
    _passed++;
    stdout.writeln('  PASS  $description');
  } catch (error) {
    _failed++;
    stdout.writeln('  FAIL  $description\n        $error');
  }
}
