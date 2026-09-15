<?php

declare(strict_types=1);

namespace App\Services\Discovery;

use App\Enums\RestaurantAvailability;

/**
 * The two availability questions a customer might actually be asking.
 *
 * They are **not** the same question, and this enum exists because collapsing
 * them would be the module's worst mistake. A restaurant can be open by the
 * clock and not taking orders — the doors are unlocked and the kitchen has
 * stopped — so "Open now" must not silently mean "you can order here".
 *
 * {@see AcceptingOrders} is the stricter of the two and is what a customer
 * deciding where to drive actually wants.
 */
enum AvailabilityFilter: string
{
    /** Within opening hours. Says nothing about whether the kitchen is working. */
    case OpenNow = 'open_now';

    /** Open **and** taking orders. */
    case AcceptingOrders = 'accepting_orders';

    public function matches(RestaurantAvailability $availability): bool
    {
        return match ($this) {
            // Closing soon is still open. Opening soon is not.
            self::OpenNow => $availability === RestaurantAvailability::Open
                || $availability === RestaurantAvailability::ClosingSoon
                // Open by the clock, paused in the kitchen: it satisfies
                // "open now" and deliberately fails "accepting orders".
                || $availability === RestaurantAvailability::NotAcceptingOrders,

            self::AcceptingOrders => $availability->isActionable(),
        };
    }

    public function label(): string
    {
        return match ($this) {
            self::OpenNow => 'Open now',
            self::AcceptingOrders => 'Accepting orders',
        };
    }
}
