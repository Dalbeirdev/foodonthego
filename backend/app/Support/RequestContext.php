<?php

declare(strict_types=1);

namespace App\Support;

use Illuminate\Support\Str;

/**
 * Holds the correlation ID for the current request.
 *
 * It is generated (or accepted from an inbound `X-Request-Id`) once by
 * `AssignRequestId`, then read by the response envelope, the log formatter and the
 * exception handler — so the id a client is shown in an error body is provably the
 * same id written to the logs for that request. That is the whole point: a user
 * reporting "I got an error, here is the id" must be findable in one grep.
 */
final class RequestContext
{
    private static ?string $requestId = null;

    private static ?string $actorId = null;

    private static ?string $actorRole = null;

    public static function set(string $requestId): void
    {
        self::$requestId = $requestId;
    }

    public static function id(): string
    {
        // Generated lazily so that code running outside an HTTP request — a queued
        // job, a console command, a test — still has a usable correlation id.
        return self::$requestId ??= (string) Str::uuid();
    }

    public static function setActor(?string $id, ?string $role): void
    {
        self::$actorId = $id;
        self::$actorRole = $role;
    }

    public static function actorId(): ?string
    {
        return self::$actorId;
    }

    public static function actorRole(): ?string
    {
        return self::$actorRole;
    }

    /** Test seam: the singletons above outlive a single request inside a test process. */
    public static function reset(): void
    {
        self::$requestId = null;
        self::$actorId = null;
        self::$actorRole = null;
    }
}
