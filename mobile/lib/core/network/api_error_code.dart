/// The machine-readable error codes the API can return.
///
/// These mirror `App\Enums\ApiErrorCode` on the backend. The app branches on
/// these and **never** on the human message: the message is written for a
/// person, may be translated, and is expected to change. A client that parses
/// prose breaks the first time somebody improves the wording.
///
/// [unknown] is not a failure of this list — a newer server may send a code an
/// older app has never heard of, and the app must degrade to a generic message
/// rather than crash.
enum ApiErrorCode {
  validationFailed('VALIDATION_FAILED'),
  unauthenticated('UNAUTHENTICATED'),
  forbidden('FORBIDDEN'),
  notFound('NOT_FOUND'),
  methodNotAllowed('METHOD_NOT_ALLOWED'),
  conflict('CONFLICT'),
  idempotencyKeyReused('IDEMPOTENCY_KEY_REUSED'),
  rateLimited('RATE_LIMITED'),
  businessRuleViolated('BUSINESS_RULE_VIOLATED'),
  dependencyUnavailable('DEPENDENCY_UNAVAILABLE'),
  serverError('SERVER_ERROR'),

  invalidPhone('INVALID_PHONE'),
  unsupportedPhoneRegion('UNSUPPORTED_PHONE_REGION'),
  otpSendFailed('OTP_SEND_FAILED'),
  otpRateLimited('OTP_RATE_LIMITED'),
  otpInvalid('OTP_INVALID'),
  otpExpired('OTP_EXPIRED'),
  otpTooManyAttempts('OTP_TOO_MANY_ATTEMPTS'),
  otpResendTooSoon('OTP_RESEND_TOO_SOON'),
  registrationTokenInvalid('REGISTRATION_TOKEN_INVALID'),
  registrationTokenExpired('REGISTRATION_TOKEN_EXPIRED'),
  accountSuspended('ACCOUNT_SUSPENDED'),
  accountDisabled('ACCOUNT_DISABLED'),

  addressLimitReached('ADDRESS_LIMIT_REACHED'),
  addressNotFound('ADDRESS_NOT_FOUND'),

  tripNotFound('TRIP_NOT_FOUND'),
  tripLimitReached('TRIP_LIMIT_REACHED'),

  /// The trip has already been discarded, so there is nothing left to change.
  /// Almost always means the screen in front of the customer is stale.
  tripNotEditable('TRIP_NOT_EDITABLE'),

  /// The trip could not be written. Distinct from a validation failure: nothing
  /// the customer typed is wrong, so the screen offers a retry rather than
  /// pointing at a field.
  tripCreateFailed('TRIP_CREATE_FAILED'),

  originRequired('ORIGIN_REQUIRED'),
  destinationRequired('DESTINATION_REQUIRED'),

  /// Both ends resolve to the same place.
  sameLocation('SAME_LOCATION'),

  /// A coordinate outside the possible range, or the (0, 0) sentinel that means
  /// "nothing ever set this".
  invalidCoordinates('INVALID_COORDINATES'),

  /// A saved address the customer chose has never been located, so it cannot be
  /// one end of a journey. The answer is to locate it — never to invent a
  /// position for it.
  savedAddressNotLocated('SAVED_ADDRESS_NOT_LOCATED'),

  /// The place provider failed. Ours, not the customer's.
  placeLookupFailed('PLACE_LOOKUP_FAILED'),

  placeNotFound('PLACE_NOT_FOUND'),

  /// The request never reached the server, or never came back.
  network('NETWORK'),

  /// A code this build does not know, or a response that was not the documented
  /// envelope at all.
  unknown('UNKNOWN');

  const ApiErrorCode(this.wire);

  /// The string the API actually sends.
  final String wire;

  static ApiErrorCode fromWire(String? value) {
    if (value == null) return ApiErrorCode.unknown;

    for (final ApiErrorCode code in ApiErrorCode.values) {
      if (code.wire == value) return code;
    }
    return ApiErrorCode.unknown;
  }

  /// Whether retrying the same request unchanged could plausibly succeed.
  ///
  /// Drives whether a screen offers "Try again" or asks the customer to change
  /// something first.
  bool get isRetryable => switch (this) {
    ApiErrorCode.network ||
    ApiErrorCode.serverError ||
    ApiErrorCode.dependencyUnavailable ||
    ApiErrorCode.otpSendFailed ||
    // Ours failing, not the customer's request being wrong. The same query a
    // moment later may well work, so "Try again" is the honest control.
    ApiErrorCode.placeLookupFailed ||
    ApiErrorCode.tripCreateFailed => true,
    _ => false,
  };
}
