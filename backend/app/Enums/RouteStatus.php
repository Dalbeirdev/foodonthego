<?php

declare(strict_types=1);

namespace App\Enums;

/**
 * How far the route calculation has got.
 *
 * Deliberately separate from {@see TripStatus}. A trip's status is about the
 * customer's intent; this is about a technical job that has not been written
 * yet. Conflating them would mean a trip could not be "the customer's current
 * plan" and "waiting for a route" at the same time, which is exactly the state
 * every trip is in after Module 05.
 *
 * Module 05 only ever produced {@see NotCalculated}. Module 06 drives the rest.
 *
 * The three failure-ish cases are deliberately distinct, because a customer can
 * do something different about each. {@see Failed} is ours — the provider was
 * unreachable, slow or wrong — and the answer is to try again. {@see NoRoute} is
 * the provider succeeding and saying there is no driving route between these two
 * places, and no amount of retrying changes that; the answer is to change an
 * endpoint. {@see Stale} means the trip's endpoints have moved since the route
 * was calculated, so the stored geometry describes a journey nobody is taking.
 */
enum RouteStatus: string
{
    case NotCalculated = 'NOT_CALCULATED';
    case Calculating = 'CALCULATING';
    case Ready = 'READY';
    case Failed = 'FAILED';
    case NoRoute = 'NO_ROUTE';
    case Stale = 'STALE';

    /** @return list<string> */
    public static function values(): array
    {
        return array_map(static fn (self $case): string => $case->value, self::cases());
    }

    /**
     * Whether a stored route set can still be shown.
     *
     * Only {@see Ready}. A stale route has real geometry for the wrong journey,
     * which is more dangerous than no geometry at all: it looks entirely
     * plausible and is wrong by hundreds of kilometres.
     */
    public function hasUsableRoute(): bool
    {
        return $this === self::Ready;
    }

    /** Whether asking the provider again could plausibly change the answer. */
    public function isRetryable(): bool
    {
        return match ($this) {
            self::Failed, self::NotCalculated, self::Stale => true,
            // NoRoute is the provider's considered answer, not a fault. Calling
            // again spends money to be told the same thing.
            self::NoRoute, self::Ready, self::Calculating => false,
        };
    }
}
