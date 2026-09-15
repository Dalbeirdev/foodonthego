<?php

declare(strict_types=1);

namespace App\Services\Discovery;

use App\Models\Restaurant;
use App\Models\TripRoute;
use App\Services\Routing\RouteProvider;
use App\Services\Routing\RouteProviderException;
use App\Services\Routing\RouteRequest;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Log;

/**
 * What stopping at a restaurant actually costs.
 *
 * This is the number the product turns on, and it is the one that cannot be
 * guessed. A restaurant 300 m from a motorway with no junction for 20 km is
 * three hundred metres away and forty minutes' driving; a restaurant 2 km away
 * beside an interchange is four minutes. Proximity does not imply detour, and
 * treating one as the other would recommend exactly the wrong stops.
 *
 * ## How it is measured
 *
 * The provider is asked for the same journey with the restaurant inserted as an
 * intermediate point: origin → restaurant → destination. The detour is that
 * route's cost minus the selected route's own cost. Both halves come from the
 * same provider on the same request, so provider-to-provider differences in
 * distance or speed model cancel rather than accumulate.
 *
 * ## What it costs us
 *
 * One billed call per restaurant, which is why almost all of this class is about
 * not making them:
 *
 * - only the closest {@see maxEvaluations} candidates are evaluated at all;
 * - each answer is cached against the route and the restaurant, so a second
 *   customer on the same route pays nothing;
 * - the cache key includes the route uuid, so a different route — or a
 *   recalculated one — never reuses an answer;
 * - a provider failure is recorded once and stops the remaining calls, because
 *   the twelfth timeout tells us nothing the first did not.
 *
 * ## When it cannot be measured
 *
 * The answer is null. Not an estimate, not the straight-line distance doubled,
 * not zero. A null detour reaches the client as an absent badge; the restaurant
 * still carries its exact geometric figures, which were never in doubt. Inventing
 * a detour here would be inventing the one number a customer would act on.
 */
final class RestaurantDetourService
{
    public function __construct(
        private readonly RouteProvider $provider,
        private readonly int $maxEvaluations,
    ) {}

    /**
     * Detours for as many of these restaurants as the budget allows.
     *
     * Order matters: the caller passes them closest-first, so the budget is
     * spent on the candidates most likely to be worth showing.
     *
     * @param  list<Restaurant>  $restaurants
     * @return array<string, ?DetourEstimate> keyed by restaurant uuid; a key is
     *                                        present and null when the provider could not answer
     */
    public function estimateFor(TripRoute $route, array $restaurants): array
    {
        $estimates = [];
        $budget = $this->maxEvaluations;
        $providerFailed = false;

        foreach ($restaurants as $restaurant) {
            if (! $restaurant->hasPosition()) {
                continue;
            }

            $cacheKey = $this->cacheKey($route, $restaurant);

            $cached = Cache::get($cacheKey);

            if ($cached !== null) {
                // `false` is how "the provider could not answer" is remembered,
                // because Cache::get cannot distinguish a stored null from a
                // miss. It is cached deliberately and briefly: repeating a call
                // that just failed for every customer on this route turns one
                // outage into a bill.
                $estimates[$restaurant->uuid] = $cached === false
                    ? null
                    : DetourEstimate::fromArray($cached);

                continue;
            }

            if ($providerFailed || $budget <= 0) {
                $estimates[$restaurant->uuid] = null;

                continue;
            }

            $budget--;

            try {
                $estimate = $this->measure($route, $restaurant);
            } catch (RouteProviderException $e) {
                // Once, not twelve times. The remaining candidates get a null
                // detour and are ranked accordingly.
                $providerFailed = true;

                Log::warning('discovery.detour_provider_failed', [
                    'route_uuid' => $route->uuid,
                    'kind' => $e->kind->value,
                    'evaluated_before_failure' => $this->maxEvaluations - $budget - 1,
                ]);

                Cache::put($cacheKey, false, now()->addSeconds(self::FAILURE_TTL_SECONDS));

                $estimates[$restaurant->uuid] = null;

                continue;
            }

            Cache::put(
                $cacheKey,
                $estimate?->toArray() ?? false,
                now()->addSeconds(self::SUCCESS_TTL_SECONDS),
            );

            $estimates[$restaurant->uuid] = $estimate;
        }

        return $estimates;
    }

    /**
     * A detour survives longer than a discovery result does.
     *
     * The road network does not change on the minute, and this figure is the
     * expensive one. Availability — which does change — is recomputed on every
     * request and is not cached here.
     */
    private const SUCCESS_TTL_SECONDS = 3_600;

    /** Long enough to stop a stampede, short enough that recovery is quick. */
    private const FAILURE_TTL_SECONDS = 60;

    private function measure(TripRoute $route, Restaurant $restaurant): ?DetourEstimate
    {
        $trip = $route->trip;

        $result = $this->provider->calculate(new RouteRequest(
            originLatitude: (float) $trip->origin_latitude,
            originLongitude: (float) $trip->origin_longitude,
            destinationLatitude: (float) $trip->destination_latitude,
            destinationLongitude: (float) $trip->destination_longitude,
            // Alternatives would be several routes through the restaurant, and
            // the question is what the best one costs — not what the choice is.
            withAlternatives: false,
            // Traffic-aware, so the comparison is like for like with the
            // selected route's own traffic-aware duration where it has one.
            trafficAware: true,
            waypoints: [[(float) $restaurant->latitude, (float) $restaurant->longitude]],
        ));

        $viaRestaurant = $result->options[0] ?? null;

        if ($viaRestaurant === null) {
            // The provider found no route through this restaurant. That is an
            // answer, and the answer is that this is not a stop on this journey.
            return null;
        }

        $extraDistance = $viaRestaurant->distanceMeters - $route->distance_meters;

        $baseDuration = $route->traffic_duration_seconds ?? $route->duration_seconds;
        $viaDuration = $viaRestaurant->trafficDurationSeconds ?? $viaRestaurant->durationSeconds;

        $extraDuration = $viaDuration - $baseDuration;

        return new DetourEstimate(
            // Clamped at zero. A provider can return a route through a waypoint
            // that is marginally *shorter* than the one it recommended, because
            // the two were optimised for different things. "Stopping here saves
            // you two minutes" is not a claim this module is willing to make.
            extraDistanceMetres: max(0, $extraDistance),
            extraDurationSeconds: max(0, $extraDuration),
            provider: $this->provider->name(),
        );
    }

    /**
     * Keyed by the route, not the trip.
     *
     * A recalculated route gets a new uuid, so its detours are recomputed rather
     * than inherited — which is what makes "change the route and discovery
     * changes with it" true at the cache layer as well as in the service.
     */
    private function cacheKey(TripRoute $route, Restaurant $restaurant): string
    {
        return "discovery:detour:{$route->uuid}:{$restaurant->uuid}";
    }
}
