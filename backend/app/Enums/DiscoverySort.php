<?php

declare(strict_types=1);

namespace App\Enums;

/**
 * The orders a customer may ask for.
 *
 * An enum rather than a validated string, and the difference is not stylistic: a
 * sort value can only ever become one of these cases, each of which has a
 * hand-written comparator behind it. There is no path by which `sort=` reaches
 * a column name, an `ORDER BY`, or anything else a query planner will read.
 *
 * {@see isAvailable()} is what keeps this honest. Sorting by rating is a
 * perfectly good idea that this product cannot offer yet, because no restaurant
 * has a rating — so the case exists, the contract is settled, and asking for it
 * is refused with a reason rather than answered with an arbitrary order.
 */
enum DiscoverySort: string
{
    /** The deterministic relevance score. Route convenience dominates. */
    case Recommended = 'recommended';

    /** Ascending detour duration. What stopping costs, cheapest first. */
    case LowestDetour = 'lowest_detour';

    /** Ascending distance along the route. The next chance to stop, first. */
    case SoonestAlongRoute = 'soonest_along_route';

    /** Descending rating. Unavailable until there is a reviews module. */
    case HighestRated = 'highest_rated';

    /** Ascending price level. */
    case PriceLowToHigh = 'price_low_to_high';

    /** @return list<string> */
    public static function values(): array
    {
        return array_map(static fn (self $case): string => $case->value, self::cases());
    }

    /**
     * Whether this product can honestly offer this order today.
     *
     * Rating sorting is refused because every `rating_average` is null: any
     * order it produced would be arbitrary, and an arbitrary order presented as
     * "Highest rated" is a lie about restaurants.
     *
     * Price sorting *is* offered — `price_level` is real metadata an operator
     * declared — even though every fixture currently shares a level. A sort with
     * nothing to distinguish is stable and harmless; a sort over data that does
     * not exist is not.
     */
    public function isAvailable(): bool
    {
        return $this !== self::HighestRated;
    }

    /** Why it is unavailable, for the client to show or to log. */
    public function unavailableReason(): ?string
    {
        return $this === self::HighestRated
            ? 'No restaurant has a rating yet.'
            : null;
    }

    public function label(): string
    {
        return match ($this) {
            self::Recommended => 'Recommended',
            self::LowestDetour => 'Lowest detour',
            self::SoonestAlongRoute => 'Soonest along route',
            self::HighestRated => 'Highest rated',
            self::PriceLowToHigh => 'Price: low to high',
        };
    }
}
