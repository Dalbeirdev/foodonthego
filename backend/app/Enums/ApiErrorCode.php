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
