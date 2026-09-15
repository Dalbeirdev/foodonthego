<?php

declare(strict_types=1);

namespace App\Enums;

/**
 * What the customer means by a trip.
 *
 * `ROUTE_PENDING` is what Module 05 produces, and the name is the honest one: the
 * customer has said where they are going, and the platform has not yet worked out
 * how. Calling it `ACTIVE` would claim a route exists.
 *
 * There is no `ON_THE_ROAD`, `ARRIVED` or `COMPLETED`. Those are claims about a
 * traveller's physical position, and nothing in the product can observe one yet —
 * no GPS stream, no route, no arrival signal. The restaurant queue is eventually
 * sorted by expected arrival, so an invented travel state becomes an invented
 * cooking time. The modules that can establish those states will add them.
 *
 * @see RouteStatus for the separate question of whether the route has been calculated.
 */
enum TripStatus: string
{
    /** Saved on the server but not yet handed to route calculation. */
    case RoutePending = 'ROUTE_PENDING';

    /** Discarded by the customer before it was used. */
    case Cancelled = 'CANCELLED';

    /** @return list<string> */
    public static function values(): array
    {
        return array_map(static fn (self $case): string => $case->value, self::cases());
    }

    public function label(): string
    {
        return match ($this) {
            self::RoutePending => 'Journey created',
            self::Cancelled => 'Cancelled',
        };
    }

    /** Whether the owner can still change or discard this trip. */
    public function isOpen(): bool
    {
        return $this === self::RoutePending;
    }
}
