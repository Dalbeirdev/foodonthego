import '../../core/l10n/app_strings.dart';
import '../../core/network/api_error_code.dart';
import '../../core/network/api_exception.dart';
import '../auth/auth_error_messages.dart';

/// Turns a failure into a sentence for a traveller.
///
/// Branches on [ApiException.code] and never on the server's prose, for the
/// reason stated on `ApiErrorCode`: the message is written for a person, may be
/// translated, and is expected to change.
///
/// The two journey-specific codes are worth their own wording. `TRIP_NOT_FOUND`
/// after the customer was just looking at the journey almost always means it was
/// cancelled on another device, and `TRIP_NOT_EDITABLE` means the screen in
/// front of them is stale — both call for "refresh", not "try again", which
/// would repeat a request that cannot start succeeding.
String tripErrorMessage(AppStrings strings, ApiException error, {int? limit}) {
  return switch (error.code) {
    ApiErrorCode.network => strings.customerErrorOffline,
    ApiErrorCode.tripNotFound => strings.tripErrorGone,
    ApiErrorCode.tripNotEditable => strings.tripErrorNotEditable,
    ApiErrorCode.tripLimitReached => strings.tripErrorLimit(limit ?? 20),
    // A journey planned from a saved address that has since been deleted, or —
    // and the customer must not be able to tell these apart — one that was never
    // theirs.
    ApiErrorCode.addressNotFound => strings.customerErrorAddressGone,
    _ => authErrorMessage(strings, error),
  };
}

/// The first message the server gave for [field], if it gave one.
///
/// Preferred over a generic sentence wherever a form can point at a field: the
/// server is the authority on why something was refused, and a client that
/// paraphrases will eventually paraphrase a rule it no longer implements.
String? serverFieldError(ApiException error, String field) {
  final Object? fields = error.details?['fields'];
  if (fields is! Map<String, dynamic>) return null;

  final Object? messages = fields[field];
  if (messages is List && messages.isNotEmpty) {
    final Object? first = messages.first;
    if (first is String && first.trim().isNotEmpty) return first;
  }

  return null;
}
