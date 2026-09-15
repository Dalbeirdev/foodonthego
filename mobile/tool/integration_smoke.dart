// A real end-to-end run: this app's own network layer against a running Laravel
// backend and a real MySQL database. No mocks, no fakes, no stubs.
//
// It exists because the widget tests prove the screens behave correctly against
// a fake, and the backend tests prove the API behaves correctly on its own — but
// neither proves the two agree on the wire. A field renamed on one side and not
// the other passes both suites and fails in a customer's hand.
//
// Run it with the backend serving and OTP_PROVIDER=log:
//
//   php artisan serve --host=127.0.0.1 --port=8000
//   dart run tool/integration_smoke.dart
//
// It reads each code from the development OTP log, which is the only place the
// log provider writes one. That file is gitignored, is never written outside a
// development environment (LogOtpProvider refuses to construct in production),
// and the codes in it are for numbers in a reserved test range.
//
// It is deliberately NOT a `flutter test`: flutter_test replaces HttpClient with
// a mock, so a "test" there could never make a real request.

import 'dart:convert';
import 'dart:io';

import 'package:foodonthego/core/config/api_config.dart';
import 'package:foodonthego/core/network/api_client.dart';
import 'package:foodonthego/core/network/api_error_code.dart';
import 'package:foodonthego/core/network/api_exception.dart';
import 'package:foodonthego/data/repositories/api_auth_repository.dart';
import 'package:foodonthego/domain/models/auth_models.dart';
import 'package:foodonthego/domain/models/customer.dart';

/// A number from the Indian range reserved for testing/documentation, so a code
/// can never be sent to a real person's handset even if a real SMS provider were
/// configured by mistake.
const String _testNational = '9999900001';
const String _countryCode = '91';

const String _otpLog = '../backend/storage/logs/otp-development.log';

int _passed = 0;
int _failed = 0;

void main(List<String> args) async {
  stdout.writeln('FoodOnTheGo — Module 03 integration run');
  stdout.writeln('Backend: ${ApiConfig.baseUrl}');
  stdout.writeln('');

  String? token;
  final ApiClient client = ApiClient(tokenReader: () async => token);
  final ApiAuthRepository auth = ApiAuthRepository(client);

  final int logOffset = await _logLength();

  // --- 1. request a code ---------------------------------------------------
  final OtpRequestResult requested = await _requestCode(auth);

  _check('the API masks the number in its response', () {
    _expect(requested.maskedPhone, '+91 ••••••0001');
  });
  _check('the response never carries the code', () {
    _expect(requested.otpLength, 6);
  });

  final String code = await _readCodeAfter(logOffset);
  _check('a code was generated and delivered to the development channel', () {
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      throw 'Expected six digits, got a ${code.length}-character value';
    }
  });

  // --- 2. a wrong code is rejected ----------------------------------------
  await _checkAsync('a wrong code is rejected by the real server', () async {
    try {
      await auth.verifyOtp(
        phone: _testNational,
        countryCode: _countryCode,
        code: _wrong(code),
      );
      throw 'A wrong code was accepted';
    } on ApiException catch (error) {
      _expect(error.code, ApiErrorCode.otpInvalid);
    }
  });

  // --- 3. the correct code ------------------------------------------------
  final OtpVerifyResult verified = await auth.verifyOtp(
    phone: _testNational,
    countryCode: _countryCode,
    code: code,
  );

  late String accessToken;
  late Customer customer;

  if (verified is OtpRegistrationRequired) {
    _check('a new number is asked to register rather than signed in', () {
      if (verified.registrationToken.isEmpty) throw 'No registration token';
    });

    _check('the registration token does not contain the phone number', () {
      if (verified.registrationToken.contains(_testNational)) {
        throw 'The number is readable inside the token';
      }
    });

    final AuthSession session = await auth.register(
      registrationToken: verified.registrationToken,
      firstName: 'Integration',
      lastName: 'Runner',
      email: null,
    );

    accessToken = session.accessToken;
    customer = session.customer;

    _check('registration returns a session for the verified number', () {
      _expect(customer.phone, '+91$_testNational');
      _expect(customer.phoneVerified, true);
      _expect(customer.emailVerified, false);
    });
  } else {
    final AuthSession session = (verified as OtpSignedIn).session;
    accessToken = session.accessToken;
    customer = session.customer;

    _check('a returning customer is signed straight in', () {
      _expect(customer.phone, '+91$_testNational');
    });
  }

  _check('the access token is a real Sanctum token', () {
    if (!accessToken.contains('|')) throw 'Not a Sanctum token shape';
  });

  // --- 4. the token works, and only for what it is for --------------------
  token = accessToken;

  final Customer me = await auth.currentCustomer();
  _check('the token authenticates /customer/me against the real API', () {
    _expect(me.id, customer.id);
  });

  _check('the profile exposes a uuid, not a database key', () {
    if (RegExp(r'^\d+$').hasMatch(me.id)) {
      throw 'The API returned a sequential id: ${me.id}';
    }
  });

  await _checkAsync('an unauthenticated call to /customer/me is 401', () async {
    final ApiClient anonymous = ApiClient();
    try {
      await anonymous.get('/customer/me', authenticated: true);
      throw 'A protected endpoint answered without a token';
    } on ApiException catch (error) {
      _expect(error.code, ApiErrorCode.unauthenticated);
      _expect(error.status, 401);
    } finally {
      anonymous.close();
    }
  });

  // --- 5. replay is refused ------------------------------------------------
  await _checkAsync('the used code cannot be replayed', () async {
    try {
      await auth.verifyOtp(
        phone: _testNational,
        countryCode: _countryCode,
        code: code,
      );
      throw 'A consumed code verified a second time';
    } on ApiException catch (error) {
      _expect(error.code, ApiErrorCode.otpExpired);
    }
  });

  // --- 6. logout revokes ---------------------------------------------------
  await auth.logout();

  await _checkAsync('logout revokes the token immediately', () async {
    try {
      await auth.currentCustomer();
      throw 'A revoked token still worked';
    } on ApiException catch (error) {
      _expect(error.code, ApiErrorCode.unauthenticated);
    }
  });

  // --- 7. a rejected number never reaches the database ---------------------
  await _checkAsync('an invalid number is refused with its own code', () async {
    try {
      await auth.requestOtp(phone: '12345', countryCode: _countryCode);
      throw 'An invalid number was accepted';
    } on ApiException catch (error) {
      _expect(error.code, ApiErrorCode.invalidPhone);
    }
  });

  // --- 8. the resend cooldown is real --------------------------------------
  await _checkAsync('the server enforces the resend cooldown', () async {
    try {
      await auth.requestOtp(phone: _testNational, countryCode: _countryCode);
      throw 'A resend inside the cooldown was allowed';
    } on ApiException catch (error) {
      _expect(error.code, ApiErrorCode.otpResendTooSoon);
      if ((error.retryAfterSeconds ?? 0) <= 0) {
        throw 'No retry_after_seconds for the client countdown';
      }
    }
  });

  client.close();

  stdout.writeln('');
  stdout.writeln('$_passed passed, $_failed failed');
  exit(_failed == 0 ? 0 : 1);
}

/// Requests a code, waiting out the server's cooldown if a previous run of this
/// script is still inside it.
///
/// The wait is not a workaround — it is the cooldown working. Running this twice
/// in a minute is exactly the "tapped resend too soon" case, and the server
/// refusing is the correct answer. The per-hour rate limit is a different thing
/// and is reported rather than waited out: sleeping for an hour would be absurd,
/// and a run that cannot get a code has nothing useful to say.
Future<OtpRequestResult> _requestCode(ApiAuthRepository auth) async {
  try {
    return await auth.requestOtp(
      phone: _testNational,
      countryCode: _countryCode,
    );
  } on ApiException catch (error) {
    if (error.code == ApiErrorCode.otpRateLimited) {
      stderr.writeln(
        'The per-phone request limit is spent for $_testNational. It resets in '
        '${error.retryAfterSeconds ?? '?'}s, or clear it with:\n'
        "  php artisan tinker --execute=\"Illuminate\\Support\\Facades\\Redis::flushdb();\"",
      );
      exit(2);
    }

    if (error.code != ApiErrorCode.otpResendTooSoon) rethrow;

    final int wait = (error.retryAfterSeconds ?? 30) + 1;
    stdout.writeln('  ..    resend cooldown is active; waiting ${wait}s');
    await Future<void>.delayed(Duration(seconds: wait));

    return auth.requestOtp(phone: _testNational, countryCode: _countryCode);
  }
}

String _wrong(String code) => code == '000000' ? '111111' : '000000';

Future<int> _logLength() async {
  final File file = File(_otpLog);
  return file.existsSync() ? file.lengthSync() : 0;
}

/// Reads the newest development code written after [offset].
Future<String> _readCodeAfter(int offset) async {
  final File file = File(_otpLog);
  if (!file.existsSync()) {
    throw StateError(
      'No development OTP log at $_otpLog. Is OTP_PROVIDER=log and the backend '
      'running from the repository checkout?',
    );
  }

  // Sliced as bytes and decoded afterwards, not the other way round. The mask
  // characters in this log are three bytes each in UTF-8 but one UTF-16 code
  // unit in a Dart string, so a byte offset used as a string index drifts
  // further out with every masked number written — and eventually throws.
  final List<int> bytes = await file.readAsBytes();
  final int from = offset.clamp(0, bytes.length);
  final String fresh = utf8.decode(bytes.sublist(from), allowMalformed: true);

  // Laravel's single-file format is "[time] channel.LEVEL: message {json}".
  final Match? match = RegExp(r'\{.*"code":"(\d+)".*\}').firstMatch(fresh);
  if (match != null) return match.group(1)!;

  final Match? loose = RegExp(r'"code":"(\d+)"').firstMatch(fresh);
  if (loose != null) return loose.group(1)!;

  throw StateError(
    'No OTP found in the development log since the run started.',
  );
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
