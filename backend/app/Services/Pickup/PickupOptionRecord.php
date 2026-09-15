<?php

declare(strict_types=1);

namespace App\Services\Pickup;

use Carbon\CarbonImmutable;

/**
 * What the server wrote down when it offered a pickup time.
 *
 * Every field here was written by the server and read back by the server. None
 * of it came from a request, and nothing in a request can change any of it —
 * which is the property that lets the selection endpoint accept a bare id and
 * still know exactly what it is agreeing to.
 */
final readonly class PickupOptionRecord
{
    public function __construct(
        public string $token,
        public string $customerUuid,
        public string $cartUuid,
        public string $tripUuid,
        public string $restaurantUuid,
        public CarbonImmutable $startAt,
        public CarbonImmutable $endAt,
        public string $timezone,
        public string $fingerprint,
        public int $planningVersion,
    ) {}
}
