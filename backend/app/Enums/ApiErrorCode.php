<?php

declare(strict_types=1);

namespace App\Enums;

/**
 * The machine-readable half of the error contract (docs/05-api-standards.md).
 *
 * Clients branch on these, never on the human-readable message, which is free to
 * change wording or be translated. Adding a case is backwards compatible; changing
 * or removing one is a breaking API change and needs a new API version.
 */
enum ApiErrorCode: string
{
    case ValidationFailed = 'VALIDATION_FAILED';
    case Unauthenticated = 'UNAUTHENTICATED';
    case Forbidden = 'FORBIDDEN';
    case NotFound = 'NOT_FOUND';
    case MethodNotAllowed = 'METHOD_NOT_ALLOWED';
    case Conflict = 'CONFLICT';
    case IdempotencyKeyReused = 'IDEMPOTENCY_KEY_REUSED';
    case RateLimited = 'RATE_LIMITED';
    case BusinessRuleViolated = 'BUSINESS_RULE_VIOLATED';
    case DependencyUnavailable = 'DEPENDENCY_UNAVAILABLE';
    case ServerError = 'SERVER_ERROR';

    // --- Module 03: customer authentication -----------------------------
    case InvalidPhone = 'INVALID_PHONE';
    case UnsupportedPhoneRegion = 'UNSUPPORTED_PHONE_REGION';
    case OtpSendFailed = 'OTP_SEND_FAILED';
    case OtpRateLimited = 'OTP_RATE_LIMITED';
    case OtpInvalid = 'OTP_INVALID';
    case OtpExpired = 'OTP_EXPIRED';
    case OtpTooManyAttempts = 'OTP_TOO_MANY_ATTEMPTS';
    case OtpResendTooSoon = 'OTP_RESEND_TOO_SOON';
    case RegistrationTokenInvalid = 'REGISTRATION_TOKEN_INVALID';
    case RegistrationTokenExpired = 'REGISTRATION_TOKEN_EXPIRED';
    case AccountSuspended = 'ACCOUNT_SUSPENDED';
    case AccountDisabled = 'ACCOUNT_DISABLED';

    // --- Module 04: profile and saved addresses -------------------------
    case AddressLimitReached = 'ADDRESS_LIMIT_REACHED';
    case AddressNotFound = 'ADDRESS_NOT_FOUND';

    // Module 05
    case TripNotFound = 'TRIP_NOT_FOUND';
    case TripLimitReached = 'TRIP_LIMIT_REACHED';
    case TripNotEditable = 'TRIP_NOT_EDITABLE';
    case TripCreateFailed = 'TRIP_CREATE_FAILED';
    case OriginRequired = 'ORIGIN_REQUIRED';
    case DestinationRequired = 'DESTINATION_REQUIRED';
    case SameLocation = 'SAME_LOCATION';
    case InvalidCoordinates = 'INVALID_COORDINATES';
    case SavedAddressNotLocated = 'SAVED_ADDRESS_NOT_LOCATED';
    case PlaceLookupFailed = 'PLACE_LOOKUP_FAILED';
    case PlaceNotFound = 'PLACE_NOT_FOUND';

    // --- Module 06: maps, routing, distance and travel time -------------
    //
    // Six of these describe a *routing provider* rather than the request, and
    // they are separate because the customer's next move differs for each: retry
    // (unavailable, timeout), wait (rate limited), change an endpoint (no
    // route), or nothing at all (response invalid — ours to fix).
    case RouteInputInvalid = 'ROUTE_INPUT_INVALID';
    case RouteNotFound = 'ROUTE_NOT_FOUND';
    case RouteSelectionInvalid = 'ROUTE_SELECTION_INVALID';
    case RouteStale = 'ROUTE_STALE';
    case RouteAlreadyCurrent = 'ROUTE_ALREADY_CURRENT';
    case RouteNoRouteFound = 'ROUTE_NO_ROUTE_FOUND';
    case RouteProviderUnavailable = 'ROUTE_PROVIDER_UNAVAILABLE';
    case RouteProviderRateLimited = 'ROUTE_PROVIDER_RATE_LIMITED';
    case RouteTimeout = 'ROUTE_TIMEOUT';
    case RouteResponseInvalid = 'ROUTE_RESPONSE_INVALID';
    case RouteCalculationInProgress = 'ROUTE_CALCULATION_IN_PROGRESS';

    // --- Module 07: restaurant discovery ---------------------------------
    //
    // RouteNotReady is deliberately distinct from RouteNotFound. The route
    // exists and the customer can see it; it is simply not in a state discovery
    // can search along, and the client's answer is to send them back to the
    // route screen rather than to report a missing journey.
    case RouteNotReady = 'ROUTE_NOT_READY';
    case DiscoveryFailed = 'DISCOVERY_FAILED';
    case DiscoveryRateLimited = 'DISCOVERY_RATE_LIMITED';
    case RestaurantDataUnavailable = 'RESTAURANT_DATA_UNAVAILABLE';
    case DetourProviderUnavailable = 'DETOUR_PROVIDER_UNAVAILABLE';

    public function httpStatus(): int
    {
        return match ($this) {
            self::ValidationFailed => 422,
            self::Unauthenticated => 401,
            self::Forbidden => 403,
            self::NotFound => 404,
            self::MethodNotAllowed => 405,
            self::Conflict, self::IdempotencyKeyReused => 409,
            // 422, not 409: the request is well formed and the conflict is with a
            // limit rather than with another version of the same resource.
            self::AddressLimitReached => 422,
            // 404, and deliberately the same answer an address that does not
            // exist gets — see CustomerAddressService::ownedByOrFail().
            self::AddressNotFound => 404,
            // Same reasoning again, for journeys: not-yours and does-not-exist
            // are one answer, so the endpoint cannot be walked to discover which
            // identifiers are real.
            self::TripNotFound => 404,
            self::TripLimitReached,
            // 422 rather than 409: the request is valid, the journey is simply
            // past the point where changing it means anything.
            self::TripNotEditable,
            self::OriginRequired,
            self::DestinationRequired,
            self::SameLocation,
            self::InvalidCoordinates,
            // 422 and not 404: the address exists and is the caller's own. What
            // is missing is a map position, and the app's job is to go and get
            // one rather than to report the address as gone.
            self::SavedAddressNotLocated => 422,

            self::TripCreateFailed => 500,

            // 503: the place provider is a dependency, and a caller that gets
            // this should retry rather than change its request.
            self::PlaceLookupFailed => 503,
            self::PlaceNotFound => 404,

            // The request named a trip whose endpoints cannot be routed between.
            self::RouteInputInvalid => 422,
            // 404, and the same answer a route belonging to somebody else gets.
            self::RouteNotFound => 404,
            self::RouteSelectionInvalid => 422,
            // The stored route was calculated for endpoints that have since
            // moved. 409 rather than 422: nothing in the request is wrong, the
            // resource has simply moved underneath it.
            self::RouteStale => 409,
            self::RouteAlreadyCurrent => 409,
            // 422 and not 503: the provider answered perfectly well. There is no
            // driving route, and retrying will be told the same thing.
            self::RouteNoRouteFound => 422,
            self::RouteProviderUnavailable => 503,
            // 429 passed through, so a client can back off the way it would for
            // any other rate limit. It carries nothing about our quota.
            self::RouteProviderRateLimited => 429,
            self::RouteTimeout => 504,
            // Ours. The provider answered and the answer was not usable, which is
            // a bug or a contract change on our side of the adapter.
            self::RouteResponseInvalid => 502,
            // Another calculation for this trip is already running. 409 so a
            // double tap is told plainly rather than starting a second one.
            self::RouteCalculationInProgress => 409,

            self::RouteNotReady => 409,
            self::DiscoveryFailed => 500,
            self::DiscoveryRateLimited => 429,
            self::RestaurantDataUnavailable => 503,
            self::DetourProviderUnavailable => 503,
            self::RateLimited => 429,
            self::BusinessRuleViolated => 422,
            self::DependencyUnavailable => 503,
            self::ServerError => 500,

            self::InvalidPhone,
            self::UnsupportedPhoneRegion,
            self::OtpInvalid,
            self::OtpExpired,
            self::OtpTooManyAttempts => 422,

            // 429 for both: a resend asked for too early is a rate limit, and
            // giving it its own status would let a caller distinguish "too soon"
            // from "too many" and tune an abuse loop against it.
            self::OtpRateLimited,
            self::OtpResendTooSoon => 429,

            self::RegistrationTokenInvalid,
            self::RegistrationTokenExpired => 401,

            // 403, not 401: the caller proved who they are. They are not allowed.
            self::AccountSuspended,
            self::AccountDisabled => 403,

            self::OtpSendFailed => 503,
        };
    }
}
