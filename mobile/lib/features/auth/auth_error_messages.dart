import '../../core/l10n/app_strings.dart';
import '../../core/network/api_error_code.dart';
import '../../core/network/api_exception.dart';

/// Turns an [ApiException] into something a customer can act on.
///
/// The mapping is on the *code*, never on the server's message text: the message
/// is prose written for a human, it may be reworded or translated, and a client
/// that parses it breaks the first time somebody improves it.
///
/// Where a known code exists the app's own wording wins — so the same failure
/// reads the same way whichever endpoint produced it. Anything unrecognised
/// falls back to a generic sentence rather than showing an unvetted string from
/// the network.
String authErrorMessage(AppStrings strings, ApiException error) {
  return switch (error.code) {
    ApiErrorCode.network => strings.authErrorOffline,
    ApiErrorCode.invalidPhone => strings.authErrorInvalidPhone,
    ApiErrorCode.unsupportedPhoneRegion => strings.authErrorUnsupportedRegion,
    ApiErrorCode.otpSendFailed => strings.authErrorOtpSendFailed,
    ApiErrorCode.otpInvalid => strings.authErrorOtpInvalid,
    ApiErrorCode.otpExpired => strings.authErrorOtpExpired,
    ApiErrorCode.otpTooManyAttempts => strings.authErrorOtpTooManyAttempts,
    ApiErrorCode.otpResendTooSoon => strings.authErrorOtpResendTooSoon(
      error.retryAfterSeconds ?? 30,
    ),
    ApiErrorCode.otpRateLimited ||
    ApiErrorCode.rateLimited => strings.authErrorOtpRateLimited,
    ApiErrorCode.registrationTokenInvalid ||
    ApiErrorCode.registrationTokenExpired =>
      strings.authErrorRegistrationExpired,
    ApiErrorCode.accountSuspended => strings.authErrorAccountSuspended,
    ApiErrorCode.accountDisabled => strings.authErrorAccountDisabled,

    // VALIDATION_FAILED is handled by the screen that owns the field, so a
    // reaching this point means a field the screen does not render — generic is
    // the honest answer.
    _ => strings.authErrorGeneric,
  };
}

/// Whether the failure means the customer must start the flow again rather than
/// retry what they just did.
bool authErrorNeedsRestart(ApiErrorCode code) => switch (code) {
  ApiErrorCode.otpExpired ||
  ApiErrorCode.otpTooManyAttempts ||
  ApiErrorCode.registrationTokenInvalid ||
  ApiErrorCode.registrationTokenExpired => true,
  _ => false,
};
