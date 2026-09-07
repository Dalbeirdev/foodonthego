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

    // Module 09. Three codes for what a customer experiences as one thing —
    // "I can't see this restaurant" — because the client's next move differs.
    //
    // NotFound sends them back to the list: the restaurant does not exist, or
    // is not theirs to see, and the two are answered identically on purpose so
    // that a probe cannot tell an id apart from a permission.
    //
    // Unavailable keeps them where they are and explains: the restaurant is
    // real and was on their route a minute ago, and has since been suspended
    // or closed. That is a different sentence and a different button.
    //
    // OutsideRoute is neither. The restaurant is trading and the customer may
    // see it — it is simply not on the journey they asked about, so its detour
    // and distance-ahead figures do not exist and inventing them would be the
    // one thing this product must never do.
    case RestaurantNotFound = 'RESTAURANT_NOT_FOUND';
    case RestaurantUnavailable = 'RESTAURANT_UNAVAILABLE';
    case RestaurantOutsideRoute = 'RESTAURANT_OUTSIDE_ROUTE';
    case DetailLoadFailed = 'DETAIL_LOAD_FAILED';

    // Module 10. A menu is customer-facing content, so most of what can go
    // wrong here is already covered by the restaurant codes above — a menu
    // cannot be reached for a restaurant that cannot be reached.
    //
    // MenuNotAvailable is the case where the restaurant is fine and the menu is
    // not: nothing published, or nothing a customer may see. It is a 200 in
    // practice — an empty menu is an answer, not a failure — and the code
    // exists for the paths where it is genuinely an error.
    //
    // ItemNotFound covers three situations that are answered identically on
    // purpose: no such item, an item belonging to another restaurant, and an
    // item withdrawn from the menu. Telling them apart would let anybody with a
    // list of ids map another restaurant's menu.
    case MenuNotAvailable = 'MENU_NOT_AVAILABLE';
    case ItemNotFound = 'ITEM_NOT_FOUND';
    case ItemUnavailable = 'ITEM_UNAVAILABLE';

    /*
     |--------------------------------------------------------------------------
     | Module 11 — customization and the cart
     |--------------------------------------------------------------------------
     |
     | Deliberately fine-grained. A customer who cannot add a dish deserves to
     | be told which part of their choice is the problem, and a screen can only
     | focus the right group if the server names it.
     */

    /** The kitchen has run out. Distinct from withdrawn: it may come back. */
    case ItemSoldOut = 'ITEM_SOLD_OUT';

    case VariantRequired = 'VARIANT_REQUIRED';
    case VariantInvalid = 'VARIANT_INVALID';
    case VariantUnavailable = 'VARIANT_UNAVAILABLE';

    case ModifierRequired = 'MODIFIER_REQUIRED';
    case ModifierMinNotMet = 'MODIFIER_MIN_NOT_MET';
    case ModifierMaxExceeded = 'MODIFIER_MAX_EXCEEDED';
    case ModifierInvalid = 'MODIFIER_INVALID';
    case ModifierUnavailable = 'MODIFIER_UNAVAILABLE';

    case QuantityInvalid = 'QUANTITY_INVALID';
    case QuantityLimitExceeded = 'QUANTITY_LIMIT_EXCEEDED';

    case SpecialInstructionsTooLong = 'SPECIAL_INSTRUCTIONS_TOO_LONG';

    case RestaurantNotAcceptingOrders = 'RESTAURANT_NOT_ACCEPTING_ORDERS';

    /**
     * The cart holds another restaurant's food, or belongs to another journey.
     *
     * Refusals rather than merges. Emptying a customer's cart to make an API
     * call succeed is a decision they should make, and the screen that lets
     * them make it is Module 12's.
     */
    case CartRestaurantConflict = 'CART_RESTAURANT_CONFLICT';
    case CartTripConflict = 'CART_TRIP_CONFLICT';
    case CartLineLimitReached = 'CART_LINE_LIMIT_REACHED';
    case CartNotFound = 'CART_NOT_FOUND';

    /**
     * The dish costs more than the customer was shown.
     *
     * Not an error in the usual sense — nothing is wrong — but the add is
     * refused so the customer can look at the new figure before agreeing to it.
     */
    case PriceUpdated = 'PRICE_UPDATED';

    // --- pickup planning (Module 13) -------------------------------------
    //
    // A pickup window is a claim about time, and every way a claim about time
    // can go wrong gets its own code: the customer's next move is different for
    // each, and "something went wrong with your pickup time" is not a move.
    case PreparationDataUnavailable = 'PREPARATION_DATA_UNAVAILABLE';
    case PickupOptionsUnavailable = 'PICKUP_OPTIONS_UNAVAILABLE';
    case PickupOptionNotFound = 'PICKUP_OPTION_NOT_FOUND';
    case PickupOptionExpired = 'PICKUP_OPTION_EXPIRED';
    case PickupOptionStale = 'PICKUP_OPTION_STALE';
    case PickupOptionForbidden = 'PICKUP_OPTION_FORBIDDEN';
    case PickupTimeInvalid = 'PICKUP_TIME_INVALID';
    case PickupOutsideHours = 'PICKUP_OUTSIDE_HOURS';
    case PickupBeforeReady = 'PICKUP_BEFORE_READY';
    case NoFeasiblePickupWindow = 'NO_FEASIBLE_PICKUP_WINDOW';

    // RouteStale is Module 06's and is reused rather than redeclared: a route
    // whose estimate has aged out is the same fact whoever noticed it.
    case CartVersionConflict = 'CART_VERSION_CONFLICT';
    case PreCheckoutInvalid = 'PRECHECKOUT_INVALID';

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

            // 404 for both. A suspended restaurant answering 403 while a
            // non-existent one answers 404 tells anyone with a list of uuids
            // exactly which businesses this platform has suspended.
            self::RestaurantNotFound => 404,
            self::RestaurantUnavailable => 404,
            // 409: the request is well formed and the customer is entitled to
            // it; it conflicts with the route they have selected.
            self::RestaurantOutsideRoute => 409,
            self::DetailLoadFailed => 500,

            self::MenuNotAvailable => 409,
            // 404 for both, and the same 404 a missing restaurant gets. An
            // item on another restaurant's menu must not answer differently
            // from one that does not exist.
            self::ItemNotFound => 404,
            self::ItemUnavailable => 404,

            // Module 11. The 422s are "your choice does not work"; the 409s are
            // "the world moved". A customer can fix the first by changing
            // something on screen, and the second by looking again.
            self::ItemSoldOut => 409,
            self::VariantRequired => 422,
            self::VariantInvalid => 422,
            self::VariantUnavailable => 409,
            self::ModifierRequired => 422,
            self::ModifierMinNotMet => 422,
            self::ModifierMaxExceeded => 422,
            self::ModifierInvalid => 422,
            self::ModifierUnavailable => 409,
            self::QuantityInvalid => 422,
            self::QuantityLimitExceeded => 422,
            self::SpecialInstructionsTooLong => 422,
            self::RestaurantNotAcceptingOrders => 409,
            self::CartRestaurantConflict => 409,
            self::CartTripConflict => 409,
            self::CartLineLimitReached => 409,
            self::CartNotFound => 404,
            self::PriceUpdated => 409,

            // 409 for "the world moved", 422 for "your request does not work",
            // 404 for "no such thing", 403 for "not yours" — the same split
            // Module 11 established.
            self::PreparationDataUnavailable => 409,
            self::PickupOptionsUnavailable => 409,
            self::PickupOptionNotFound => 404,
            self::PickupOptionExpired => 409,
            self::PickupOptionStale => 409,
            self::PickupOptionForbidden => 404,
            self::PickupTimeInvalid => 422,
            self::PickupOutsideHours => 422,
            self::PickupBeforeReady => 422,
            self::NoFeasiblePickupWindow => 409,
            self::CartVersionConflict => 409,
            self::PreCheckoutInvalid => 409,
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
