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
/// Each trip-specific code earns its own wording because each calls for a
/// different action. `TRIP_NOT_FOUND` after the customer was just looking at the
/// journey almost always means it was discarded on another device, and
/// `SAVED_ADDRESS_NOT_LOCATED` is not a fault at all — it is a saved address
/// that has never been placed on a map, and the answer is to search for it
/// rather than to retry a request that will fail identically.
String tripErrorMessage(AppStrings strings, ApiException error, {int? limit}) {
  return switch (error.code) {
    ApiErrorCode.network => strings.customerErrorOffline,
    ApiErrorCode.tripNotFound => strings.tripErrorGone,
    ApiErrorCode.tripNotEditable => strings.tripErrorNotEditable,
    ApiErrorCode.tripLimitReached => strings.tripErrorLimit(limit ?? 20),
    ApiErrorCode.originRequired => strings.tripErrorOriginRequired,
    ApiErrorCode.destinationRequired => strings.tripErrorDestinationRequired,
    ApiErrorCode.sameLocation => strings.tripErrorSamePlace,
    ApiErrorCode.invalidCoordinates => strings.tripErrorInvalidCoordinates,
    ApiErrorCode.savedAddressNotLocated =>
      strings.tripErrorSavedAddressNotLocated,
    ApiErrorCode.tripCreateFailed => strings.tripErrorCreateFailed,
    ApiErrorCode.placeLookupFailed => strings.placePickerSearchFailed,
    ApiErrorCode.placeNotFound => strings.placePickerResolveFailed,
    // A journey planned from a saved address that has since been deleted, or —
    // and the customer must not be able to tell these apart — one that was never
    // theirs.
    ApiErrorCode.addressNotFound => strings.customerErrorAddressGone,
    _ => authErrorMessage(strings, error),
  };
}

/// The first message the server gave for [field], if it gave one.
///
/// Preferred over a generic sentence wherever a screen can point at a specific
/// end of the journey: the server is the authority on why something was refused,
/// and a client that paraphrases will eventually paraphrase a rule it no longer
/// implements.
String? serverFieldError(ApiException error, String field) {
  final Object? fields = error.details?['fields'];
  if (fields is! Map<String, dynamic>) return null;

  for (final String key in <String>[
    field,
    '$field.latitude',
    '$field.longitude',
    '$field.saved_address_id',
  ]) {
    final Object? messages = fields[key];
    if (messages is List && messages.isNotEmpty) {
      final Object? first = messages.first;
      if (first is String && first.trim().isNotEmpty) return first;
    }
  }

  return null;
}
