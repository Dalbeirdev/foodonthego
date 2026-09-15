<?php

declare(strict_types=1);

namespace App\Support\Pickup;

use App\Models\Cart;
use App\Models\Restaurant;
use App\Models\RestaurantOpeningHour;
use App\Support\Trip\EndpointFingerprint;

/**
 * A deterministic fingerprint of the facts a pickup plan was made under.
 *
 * A pickup window is only meaningful alongside what produced it. "4:10 PM" was
 * a good answer for a cart of one quick dish, on a route calculated two minutes
 * ago, at a restaurant that was taking orders. Change any of those and it is
 * still 4:10 PM on the screen and no longer a claim anybody checked.
 *
 * So the selection carries a hash of its inputs, and reads STALE the moment they
 * move. Compared, never parsed: it is opaque on purpose, and nothing anywhere
 * should be reading a fact back out of it.
 *
 * Modelled on {@see EndpointFingerprint}, which does the same
 * job for routes, and derived rather than stored for the same reason — a stored
 * copy is a second thing to update, and the day somebody forgets, plans quietly
 * stop being invalidated.
 */
final class PlanningFingerprint
{
    public static function of(Cart $cart): string
    {
        $restaurant = $cart->restaurant;
        $route = $cart->trip?->selectedRoute;

        return self::fromParts(
            // The cart's own counter, which moves when its CONTENTS move.
            // Deliberately not `updated_at`: a price correction touches the row
            // and changes nothing about how long the kitchen needs, and
            // invalidating a good window over it would be an insult dressed as
            // caution.
            cartVersion: (int) $cart->version,
            routeUuid: $route?->uuid,
            routeCalculatedAt: $route?->calculated_at?->toIso8601String(),
            restaurantUuid: $restaurant?->uuid,
            // Both, not just the paused flag. A restaurant suspended outright
            // has changed the answer at least as much as one that has paused
            // its orders, and `status` is where this schema keeps that.
            isAcceptingOrders: (bool) $restaurant?->is_accepting_orders,
            status: $restaurant?->status?->value,
            hoursFingerprint: self::hours($restaurant),
        );
    }

    public static function fromParts(
        int $cartVersion,
        ?string $routeUuid,
        ?string $routeCalculatedAt,
        ?string $restaurantUuid,
        bool $isAcceptingOrders,
        ?string $status,
        string $hoursFingerprint,
    ): string {
        $canonical = implode('|', [
            'v'.(int) config('foodonthego.pickup.planning_version'),
            (string) $cartVersion,
            $routeUuid ?? '',
            $routeCalculatedAt ?? '',
            $restaurantUuid ?? '',
            $isAcceptingOrders ? '1' : '0',
            $status ?? '',
            $hoursFingerprint,
        ]);

        return hash('sha256', $canonical);
    }

    /**
     * The restaurant's whole schedule, in a fixed order.
     *
     * Sorted explicitly rather than trusting the order rows come back in. Two
     * identical schedules that happened to be inserted in a different order are
     * the same schedule, and a fingerprint that disagreed would mark every plan
     * stale for no reason a customer could see.
     */
    private static function hours(?Restaurant $restaurant): string
    {
        if ($restaurant === null) {
            return '';
        }

        $rows = $restaurant->openingHours
            ->map(static fn (RestaurantOpeningHour $h): string => implode(':', [
                (int) $h->day_of_week,
                (string) $h->opens_at,
                (string) $h->closes_at,
            ]))
            ->sort()
            ->values()
            ->all();

        return hash('sha256', implode(',', $rows));
    }
}
