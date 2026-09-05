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

  // --- Module 06: maps, routing, distance and travel time ------------------
  //
  // Six of these describe a routing *provider* rather than the request, and
  // they are separate because the customer's next move differs for each: retry,
  // wait, change an endpoint, or nothing at all.

  /// The journey's endpoints cannot be routed between.
  routeInputInvalid('ROUTE_INPUT_INVALID'),

  /// No such route on this journey — or it was never this customer's.
  routeNotFound('ROUTE_NOT_FOUND'),

  routeSelectionInvalid('ROUTE_SELECTION_INVALID'),

  /// The stored route was worked out for endpoints that have since moved.
  routeStale('ROUTE_STALE'),

  routeAlreadyCurrent('ROUTE_ALREADY_CURRENT'),

  /// The provider looked and there is no driving route. Retrying will be told
  /// the same thing.
  routeNoRouteFound('ROUTE_NO_ROUTE_FOUND'),

  routeProviderUnavailable('ROUTE_PROVIDER_UNAVAILABLE'),
  routeProviderRateLimited('ROUTE_PROVIDER_RATE_LIMITED'),
  routeTimeout('ROUTE_TIMEOUT'),

  /// The provider answered and the server could not use the answer. Ours.
  routeResponseInvalid('ROUTE_RESPONSE_INVALID'),

  routeCalculationInProgress('ROUTE_CALCULATION_IN_PROGRESS'),

  /// Module 07. The route exists and the customer can see it; it is simply not
  /// in a state discovery can search along. Distinct from [routeNotFound],
  /// because the answer is to send them back to the route screen rather than to
  /// report a missing journey.
  routeNotReady('ROUTE_NOT_READY'),
  discoveryFailed('DISCOVERY_FAILED'),
  discoveryRateLimited('DISCOVERY_RATE_LIMITED'),
  restaurantDataUnavailable('RESTAURANT_DATA_UNAVAILABLE'),
  detourProviderUnavailable('DETOUR_PROVIDER_UNAVAILABLE'),

  /// Module 09. Three codes for what a customer experiences as one thing —
  /// "I can't see this restaurant" — because the next move differs.
  ///
  /// [restaurantNotFound] sends them back to the list. [restaurantUnavailable]
  /// keeps them where they are and explains: it was on their route a minute
  /// ago and has since been withdrawn. [restaurantOutsideRoute] is neither —
  /// the restaurant is trading and they may see it, it is simply not on the
  /// journey they asked about.
  restaurantNotFound('RESTAURANT_NOT_FOUND'),
  restaurantUnavailable('RESTAURANT_UNAVAILABLE'),
  restaurantOutsideRoute('RESTAURANT_OUTSIDE_ROUTE'),
  detailLoadFailed('DETAIL_LOAD_FAILED'),

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
    ApiErrorCode.tripCreateFailed ||
    // Ours or the provider's, not the customer's request. The same call a
    // moment later may well work.
    ApiErrorCode.routeProviderUnavailable ||
    ApiErrorCode.routeTimeout ||
    ApiErrorCode.routeProviderRateLimited ||
    ApiErrorCode.routeResponseInvalid ||
    ApiErrorCode.discoveryFailed ||
    ApiErrorCode.restaurantDataUnavailable ||
    ApiErrorCode.detourProviderUnavailable ||
    // Ours. A restaurant that exists and is on the route, whose detail we
    // failed to assemble, is worth asking for again.
    ApiErrorCode.detailLoadFailed => true,
    _ => false,
  };
}
