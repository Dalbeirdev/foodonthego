import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'api_error_code.dart';
import 'api_exception.dart';

/// Reads the current bearer token, or null when nobody is signed in.
///
/// A callback rather than a stored string so the client always sees the live
/// token: a session restored, refreshed or revoked between two calls must not
/// leave a stale credential captured inside this object.
typedef TokenReader = Future<String?> Function();

/// Called when an *authenticated* request comes back with a code meaning the
/// credential is finished. Lets one rejected request anywhere in the app end the
/// session everywhere, rather than each screen discovering it separately.
typedef AuthenticationFailureHandler = void Function(ApiErrorCode code);

/// The single place the app speaks HTTP.
///
/// It knows about exactly one thing beyond the transport: the response envelope
/// agreed in docs/05-api-standards.md. Every success is `{data, meta}` and every
/// failure is `{error: {code, message, details?, request_id}}`, so unwrapping it
/// once here means no screen ever indexes into a raw JSON map.
class ApiClient {
  ApiClient({
    http.Client? httpClient,
    this.tokenReader,
    this.onAuthenticationFailure,
  }) : _http = httpClient ?? http.Client();

  final http.Client _http;

  /// Public because a named parameter cannot be private in Dart, and injecting
  /// this is how a test drives the client without a real session store.
  final TokenReader? tokenReader;

  /// See [AuthenticationFailureHandler]. Null in the sign-in screens' own
  /// client, where a 401 is an expected answer rather than a lost session.
  final AuthenticationFailureHandler? onAuthenticationFailure;

  Future<Map<String, dynamic>> get(String path, {bool authenticated = false}) =>
      _send('GET', path, authenticated: authenticated);

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = false,
  }) => _send('POST', path, body: body, authenticated: authenticated);

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = false,
  }) async {
    final Uri uri = ApiConfig.uri(path);

    final Map<String, String> headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };

    if (authenticated) {
      final String? token = await tokenReader?.call();
      if (token != null && token.isNotEmpty) {
        // Authorization header only. A token in a query string ends up in access
        // logs, proxy logs and Referer headers.
        headers['Authorization'] = 'Bearer $token';
      }
    }

    http.Response response;
    try {
      final http.Request request = http.Request(method, uri)
        ..headers.addAll(headers);
      if (body != null) {
        request.body = jsonEncode(body);
      }

      final http.StreamedResponse streamed = await _http
          .send(request)
          .timeout(ApiConfig.requestTimeout);
      response = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw const ApiException.network();
    } on SocketException {
      throw const ApiException.network();
    } on http.ClientException {
      throw const ApiException.network();
    }

    try {
      return _decode(response);
    } on ApiException catch (error) {
      // Only for requests that actually presented a credential: a 401 from the
      // OTP endpoints means "wrong code", not "your session ended".
      if (authenticated) onAuthenticationFailure?.call(error.code);
      rethrow;
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic>? payload;
    try {
      final Object? decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) payload = decoded;
    } on FormatException {
      payload = null;
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (payload == null) {
        // 204 No Content is a legitimate empty success — logout returns one.
        if (response.body.isEmpty) return const <String, dynamic>{};

        throw ApiException(
          code: ApiErrorCode.unknown,
          message: 'The server sent a response the app could not read.',
          status: response.statusCode,
        );
      }

      final Object? data = payload['data'];
      return data is Map<String, dynamic> ? data : <String, dynamic>{};
    }

    final Object? error = payload?['error'];
    if (error is! Map<String, dynamic>) {
      // A gateway HTML page, a proxy error, an empty 502. Not our envelope, so
      // there is nothing trustworthy to show the customer.
      throw ApiException(
        code: response.statusCode >= 500
            ? ApiErrorCode.serverError
            : ApiErrorCode.unknown,
        message: 'Something went wrong. Please try again.',
        status: response.statusCode,
      );
    }

    final Object? details = error['details'];

    throw ApiException(
      code: ApiErrorCode.fromWire(error['code'] as String?),
      message: (error['message'] as String?) ?? 'Something went wrong.',
      status: response.statusCode,
      requestId: error['request_id'] as String?,
      details: details is Map<String, dynamic> ? details : null,
    );
  }

  void close() => _http.close();
}
