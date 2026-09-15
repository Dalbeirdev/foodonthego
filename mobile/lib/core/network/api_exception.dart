import 'api_error_code.dart';

/// A failed API call, in the app's own vocabulary.
///
/// Screens catch this and branch on [code]. They never render [message] from an
/// unexpected failure and never render [requestId] as prose — but [requestId] is
/// kept because it is the one thing support can use to find the matching server
/// log line, and it is shown deliberately on the generic error screen.
class ApiException implements Exception {
  const ApiException({
    required this.code,
    required this.message,
    this.status,
    this.requestId,
    this.details,
  });

  /// A request that never completed: no DNS, no route, no response.
  const ApiException.network()
    : code = ApiErrorCode.network,
      message = 'The request could not be completed.',
      status = null,
      requestId = null,
      details = null;

  final ApiErrorCode code;

  /// The server's message. Safe to show for the codes the app knows about —
  /// they are written for customers — and deliberately not shown otherwise.
  final String message;

  final int? status;
  final String? requestId;

  /// Extra machine-readable context, e.g. `retry_after_seconds`.
  final Map<String, dynamic>? details;

  /// Seconds the server asked us to wait, when it said.
  int? get retryAfterSeconds {
    final Object? value = details?['retry_after_seconds'];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }

  /// Field-level validation errors, keyed by field name.
  Map<String, List<String>> get fieldErrors {
    final Object? fields = details?['fields'];
    if (fields is! Map) return const <String, List<String>>{};

    return fields.map(
      (Object? key, Object? value) => MapEntry<String, List<String>>(
        key.toString(),
        value is List
            ? value.map((Object? item) => item.toString()).toList()
            : <String>[value.toString()],
      ),
    );
  }

  @override
  String toString() => 'ApiException(${code.wire}, status: $status)';
}
