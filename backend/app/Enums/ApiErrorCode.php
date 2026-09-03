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

    public function httpStatus(): int
    {
        return match ($this) {
            self::ValidationFailed => 422,
            self::Unauthenticated => 401,
            self::Forbidden => 403,
            self::NotFound => 404,
            self::MethodNotAllowed => 405,
            self::Conflict, self::IdempotencyKeyReused => 409,
            self::RateLimited => 429,
            self::BusinessRuleViolated => 422,
            self::DependencyUnavailable => 503,
            self::ServerError => 500,
        };
    }
}
