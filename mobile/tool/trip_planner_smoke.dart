// The Module 05 end-to-end run: this app's own network layer against a running
// Laravel backend and a real MySQL database. No mocks, no fakes, no stubs.
//
// It walks the module's own example — Rahul plans New Delhi → Jaipur from a
// saved address, edits it, states an arrival, cancels one, and finds his past
// journeys — then Ananya's journey is attacked from Rahul's session every way
// the API allows, including the subtle one this module adds: planning a journey
// *from somebody else's saved address*.
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
import 'package:foodonthego/data/repositories/api_trip_repository.dart';
import 'package:foodonthego/domain/models/auth_models.dart';
import 'package:foodonthego/domain/models/saved_address.dart';
import 'package:foodonthego/domain/models/trip.dart';

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

  ApiCustomerRepository get customer =>
      _customer ??= ApiCustomerRepository(client);

  ApiTripRepository get trips => _trips ??= ApiTripRepository(client);

  void close() => client.close();
}

void main(List<String> args) async {
  stdout.writeln('FoodOnTheGo — Module 05 integration run');
  stdout.writeln('Backend: ${ApiConfig.baseUrl}');
  stdout.writeln('');

  final Session rahul = await _signIn('Rahul', 'Sharma', _rahulPhone);
  final Session ananya = await _signIn('Ananya', 'Mehta', _ananyaPhone);

  await _cancelEverything(rahul);
  await _cancelEverything(ananya);
  await _clearAddresses(rahul);
  await _clearAddresses(ananya);

  final DateTime tomorrow = DateTime.now().add(const Duration(days: 1));

  // --- 1. an empty account -----------------------------------------------
  await _checkAsync('a new customer has no journeys', () async {
    _expect((await rahul.trips.trips()).isEmpty, true);
    _expect(await rahul.trips.nextTrip(), null);
  });

  // --- 2. planning from a saved address -----------------------------------
  final SavedAddress home = await rahul.customer.createAddress(
    const AddressDraft(
      type: AddressType.home,
      label: 'Home',
      addressLine1: '12 Green Park Road',
      city: 'New Delhi',
      state: 'Delhi',
      postalCode: '110016',
      countryCode: 'IN',
    ),
  );

  final Trip planned = await rahul.trips.planTrip(
    TripDraft(
      origin: JourneyPlaceDraft.fromSavedAddress(home),
      destination: const JourneyPlaceDraft.typed(
        city: 'Jaipur',
        countryCode: 'IN',
        label: 'MI Road',
        addressLine: 'MI Road',
        state: 'Rajasthan',
      ),
      departureAt: tomorrow,
      travellerCount: 2,
      note: 'Collecting my sister',
    ),
  );

  _check('a journey is planned from a saved address', () {
    _expect(planned.status, TripStatus.planned);
    _expect(planned.origin.city, 'New Delhi');
    _expect(planned.destination.city, 'Jaipur');
    _expect(planned.travellerCount, 2);
  });

  _check('the saved address is snapshotted, not referenced', () {
    // The label came from the address, and the response carries no address id
    // at all — the journey holds a copy, not a pointer.
    _expect(planned.origin.label, 'Home');
  });

  _check('coordinates are null, not invented from the text', () {
    _expect(planned.origin.latitude, null);
    _expect(planned.origin.longitude, null);
    _expect(planned.destination.latitude, null);
    _expect(planned.origin.hasCoordinates, false);
  });

  _check('an arrival nothing computed is null, not a guess', () {
    _expect(planned.expectedArrivalAt, null);
  });

  _check('the server says whether the journey can still be changed', () {
    _expect(planned.isEditable, true);
    _expect(planned.hasDeparted, false);
  });

  // --- 3. editing the saved address does not rewrite the journey ----------
  await rahul.customer.updateAddress(
    home.id,
    const AddressDraft(
      type: AddressType.home,
      label: 'Old Flat',
      addressLine1: '99 Somewhere Else',
      city: 'Mumbai',
      state: 'Maharashtra',
      postalCode: '400001',
      countryCode: 'IN',
    ),
  );

  await _checkAsync(
    'editing the address later leaves the journey alone',
    () async {
      final Trip reread = await rahul.trips.trip(planned.id);
      _expect(reread.origin.city, 'New Delhi');
      _expect(reread.origin.label, 'Home');
    },
  );

  // --- 4. reading it back -------------------------------------------------
  await _checkAsync('a fresh read returns the planned journey', () async {
    final Trip reread = await rahul.trips.trip(planned.id);
    _expect(reread.id, planned.id);
    _expect(reread.note, 'Collecting my sister');
  });

  await _checkAsync('the journey is the next one', () async {
    _expect((await rahul.trips.nextTrip())?.id, planned.id);
  });

  // --- 5. editing ---------------------------------------------------------
  final Trip edited = await rahul.trips.updateTrip(
    planned.id,
    TripDraft(
      origin: null,
      destination: null,
      departureAt: null,
      expectedArrivalAt: tomorrow.add(const Duration(hours: 5)),
      travellerCount: 3,
    ),
  );

  _check('an edit persists and leaves untouched fields alone', () {
    _expect(edited.travellerCount, 3);
    _expect(edited.expectedArrivalAt != null, true);
    // Not sent, so not changed.
    _expect(edited.note, 'Collecting my sister');
    _expect(edited.destination.city, 'Jaipur');
  });

  final Trip cleared = await rahul.trips.updateTrip(
    planned.id,
    const TripDraft(
      origin: null,
      destination: null,
      departureAt: null,
      clearArrival: true,
      clearNote: true,
    ),
  );

  _check('an explicit clear really clears', () {
    _expect(cleared.expectedArrivalAt, null);
    _expect(cleared.note, null);
  });

  await _checkAsync('a partial update leaves untouched fields alone in the database', () async {
    // Read back rather than trusting the update's own response. The traveller
    // count survived the response and was reset in the row underneath it, which
    // is exactly the defect this assertion now guards.
    final Trip reread = await rahul.trips.trip(planned.id);
    _expect(reread.travellerCount, 3);
    _expect(reread.destination.city, 'Jaipur');
  });

  // --- 6. ordering and scopes --------------------------------------------
  final Trip second = await rahul.trips.planTrip(
    TripDraft(
      origin: const JourneyPlaceDraft.typed(
        city: 'New Delhi',
        countryCode: 'IN',
        label: 'Office',
      ),
      destination: const JourneyPlaceDraft.typed(
        city: 'Agra',
        countryCode: 'IN',
        label: 'Agra',
      ),
      departureAt: DateTime.now().add(const Duration(hours: 6)),
    ),
  );

  await _checkAsync('the upcoming list is soonest first', () async {
    final List<Trip> upcoming = await rahul.trips.trips();
    _expect(upcoming.length, 2);
    _expect(upcoming.first.id, second.id);
  });

  await _checkAsync('the soonest journey is the next one', () async {
    _expect((await rahul.trips.nextTrip())?.id, second.id);
  });

  // --- 7. validation ------------------------------------------------------
  await _expectRefused(
    'a departure in the past is refused',
    () => rahul.trips.planTrip(
      TripDraft(
        origin: const JourneyPlaceDraft.typed(city: 'A', countryCode: 'IN'),
        destination: const JourneyPlaceDraft.typed(
          city: 'B',
          countryCode: 'IN',
        ),
        departureAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
    ),
    ApiErrorCode.validationFailed,
  );

  await _expectRefused(
    'the same place at both ends is refused',
    () => rahul.trips.planTrip(
      TripDraft(
        origin: const JourneyPlaceDraft.typed(
          city: 'Jaipur',
          countryCode: 'IN',
          addressLine: 'MI Road',
          state: 'Rajasthan',
        ),
        destination: const JourneyPlaceDraft.typed(
          city: 'Jaipur',
          countryCode: 'IN',
          addressLine: 'MI Road',
          state: 'Rajasthan',
        ),
        departureAt: tomorrow,
      ),
    ),
    ApiErrorCode.validationFailed,
  );

  await _expectRefused(
    'an arrival before departure is refused',
    () => rahul.trips.planTrip(
      TripDraft(
        origin: const JourneyPlaceDraft.typed(city: 'Delhi', countryCode: 'IN'),
        destination: const JourneyPlaceDraft.typed(
          city: 'Bhopal',
          countryCode: 'IN',
        ),
        departureAt: tomorrow.add(const Duration(hours: 5)),
        expectedArrivalAt: tomorrow.add(const Duration(hours: 2)),
      ),
    ),
    ApiErrorCode.validationFailed,
  );

  // --- 8. cancelling ------------------------------------------------------
  final Trip cancelled = await rahul.trips.cancelTrip(
    second.id,
    reason: 'Train booked instead',
  );

  _check('cancelling records the decision', () {
    _expect(cancelled.status, TripStatus.cancelled);
    _expect(cancelled.cancellationReason, 'Train booked instead');
    _expect(cancelled.isEditable, false);
  });

  await _checkAsync('a cancelled journey leaves the upcoming list', () async {
    final List<Trip> upcoming = await rahul.trips.trips();
    _expect(upcoming.length, 1);
    _expect(upcoming.first.id, planned.id);

    final List<Trip> off = await rahul.trips.trips(scope: TripScope.cancelled);
    _expect(off.any((Trip t) => t.id == second.id), true);
  });

  await _expectRefused(
    'cancelling twice is refused rather than silently accepted',
    () => rahul.trips.cancelTrip(second.id),
    ApiErrorCode.tripNotEditable,
  );

  await _expectRefused(
    'a cancelled journey can no longer be edited',
    () => rahul.trips.updateTrip(
      second.id,
      const TripDraft(
        origin: null,
        destination: null,
        departureAt: null,
        travellerCount: 4,
      ),
    ),
    ApiErrorCode.tripNotEditable,
  );

  // --- 9. ownership -------------------------------------------------------
  final SavedAddress ananyaHome = await ananya.customer.createAddress(
    const AddressDraft(
      type: AddressType.home,
      label: 'Ananya Home',
      addressLine1: '9 Sector 44',
      city: 'Gurugram',
      state: 'Haryana',
      postalCode: '122003',
      countryCode: 'IN',
    ),
  );

  final Trip ananyaTrip = await ananya.trips.planTrip(
    TripDraft(
      origin: JourneyPlaceDraft.fromSavedAddress(ananyaHome),
      destination: const JourneyPlaceDraft.typed(
        city: 'Chandigarh',
        countryCode: 'IN',
        label: 'Sector 17',
      ),
      departureAt: tomorrow,
    ),
  );

  await _expectRefused(
    "Rahul cannot read Ananya's journey",
    () => rahul.trips.trip(ananyaTrip.id),
    ApiErrorCode.tripNotFound,
  );

  await _expectRefused(
    "Rahul cannot change Ananya's journey",
    () => rahul.trips.updateTrip(
      ananyaTrip.id,
      const TripDraft(
        origin: null,
        destination: null,
        departureAt: null,
        travellerCount: 9,
      ),
    ),
    ApiErrorCode.tripNotFound,
  );

  await _expectRefused(
    "Rahul cannot cancel Ananya's journey",
    () => rahul.trips.cancelTrip(ananyaTrip.id, reason: 'not mine to cancel'),
    ApiErrorCode.tripNotFound,
  );

  await _expectRefused(
    "Rahul cannot plan a journey from Ananya's saved address",
    () => rahul.trips.planTrip(
      TripDraft(
        origin: JourneyPlaceDraft.saved(ananyaHome.id),
        destination: const JourneyPlaceDraft.typed(
          city: 'Agra',
          countryCode: 'IN',
        ),
        departureAt: tomorrow,
      ),
    ),
    // The same answer a direct read of that address gives. Anything else would
    // confirm that the address exists.
    ApiErrorCode.addressNotFound,
  );

  await _checkAsync("Ananya's journey is untouched", () async {
    final Trip reread = await ananya.trips.trip(ananyaTrip.id);
    _expect(reread.status, TripStatus.planned);
    _expect(reread.travellerCount, 1);
    _expect(reread.destination.city, 'Chandigarh');
    _expect(reread.cancellationReason, null);
  });

  await _checkAsync('neither customer can see the other in a list', () async {
    final List<Trip> his = await rahul.trips.trips(scope: TripScope.all);
    final List<Trip> hers = await ananya.trips.trips(scope: TripScope.all);

    _expect(his.any((Trip t) => t.id == ananyaTrip.id), false);
    _expect(hers.any((Trip t) => t.id == planned.id), false);
  });

  await _checkAsync("Rahul's next journey is never hers", () async {
    _expect((await rahul.trips.nextTrip())?.id, planned.id);
    _expect((await ananya.trips.nextTrip())?.id, ananyaTrip.id);
  });

  // --- 10. authentication -------------------------------------------------
  await _checkAsync('an unauthenticated call reaches no journeys', () async {
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
  await _checkAsync('a revoked session stops reaching journeys', () async {
    await rahul.client.post('/auth/logout', authenticated: true);

    try {
      await rahul.trips.trips();
      throw StateError('a revoked token still reached journeys');
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

/// Leaves the account with no journeys the run could trip over.
///
/// Cancelled rather than deleted, because there is no delete — a journey is
/// history. A departed one is left alone: nothing can change it, and it does not
/// consume the upcoming allowance.
Future<void> _cancelEverything(Session session) async {
  for (final Trip trip in await session.trips.trips(scope: TripScope.all)) {
    if (trip.isEditable) {
      await session.trips.cancelTrip(trip.id);
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
