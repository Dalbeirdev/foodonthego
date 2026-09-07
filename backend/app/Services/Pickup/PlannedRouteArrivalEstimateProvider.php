<?php

declare(strict_types=1);

namespace App\Services\Pickup;

use App\Models\Restaurant;
use App\Models\Trip;
use App\Services\Discovery\DiscoveredRestaurant;
use App\Services\Discovery\RestaurantDiscoveryService;
use Carbon\CarbonImmutable;

/**
 * Arrival, from the journey the customer planned.
 *
 * **The approximation, stated once and plainly: this assumes the customer sets
 * off now.** `trips` has no departure time and Module 13 does not track anybody,
 * so the reference point is the server's clock at the moment of planning. A
 * customer who plans at three and leaves at four has an estimate an hour adrift,
 * and nothing here can know it. That is the single largest inaccuracy in the
 * module and the first thing the live ETA engine removes.
 *
 * The travel figure itself is Module 07's: the selected route's traffic-aware
 * duration multiplied by the fraction of the route at which the restaurant sits.
 * It is read from the discovery result, which is cached — so planning a pickup,
 * and re-planning it, costs no routing provider call at all.
 */
final class PlannedRouteArrivalEstimateProvider implements ArrivalEstimateProvider
{
    public function __construct(private readonly RestaurantDiscoveryService $discovery) {}

    public function estimate(
        Trip $trip,
        Restaurant $restaurant,
        CarbonImmutable $now,
    ): ?ArrivalEstimate {
        $route = $trip->selectedRoute;

        if ($route === null) {
            return null;
        }

        $found = $this->onRoute($trip, $restaurant, $now);

        // No usable time-ahead means no honest arrival estimate. Returning
        // "now" or "now plus something" would be inventing the one number this
        // whole module hangs on.
        if ($found?->timeAheadSeconds === null) {
            return null;
        }

        $calculatedAt = $route->calculated_at
            ? CarbonImmutable::parse($route->calculated_at)
            : null;

        $maxAge = (int) config('foodonthego.pickup.route_estimate_max_age_seconds');

        return new ArrivalEstimate(
            arrivalAt: $now->addSeconds($found->timeAheadSeconds),
            travelSeconds: $found->timeAheadSeconds,
            source: 'planned_route',
            calculatedAt: $calculatedAt,

            // Age is measured on the route calculation, not on the discovery
            // cache: a cached discovery result derived from a fresh route is
            // fresh, and one derived from a stale route is not, however
            // recently it was recomputed.
            isFresh: $calculatedAt !== null
                && $calculatedAt->diffInSeconds($now, absolute: true) <= $maxAge,
        );
    }

    /**
     * The restaurant's place on this journey, from the cached discovery result.
     */
    private function onRoute(
        Trip $trip,
        Restaurant $restaurant,
        CarbonImmutable $now,
    ): ?DiscoveredRestaurant {
        $result = $this->discovery->discover($trip, $now);

        foreach ($result->restaurants as $candidate) {
            if ((int) $candidate->restaurant->id === (int) $restaurant->id) {
                return $candidate;
            }
        }

        // Off the corridor. The cart's restaurant is no longer on the road the
        // customer is taking, which is a planning refusal rather than a
        // zero-minute drive.
        return null;
    }
}
