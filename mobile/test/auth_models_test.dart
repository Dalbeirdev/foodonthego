import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/core/l10n/app_strings.dart';
import 'package:foodonthego/core/network/api_error_code.dart';
import 'package:foodonthego/core/network/api_exception.dart';
import 'package:foodonthego/core/phone/supported_country.dart';
import 'package:foodonthego/data/auth/session_store.dart';
import 'package:foodonthego/domain/models/auth_models.dart';
import 'package:foodonthego/domain/models/customer.dart';
import 'package:foodonthego/features/auth/auth_error_messages.dart';

void main() {
  group('phone input', () {
    test('a trunk zero is not part of the number', () {
      // "09876543210" and "9876543210" are one subscriber. Treating them as two
      // accounts is a real bug with real support cost.
      expect(normalizeNationalDigits('09876543210'), '9876543210');
      expect(normalizeNationalDigits('9876543210'), '9876543210');
      expect(normalizeNationalDigits('98765 43210'), '9876543210');
      expect(normalizeNationalDigits('+91-98765-43210'), '919876543210');
    });

    test('plausibility follows the country, not a global rule', () {
      expect(SupportedCountry.india.looksPlausible('9876543210'), isTrue);
      // 2 is an Indian landline range; an SMS would never arrive.
      expect(SupportedCountry.india.looksPlausible('2876543210'), isFalse);
      expect(SupportedCountry.india.looksPlausible('98765'), isFalse);
    });

    test('a country with no mobile prefix rule accepts any leading digit', () {
      final SupportedCountry us = SupportedCountry.all.firstWhere(
        (SupportedCountry c) => c.iso == 'US',
      );

      expect(us.looksPlausible('2125550123'), isTrue);
      expect(us.looksPlausible('212555012'), isFalse);
    });

    test('the country list mirrors the server, India first', () {
      // Same four markets as PhoneNormalizer::COUNTRIES.
      expect(
        SupportedCountry.all
            .map((SupportedCountry c) => c.callingCode)
            .toList(),
        <String>['91', '971', '44', '1'],
      );
      expect(SupportedCountry.fallback.iso, 'IN');
    });
  });

  group('masking', () {
    test('matches the format the server produces', () {
      expect(maskE164('+919876543210'), '+91 ••••••3210');
      expect(maskE164('+971501234567'), '+971 •••••4567');
    });

    test('the longest calling code wins', () {
      // '+971...' must not be read as '+1' followed by a national number.
      expect(maskE164('+971501234567'), startsWith('+971 '));
      expect(maskE164('+12125550123'), startsWith('+1 '));
    });

    test('an unknown country is masked more, not less', () {
      final String masked = maskE164('+33612345678');

      expect(masked, endsWith('5678'));
      expect(masked, isNot(contains('33612')));
    });
  });

  group('Customer', () {
    test('reads what the API sends and survives what it omits', () {
      final Customer customer = Customer.fromJson(const <String, dynamic>{
        'id': 'u-1',
        'first_name': 'Ravi',
        'phone': '+919876543210',
      });

      expect(customer.fullName, 'Ravi');
      expect(customer.lastName, isNull);
      expect(customer.phoneVerified, isFalse);
    });

    test('round trips through storage', () {
      const Customer original = Customer(
        id: 'u-1',
        firstName: 'Ravi',
        lastName: 'Kumar',
        phone: '+919876543210',
        email: 'ravi@example.com',
        phoneVerified: true,
      );

      final Customer restored = Customer.fromJson(original.toJson());

      expect(restored.fullName, 'Ravi Kumar');
      expect(restored.email, 'ravi@example.com');
      expect(restored.phoneVerified, isTrue);
    });
  });

  group('AuthSession', () {
    test('knows when the server said it would stop working', () {
      final AuthSession expired = AuthSession(
        accessToken: 't',
        expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
        customer: _customer,
      );
      final AuthSession live = AuthSession(
        accessToken: 't',
        expiresAt: DateTime.now().add(const Duration(days: 1)),
        customer: _customer,
      );

      expect(expired.isExpired, isTrue);
      expect(live.isExpired, isFalse);
    });

    test('a session with no stated expiry is not treated as expired', () {
      const AuthSession session = AuthSession(
        accessToken: 't',
        customer: _customer,
      );

      // Absent is not the same as past. The server is the one that decides.
      expect(session.isExpired, isFalse);
    });

    test('printing it does not print the token', () {
      const AuthSession session = AuthSession(
        accessToken: 'super-secret-token',
        customer: _customer,
      );

      // The default toString of a class holding a bearer token is a leak
      // waiting for a debugPrint.
      expect(session.toString(), isNot(contains('super-secret-token')));
    });

    test('parses the register/verify response shape', () {
      final AuthSession session = AuthSession.fromJson(<String, dynamic>{
        'access_token': 'abc',
        'expires_at': '2027-01-01T00:00:00+00:00',
        'user': <String, dynamic>{
          'id': 'u-1',
          'first_name': 'Ravi',
          'phone': '+919876543210',
        },
      });

      expect(session.accessToken, 'abc');
      expect(session.customer.firstName, 'Ravi');
      expect(session.expiresAt?.year, 2027);
    });
  });

  group('InMemorySessionStore', () {
    test('reads back what was written and forgets on clear', () async {
      final InMemorySessionStore store = InMemorySessionStore();

      expect(await store.read(), isNull);

      const AuthSession session = AuthSession(
        accessToken: 't',
        customer: _customer,
      );
      await store.write(session);
      expect((await store.read())?.accessToken, 't');

      await store.clear();
      expect(await store.read(), isNull);
    });
  });

  group('error codes', () {
    test('an unrecognised wire value is unknown, never a crash', () {
      expect(ApiErrorCode.fromWire('OTP_INVALID'), ApiErrorCode.otpInvalid);
      expect(ApiErrorCode.fromWire('INVENTED_LATER'), ApiErrorCode.unknown);
      expect(ApiErrorCode.fromWire(null), ApiErrorCode.unknown);
    });

    test('every code the backend can send is known to this build', () {
      // Mirrors App\\Enums\\ApiErrorCode. A code missing here means a customer
      // sees "something went wrong" instead of the real reason.
      const List<String> serverCodes = <String>[
        'VALIDATION_FAILED',
        'UNAUTHENTICATED',
        'FORBIDDEN',
        'NOT_FOUND',
        'METHOD_NOT_ALLOWED',
        'CONFLICT',
        'IDEMPOTENCY_KEY_REUSED',
        'RATE_LIMITED',
        'BUSINESS_RULE_VIOLATED',
        'DEPENDENCY_UNAVAILABLE',
        'SERVER_ERROR',
        'INVALID_PHONE',
        'UNSUPPORTED_PHONE_REGION',
        'OTP_SEND_FAILED',
        'OTP_RATE_LIMITED',
        'OTP_INVALID',
        'OTP_EXPIRED',
        'OTP_TOO_MANY_ATTEMPTS',
        'OTP_RESEND_TOO_SOON',
        'REGISTRATION_TOKEN_INVALID',
        'REGISTRATION_TOKEN_EXPIRED',
        'ACCOUNT_SUSPENDED',
        'ACCOUNT_DISABLED',
      ];

      for (final String code in serverCodes) {
        expect(
          ApiErrorCode.fromWire(code),
          isNot(ApiErrorCode.unknown),
          reason: '$code is not mapped in the app',
        );
      }
    });

    test('retryability distinguishes "try again" from "change something"', () {
      expect(ApiErrorCode.network.isRetryable, isTrue);
      expect(ApiErrorCode.otpSendFailed.isRetryable, isTrue);
      // Retrying a wrong code with the same code is not a recovery.
      expect(ApiErrorCode.otpInvalid.isRetryable, isFalse);
      expect(ApiErrorCode.accountSuspended.isRetryable, isFalse);
    });
  });

  group('error messages', () {
    const AppStrings strings = AppStrings();

    test('every known code gets the app\'s own wording, not the server\'s', () {
      const ApiException error = ApiException(
        code: ApiErrorCode.otpInvalid,
        // Prose the app must not echo — it may be reworded or translated.
        message: 'server-side wording that could change tomorrow',
        status: 422,
      );

      expect(authErrorMessage(strings, error), strings.authErrorOtpInvalid);
    });

    test('an unknown code falls back rather than showing raw server text', () {
      const ApiException error = ApiException(
        code: ApiErrorCode.unknown,
        message: 'Undefined index: foo in /var/www/app/Http/Thing.php:42',
        status: 500,
      );

      final String shown = authErrorMessage(strings, error);

      expect(shown, strings.authErrorGeneric);
      expect(shown, isNot(contains('/var/www')));
    });

    test('a resend cooldown quotes the seconds the server gave', () {
      const ApiException error = ApiException(
        code: ApiErrorCode.otpResendTooSoon,
        message: 'Wait.',
        status: 429,
        details: <String, dynamic>{'retry_after_seconds': 17},
      );

      expect(authErrorMessage(strings, error), contains('17'));
    });

    test('failures that cannot be retried are marked as restarts', () {
      expect(authErrorNeedsRestart(ApiErrorCode.otpExpired), isTrue);
      expect(authErrorNeedsRestart(ApiErrorCode.otpTooManyAttempts), isTrue);
      expect(
        authErrorNeedsRestart(ApiErrorCode.registrationTokenExpired),
        isTrue,
      );
      // A single wrong digit is worth another go on the same screen.
      expect(authErrorNeedsRestart(ApiErrorCode.otpInvalid), isFalse);
      expect(authErrorNeedsRestart(ApiErrorCode.network), isFalse);
    });
  });
}

const Customer _customer = Customer(
  id: 'u-1',
  firstName: 'Ravi',
  phone: '+919876543210',
);
