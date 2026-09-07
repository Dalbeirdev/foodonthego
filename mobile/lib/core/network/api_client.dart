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

  /// [headers] carries the few request headers a caller genuinely needs to
  /// set — today only `Idempotency-Key`, which is what makes a retry after a
  /// lost response safe. Deliberately not a general escape hatch: it cannot
  /// overwrite `Authorization`, `Accept` or `Content-Type`, so a caller cannot
  /// accidentally send a request unauthenticated or as the wrong media type.
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = false,
    Map<String, String> headers = const <String, String>{},
  }) => _send(
    'POST',
    path,
    body: body,
    authenticated: authenticated,
    headers: headers,
  );

  /// [headers] carries `Idempotency-Key` where a caller wants a retry after a
  /// lost response to be safe. PATCH and DELETE take it for the same reason
  /// POST does: they are unsafe requests, and a connection that dies after the
  /// server acted but before the answer arrived leaves the client unable to
  /// tell that from a request that never landed.
  Future<Map<String, dynamic>> patch(
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = false,
    Map<String, String> headers = const <String, String>{},
  }) => _send(
    'PATCH',
    path,
    body: body,
    authenticated: authenticated,
    headers: headers,
  );

  Future<Map<String, dynamic>> delete(
    String path, {
    bool authenticated = false,
    Map<String, String> headers = const <String, String>{},
  }) => _send('DELETE', path, authenticated: authenticated, headers: headers);

  /// For the endpoints where a null `data` is a real answer rather than a fault.
  ///
  /// `/customer/trips/next` is the case: a customer with no journey planned has
  /// no next journey, and that is an ordinary state, not a 404. Routing it
  /// through [get] would turn the null into an empty map and the caller would
  /// build a journey out of nothing.
  Future<Map<String, dynamic>?> getOrNull(
    String path, {
    bool authenticated = false,
  }) async {
    final Object? data = await _sendRaw(
      'GET',
      path,
      authenticated: authenticated,
    );

    return data is Map<String, dynamic> ? data : null;
  }

  /// For the endpoints whose `data` is a list rather than an object.
  ///
  /// A separate method rather than a dynamic return, so a caller cannot forget
  /// which shape it is dealing with and index into the wrong one.
  Future<List<dynamic>> getList(
    String path, {
    bool authenticated = false,
  }) async {
    final Object? data = await _sendRaw(
      'GET',
      path,
      authenticated: authenticated,
    );

    return data is List ? data : const <dynamic>[];
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = false,
    Map<String, String> headers = const <String, String>{},
  }) async {
    final Object? data = await _sendRaw(
      method,
      path,
      body: body,
      authenticated: authenticated,
      extraHeaders: headers,
    );

    return data is Map<String, dynamic> ? data : <String, dynamic>{};
  }

  /// The transport. Returns whatever was under `data` — an object for most
  /// endpoints, a list for the collection ones.
  Future<Object?> _sendRaw(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = false,
    Map<String, String> extraHeaders = const <String, String>{},
  }) async {
    final Uri uri = ApiConfig.uri(path);

    final Map<String, String> headers = <String, String>{
      // The caller's first, so the three below always win. Nothing a caller
      // passes can make a request anonymous or change its media type.
      ...extraHeaders,
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
      return _unwrap(response);
    } on ApiException catch (error) {
      // Only for requests that actually presented a credential: a 401 from the
      // OTP endpoints means "wrong code", not "your session ended".
      if (authenticated) onAuthenticationFailure?.call(error.code);
      rethrow;
    }
  }

  Object? _unwrap(http.Response response) {
    Map<String, dynamic>? payload;
    try {
      final Object? decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) payload = decoded;
    } on FormatException {
      payload = null;
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (payload == null) {
        // 204 No Content is a legitimate empty success — logout and delete both
        // return one.
        if (response.body.isEmpty) return const <String, dynamic>{};

        throw ApiException(
          code: ApiErrorCode.unknown,
          message: 'The server sent a response the app could not read.',
          status: response.statusCode,
        );
      }

      return payload['data'];
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
