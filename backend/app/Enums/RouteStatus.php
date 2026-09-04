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
 * Module 05 only ever produces {@see NotCalculated}. The other three cases exist
 * so Module 06 does not have to migrate the column, and nothing in this module
 * can set them.
 */
enum RouteStatus: string
{
    case NotCalculated = 'NOT_CALCULATED';
    case Calculating = 'CALCULATING';
    case Ready = 'READY';
    case Failed = 'FAILED';

    /** @return list<string> */
    public static function values(): array
    {
        return array_map(static fn (self $case): string => $case->value, self::cases());
    }
}
