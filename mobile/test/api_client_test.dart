import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/core/network/api_client.dart';
import 'package:foodonthego/core/network/api_error_code.dart';
import 'package:foodonthego/core/network/api_exception.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The client's only job beyond transport is the response envelope. These tests
/// pin that contract, including the shapes a proxy or a gateway can produce that
/// are not our envelope at all.
void main() {
  ApiClient clientReturning(
    int status,
    String body, {
    Future<String?> Function()? token,
    void Function(http.Request request)? capture,
    void Function(ApiErrorCode code)? onAuthFailure,
  }) {
    return ApiClient(
      httpClient: MockClient((http.Request request) async {
        capture?.call(request);
        return http.Response(
          body,
          status,
          headers: <String, String>{'content-type': 'application/json'},
        );
      }),
      tokenReader: token,
      onAuthenticationFailure: onAuthFailure,
    );
  }

  group('success', () {
    test('unwraps the data envelope', () async {
      final ApiClient client = clientReturning(
        200,
        jsonEncode(<String, dynamic>{
          'data': <String, dynamic>{'phone_masked': '+91 ••••••3210'},
          'meta': <String, dynamic>{'request_id': 'req-1'},
        }),
      );

      expect(await client.get('/anything'), <String, dynamic>{
        'phone_masked': '+91 ••••••3210',
      });
    });

    test('an empty 204 is a success, not a parse failure', () async {
      final ApiClient client = ApiClient(
        httpClient: MockClient(
          (http.Request request) async => http.Response('', 204),
        ),
      );

      // Logout returns one of these.
      expect(await client.post('/auth/logout'), isEmpty);
    });
  });

  group('failure', () {
    test('maps the error code and keeps the request id', () async {
      final ApiClient client = clientReturning(
        422,
        jsonEncode(<String, dynamic>{
          'error': <String, dynamic>{
            'code': 'OTP_INVALID',
            'message': "That code isn't correct.",
            'request_id': 'req-2',
          },
        }),
      );

      try {
        await client.post('/auth/customer/otp/verify');
        fail('Expected the failure to surface.');
      } on ApiException catch (error) {
        expect(error.code, ApiErrorCode.otpInvalid);
        expect(error.status, 422);
        // The one thing support can use to find the matching server log line.
        expect(error.requestId, 'req-2');
      }
    });

    test(
      'a code this build has never seen degrades rather than crashing',
      () async {
        final ApiClient client = clientReturning(
          422,
          jsonEncode(<String, dynamic>{
            'error': <String, dynamic>{
              'code': 'SOMETHING_INVENTED_LATER',
              'message': 'New rule.',
            },
          }),
        );

        // A newer server must not break an older app.
        await expectLater(
          client.post('/x'),
          throwsA(
            isA<ApiException>().having(
              (ApiException e) => e.code,
              'code',
              ApiErrorCode.unknown,
            ),
          ),
        );
      },
    );

    test(
      'an HTML gateway page becomes a server error, not a parse crash',
      () async {
        final ApiClient client = ApiClient(
          httpClient: MockClient(
            (http.Request request) async =>
                http.Response('<html>502 Bad Gateway</html>', 502),
          ),
        );

        await expectLater(
          client.get('/x'),
          throwsA(
            isA<ApiException>()
                .having(
                  (ApiException e) => e.code,
                  'code',
                  ApiErrorCode.serverError,
                )
                .having(
                  (ApiException e) => e.message,
                  'message',
                  isNot(contains('html')),
                ),
          ),
        );
      },
    );

    test('a dropped connection is a network failure', () async {
      final ApiClient client = ApiClient(
        httpClient: MockClient(
          (http.Request request) async =>
              throw http.ClientException('Connection closed'),
        ),
      );

      await expectLater(
        client.get('/x'),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.code,
            'code',
            ApiErrorCode.network,
          ),
        ),
      );
    });

    test('retry_after_seconds is read off the details', () async {
      final ApiClient client = clientReturning(
        429,
        jsonEncode(<String, dynamic>{
          'error': <String, dynamic>{
            'code': 'OTP_RESEND_TOO_SOON',
            'message': 'Wait.',
            'details': <String, dynamic>{'retry_after_seconds': 25},
          },
        }),
      );

      try {
        await client.post('/x');
        fail('Expected a failure.');
      } on ApiException catch (error) {
        expect(error.retryAfterSeconds, 25);
      }
    });

    test('validation fields are exposed per field', () async {
      final ApiClient client = clientReturning(
        422,
        jsonEncode(<String, dynamic>{
          'error': <String, dynamic>{
            'code': 'VALIDATION_FAILED',
            'message': 'Invalid.',
            'details': <String, dynamic>{
              'fields': <String, dynamic>{
                'first_name': <String>['Please tell us your first name.'],
              },
            },
          },
        }),
      );

      try {
        await client.post('/x');
        fail('Expected a failure.');
      } on ApiException catch (error) {
        expect(error.fieldErrors['first_name'], <String>[
          'Please tell us your first name.',
        ]);
      }
    });
  });

  group('credentials', () {
    test(
      'a token is sent in the Authorization header and nowhere else',
      () async {
        http.Request? seen;
        final ApiClient client = clientReturning(
          200,
          '{"data":{}}',
          token: () async => 'secret-token',
          capture: (http.Request request) => seen = request,
        );

        await client.get('/customer/me', authenticated: true);

        expect(seen?.headers['Authorization'], 'Bearer secret-token');
        // A token in a URL ends up in access logs, proxy logs and Referer headers.
        expect(seen?.url.toString(), isNot(contains('secret-token')));
      },
    );

    test('an unauthenticated call carries no credential at all', () async {
      http.Request? seen;
      final ApiClient client = clientReturning(
        200,
        '{"data":{}}',
        token: () async => 'secret-token',
        capture: (http.Request request) => seen = request,
      );

      await client.post('/auth/customer/otp/request');

      expect(seen?.headers.containsKey('Authorization'), isFalse);
    });

    test('the token is read per request, never captured once', () async {
      final List<String> tokens = <String>['first', 'second'];
      final List<String?> sent = <String?>[];

      final ApiClient client = clientReturning(
        200,
        '{"data":{}}',
        token: () async => tokens.removeAt(0),
        capture: (http.Request request) =>
            sent.add(request.headers['Authorization']),
      );

      await client.get('/a', authenticated: true);
      await client.get('/b', authenticated: true);

      // A re-issued session must take effect on the next call rather than
      // leaving a stale credential inside a long-lived object.
      expect(sent, <String>['Bearer first', 'Bearer second']);
    });

    test('a rejected authenticated request reports the lost session', () async {
      final List<ApiErrorCode> reported = <ApiErrorCode>[];

      final ApiClient client = clientReturning(
        401,
        jsonEncode(<String, dynamic>{
          'error': <String, dynamic>{
            'code': 'UNAUTHENTICATED',
            'message': 'Authentication is required.',
          },
        }),
        token: () async => 'expired',
        onAuthFailure: reported.add,
      );

      await expectLater(
        client.get('/customer/me', authenticated: true),
        throwsA(isA<ApiException>()),
      );

      expect(reported, <ApiErrorCode>[ApiErrorCode.unauthenticated]);
    });

    test('a 401 from an unauthenticated endpoint is not a lost session', () async {
      final List<ApiErrorCode> reported = <ApiErrorCode>[];

      final ApiClient client = clientReturning(
        401,
        jsonEncode(<String, dynamic>{
          'error': <String, dynamic>{
            'code': 'REGISTRATION_TOKEN_INVALID',
            'message': 'Invalid.',
          },
        }),
        onAuthFailure: reported.add,
      );

      await expectLater(
        client.post('/auth/customer/register'),
        throwsA(isA<ApiException>()),
      );

      // Registration failing does not mean an existing session ended — signing
      // the customer out here would be wrong.
      expect(reported, isEmpty);
    });
  });
}
