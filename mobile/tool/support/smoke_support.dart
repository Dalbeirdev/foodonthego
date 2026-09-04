// Shared machinery for the per-module integration runs.
//
// Extracted when Module 06 added a second one: two copies of a sign-in helper
// are two things that drift, and the OTP-cooldown handling in particular is
// subtle enough that nobody should have to get it right twice.
//
// These scripts drive **this app's own network layer** against a running Laravel
// server and a real database. No mocks, no fakes, no stubs.

import 'dart:convert';
import 'dart:io';

import 'package:foodonthego/core/network/api_client.dart';
import 'package:foodonthego/core/network/api_error_code.dart';
import 'package:foodonthego/core/network/api_exception.dart';
import 'package:foodonthego/data/repositories/api_auth_repository.dart';
import 'package:foodonthego/data/repositories/api_customer_repository.dart';
import 'package:foodonthego/data/repositories/api_place_repository.dart';
import 'package:foodonthego/data/repositories/api_discovery_repository.dart';
import 'package:foodonthego/data/repositories/api_route_repository.dart';
import 'package:foodonthego/data/repositories/api_trip_repository.dart';
import 'package:foodonthego/domain/models/auth_models.dart';
import 'package:foodonthego/domain/models/saved_address.dart';
import 'package:foodonthego/domain/models/trip.dart';
import 'package:foodonthego/domain/repositories/trip_repository.dart';

const String countryCode = '91';

const String otpLog = '../backend/storage/logs/otp-development.log';

int passed = 0;
int failed = 0;

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
  ApiRouteRepository? _routes;
  ApiDiscoveryRepository? _discovery;

  ApiCustomerRepository get customer =>
      _customer ??= ApiCustomerRepository(client);

  ApiTripRepository get trips => _trips ??= ApiTripRepository(client);

  ApiPlaceRepository get places => _places ??= ApiPlaceRepository(client);

  ApiRouteRepository get routes => _routes ??= ApiRouteRepository(client);

  ApiDiscoveryRepository get discovery =>
      _discovery ??= ApiDiscoveryRepository(client);

  void close() => client.close();
}

Future<Session> signIn(
  String firstName,
  String? lastName,
  String national,
) async {
  final ApiClient client = ApiClient();
  final ApiAuthRepository auth = ApiAuthRepository(client);

  final int offset = await logLength();
  await requestCode(auth, national);
  final String code = await readCodeAfter(offset);

  final OtpVerifyResult result = await auth.verifyOtp(
    phone: national,
    countryCode: countryCode,
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
Future<void> discardEverything(Session session) async {
  for (final Trip trip in await session.trips.trips(scope: TripScope.all)) {
    if (trip.isDiscardable) {
      await session.trips.discardTrip(trip.id);
    }
  }
}

Future<void> clearAddresses(Session session) async {
  for (final SavedAddress address in await session.customer.addresses()) {
    await session.customer.deleteAddress(address.id);
  }
}

/// Asks for a code, waiting out the resend cooldown if a previous run just used
/// this number.
///
/// The cooldown is Module 03 working correctly, not a fault — so the tool waits
/// for it rather than the product being loosened to make a test convenient.
Future<void> requestCode(ApiAuthRepository auth, String national) async {
  for (int attempt = 0; attempt < 3; attempt++) {
    try {
      await auth.requestOtp(phone: national, countryCode: countryCode);
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

Future<int> logLength() async {
  final File file = File(otpLog);
  return file.existsSync() ? file.lengthSync() : 0;
}

Future<String> readCodeAfter(int offset) async {
  final File file = File(otpLog);
  if (!file.existsSync()) {
    throw StateError('No development OTP log at $otpLog.');
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
Future<void> expectRefused(
  String description,
  Future<Object?> Function() body,
  ApiErrorCode expected,
) async {
  try {
    await body();
    failed++;
    stdout.writeln('  FAIL  $description\n        the call succeeded');
  } on ApiException catch (error) {
    if (error.code == expected) {
      passed++;
      stdout.writeln('  PASS  $description');
    } else {
      failed++;
      stdout.writeln(
        '  FAIL  $description\n        expected $expected, got ${error.code}',
      );
    }
  }
}

void expectValue(Object? actual, Object? expected) {
  if (actual != expected) throw 'expected $expected, got $actual';
}

void check(String description, void Function() body) {
  try {
    body();
    passed++;
    stdout.writeln('  PASS  $description');
  } catch (error) {
    failed++;
    final String detail = error is ApiException
        ? '$error ${error.details}'
        : '$error';
    stdout.writeln('  FAIL  $description\n        $detail');
  }
}

Future<void> checkAsync(
  String description,
  Future<void> Function() body,
) async {
  try {
    await body();
    passed++;
    stdout.writeln('  PASS  $description');
  } catch (error) {
    failed++;
    final String detail = error is ApiException
        ? '$error ${error.details}'
        : '$error';
    stdout.writeln('  FAIL  $description\n        $detail');
  }
}
