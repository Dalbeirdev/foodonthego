<?php

declare(strict_types=1);

namespace App\Exceptions;

use App\Enums\ApiErrorCode;
use RuntimeException;

/**
 * A failure that is part of the API contract rather than a bug. Anything thrown
 * that is NOT one of these is treated as a bug by the handler: logged in full,
 * reported to the client as an opaque SERVER_ERROR.
 */
class ApiException extends RuntimeException
{
    /**
     * @param  array<string, mixed>|null  $details
     */
    public function __construct(
        public readonly ApiErrorCode $errorCode,
        string $message,
        public readonly ?array $details = null,
    ) {
        parent::__construct($message);
    }

    /** @param array<string, mixed>|null $details */
    public static function businessRule(string $message, ?array $details = null): self
    {
        return new self(ApiErrorCode::BusinessRuleViolated, $message, $details);
    }

    public static function notFound(string $resource = 'Resource'): self
    {
        return new self(ApiErrorCode::NotFound, "{$resource} not found.");
    }

    public static function forbidden(string $message = 'You are not allowed to perform this action.'): self
    {
        return new self(ApiErrorCode::Forbidden, $message);
    }

    /** @param array<string, mixed>|null $details */
    public static function conflict(string $message, ?array $details = null): self
    {
        return new self(ApiErrorCode::Conflict, $message, $details);
    }

    public static function dependencyUnavailable(string $dependency): self
    {
        return new self(
            ApiErrorCode::DependencyUnavailable,
            "A service FoodOnTheGo depends on is unavailable: {$dependency}.",
        );
    }
}
