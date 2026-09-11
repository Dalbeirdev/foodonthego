<?php

declare(strict_types=1);

namespace App\Services\Discovery;

use App\Enums\ApiErrorCode;
use App\Exceptions\ApiException;
use App\Models\Restaurant;
use App\Models\Trip;
use App\Models\TripRoute;
use App\Services\Routing\RouteCalculationService;
use App\Support\Geo\Coordinate;
use App\Support\Geo\RouteGeometry;
use App\Support\Route\PolylineException;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Log;

/**
 * Which FoodOnTheGo restaurants a traveller can conveniently stop at on **this**
 * route.
 *
 * Not "restaurants near me". The difference is the product: a restaurant a
 * kilometre away but behind the driver is worse than one forty kilometres ahead
 * beside the road, and no amount of proximity sorting discovers that.
 *
 * ## The two stages, and why there are two
 *
 * Stage one is a bounding-box query the database answers from an index. It
 * over-selects — a box has corners a corridor does not — and it is meant to: its
 * job is to turn "every restaurant in the country" into "a few hundred that
 * could plausibly be on this road", cheaply.
 *
 * Stage two is exact, and runs only over what stage one returned: the true
 * distance from each restaurant to the route geometry, where along the route it
 * sits, and — for the closest few only — what stopping there actually costs in
 * road distance and time.
 *
 * Collapsing the two would mean either scanning the table for every trip, or
 * asking a routing provider about restaurants three states away. Both are how
 * this feature becomes unaffordable.
 */
final class RestaurantDiscoveryService
{
    public function __construct(
        private readonly RouteCalculationService $routes,
        private readonly RestaurantDiscoveryEligibilityService $eligibility,
        private readonly RestaurantAvailabilityService $availability,
        private readonly RestaurantDetourService $detours,
        private readonly DiscoveryRankingService $ranking,
    ) {}

    /**
     * @return DiscoveryResult the restaurants, and what the search cost
     *
     * @throws ApiException when the trip has no usable selected route
     */
    public function discover(Trip $trip, CarbonImmutable $now): DiscoveryResult
    {
        $route = $this->selectedRouteOrFail($trip);

        $cacheKey = $this->cacheKey($route);
        $ttl = (int) config('foodonthego.discovery.cache_ttl_seconds');

        /** @var ?array{uuids: list<string>, candidates: int, evaluated: int} $cached */
        $cached = $ttl > 0 ? Cache::get($cacheKey) : null;

        if ($cached !== null) {
            // The *selection* is cached, never the rendered payload. Availability
            // is recomputed from live time and live rows on the way out, and
            // eligibility is re-checked — so a restaurant suspended thirty
            // seconds ago cannot ride a warm cache onto a customer's screen.
            $rebuilt = $this->rebuildFromCache($route, $cached, $now);

            if ($rebuilt !== null) {
                return $rebuilt;
            }
        }

        $result = $this->search($route, $now);

        if ($ttl > 0) {
            Cache::put($cacheKey, [
                'uuids' => array_map(
                    static fn (DiscoveredRestaurant $d): string => $d->restaurant->uuid,
                    $result->restaurants,
                ),
                'candidates' => $result->candidateCount,
                'evaluated' => $result->detourEvaluatedCount,
            ], now()->addSeconds($ttl));
        }

        return $result;
    }

    /**
     * The route to search along.
     *
     * {@see RouteCalculationService::selectedRouteFor()} already refuses a route
     * whose trip's endpoints have moved, so a stale route cannot reach this
     * method — Module 07 does not re-implement that check, it depends on it.
     *
     * The selected route specifically, not the recommended one: a customer who
     * chose the alternative through Alwar must be shown the restaurants on the
     * road through Alwar.
     *
     * @throws ApiException
     */
    private function selectedRouteOrFail(Trip $trip): TripRoute
    {
        $this->routes->invalidateIfEndpointsChanged($trip);

        $route = $this->routes->selectedRouteFor($trip->refresh());

        if ($route === null) {
            throw new ApiException(
                ApiErrorCode::RouteNotReady,
                'This journey needs a calculated route before we can find food on it.',
            );
        }

        return $route;
    }

    private function search(TripRoute $route, CarbonImmutable $now): DiscoveryResult
    {
        $started = microtime(true);

        try {
            $geometry = RouteGeometry::fromEncoded(
                $route->encoded_polyline,
                (float) config('foodonthego.discovery.geometry_simplify_tolerance_metres'),
            );
        } catch (PolylineException $e) {
            // A route whose geometry will not decode is not a route this module
            // can search along, and the alternative — measuring against a
            // straight line between the endpoints — would quietly recommend
            // restaurants nowhere near the road.
            Log::warning('discovery.route_geometry_unreadable', [
                'route_uuid' => $route->uuid,
                'reason' => $e->getMessage(),
            ]);

            throw new ApiException(
                ApiErrorCode::DiscoveryFailed,
                'We could not read the shape of your route.',
            );
        }

        $corridor = (float) config('foodonthego.discovery.corridor_metres');

        // --- stage one: what the index can answer ----------------------------
        $box = $geometry->boundingBox($corridor);

        $candidates = Restaurant::query()
            ->discoverable()
            ->withinBox($box['south'], $box['west'], $box['north'], $box['east'])
            // Eager-loaded, all three, in three queries rather than three per
            // restaurant. Availability reads opening hours for every candidate
            // and the card reads cuisines and facilities for every result.
            ->with(['cuisines', 'facilities', 'openingHours'])
            ->limit((int) config('foodonthego.discovery.max_candidates'))
            ->get();

        $candidateCount = $candidates->count();

        // --- stage two: exact geometry, over the survivors -------------------
        $withinCorridor = [];

        foreach ($candidates as $restaurant) {
            // Belt and braces. The scope already filtered on the same rule, and
            // this is the authority — a disagreement between them is a bug that
            // fails closed here rather than reaching a customer.
            if (! $this->eligibility->isEligible($restaurant)) {
                continue;
            }

            $projection = $geometry->project(new Coordinate(
                (float) $restaurant->latitude,
                (float) $restaurant->longitude,
            ));

            if ($projection->proximityMetres > $corridor) {
                // Let through by the box's corners, rejected by the corridor.
                // This is the stage-one over-selection being paid back, and it
                // costs no provider call.
                continue;
            }

            $withinCorridor[] = ['restaurant' => $restaurant, 'projection' => $projection];
        }

        // Closest first, so the detour budget is spent where it is most likely
        // to buy a result worth showing.
        usort(
            $withinCorridor,
            static fn (array $a, array $b): int => $a['projection']->proximityMetres <=> $b['projection']->proximityMetres,
        );

        // --- stage three: what stopping costs, for the closest few -----------
        $estimates = $this->detours->estimateFor(
            $route,
            array_map(static fn (array $c): Restaurant => $c['restaurant'], $withinCorridor),
        );

        $maxDetourDistance = (int) config('foodonthego.discovery.max_detour_distance_metres');
        $maxDetourDuration = (int) config('foodonthego.discovery.max_detour_duration_seconds');

        $discovered = [];
        $evaluated = 0;

        foreach ($withinCorridor as $candidate) {
            /** @var Restaurant $restaurant */
            $restaurant = $candidate['restaurant'];
            $projection = $candidate['projection'];

            $detour = $estimates[$restaurant->uuid] ?? null;

            if ($detour !== null) {
                $evaluated++;

                if (! $detour->isWithin($maxDetourDistance, $maxDetourDuration)) {
                    // Geometrically close, and a long way round by road. This is
                    // the case the whole two-stage design exists to catch.
                    continue;
                }
            }

            $availability = $this->availability->availabilityOf($restaurant, $now);

            $backtracking = $projection->isAtRouteStart()
                && $projection->proximityMetres > self::BACKTRACK_TOLERANCE_METRES;

            $discovered[] = new DiscoveredRestaurant(
                restaurant: $restaurant,
                projection: $projection,
                availability: $availability,
                detour: $detour,
                timeAheadSeconds: $this->timeAhead($route, $projection->progressFraction()),
                relevanceScore: $this->ranking->score(
                    $availability,
                    $detour,
                    $projection->proximityMetres,
                    $restaurant->rating_average,
                    $backtracking,
                ),
                requiresBacktracking: $backtracking,
            );
        }

        // Ordered by journey sequence, and **not** truncated.
        //
        // Module 07 used to cut this to the result limit here, which was right
        // when the endpoint returned it directly and wrong the moment Module 08
        // began filtering: a "Parking" filter applied to the top 25 by relevance
        // silently hides the twenty-sixth restaurant, which may be the only one
        // with a car park. Filtering has to see the whole eligible set, so the
        // limit moved to where it belongs — pagination, after the filters.
        $this->orderForReading($discovered);

        $result = new DiscoveryResult(
            route: $route,
            restaurants: $discovered,
            candidateCount: $candidateCount,
            withinCorridorCount: count($withinCorridor),
            detourEvaluatedCount: $evaluated,
            durationMs: (int) round((microtime(true) - $started) * 1000),
            fromCache: false,
        );

        // Counts, not places. How many candidates a corridor produced is an
        // operational question; where somebody is going is not.
        Log::info('discovery.completed', [
            'trip_uuid' => $route->trip->uuid,
            'route_uuid' => $route->uuid,
            'candidates' => $candidateCount,
            'within_corridor' => count($withinCorridor),
            'detour_evaluated' => $evaluated,
            'returned' => count($discovered),
            'duration_ms' => $result->durationMs,
            'cache' => 'miss',
        ]);

        return $result;
    }

    /**
     * Rebuild a cached selection against live rows.
     *
     * Returns null — forcing a full search — whenever the cached set no longer
     * describes reality: a restaurant has been suspended, un-listed, deleted, or
     * has moved. That is what makes suspension take effect immediately instead
     * of at the end of a TTL.
     *
     * @param  array{uuids: list<string>, candidates: int, evaluated: int}  $cached
     */
    private function rebuildFromCache(TripRoute $route, array $cached, CarbonImmutable $now): ?DiscoveryResult
    {
        if ($cached['uuids'] === []) {
            return new DiscoveryResult(
                route: $route,
                restaurants: [],
                candidateCount: $cached['candidates'],
                withinCorridorCount: 0,
                detourEvaluatedCount: $cached['evaluated'],
                durationMs: 0,
                fromCache: true,
            );
        }

        $restaurants = Restaurant::query()
            ->discoverable()
            ->whereIn('uuid', $cached['uuids'])
            ->with(['cuisines', 'facilities', 'openingHours'])
            ->get()
            ->keyBy('uuid');

        if ($restaurants->count() !== count($cached['uuids'])) {
            // Something in the cached set is no longer discoverable. Recompute
            // rather than serve a shorter list: the missing one may have been
            // holding a place another restaurant should now occupy.
            Cache::forget($this->cacheKey($route));

            return null;
        }

        try {
            $geometry = RouteGeometry::fromEncoded(
                $route->encoded_polyline,
                (float) config('foodonthego.discovery.geometry_simplify_tolerance_metres'),
            );
        } catch (PolylineException) {
            return null;
        }

        $estimates = $this->detours->estimateFor($route, $restaurants->values()->all());

        $discovered = [];

        foreach ($cached['uuids'] as $uuid) {
            /** @var Restaurant $restaurant */
            $restaurant = $restaurants[$uuid];

            $projection = $geometry->project(new Coordinate(
                (float) $restaurant->latitude,
                (float) $restaurant->longitude,
            ));

            $detour = $estimates[$uuid] ?? null;
            $availability = $this->availability->availabilityOf($restaurant, $now);

            $backtracking = $projection->isAtRouteStart()
                && $projection->proximityMetres > self::BACKTRACK_TOLERANCE_METRES;

            $discovered[] = new DiscoveredRestaurant(
                restaurant: $restaurant,
                projection: $projection,
                availability: $availability,
                detour: $detour,
                timeAheadSeconds: $this->timeAhead($route, $projection->progressFraction()),
                relevanceScore: $this->ranking->score(
                    $availability,
                    $detour,
                    $projection->proximityMetres,
                    $restaurant->rating_average,
                    $backtracking,
                ),
                requiresBacktracking: $backtracking,
            );
        }

        $this->orderForReading($discovered);

        Log::info('discovery.completed', [
            'trip_uuid' => $route->trip->uuid,
            'route_uuid' => $route->uuid,
            'candidates' => $cached['candidates'],
            'detour_evaluated' => $cached['evaluated'],
            'returned' => count($discovered),
            'cache' => 'hit',
        ]);

        return new DiscoveryResult(
            route: $route,
            restaurants: $discovered,
            candidateCount: $cached['candidates'],
            withinCorridorCount: count($discovered),
            detourEvaluatedCount: $cached['evaluated'],
            durationMs: 0,
            fromCache: true,
        );
    }

    /**
     * How far off the road still counts as "on the way" when deciding whether a
     * restaurant behind the origin is really behind it.
     *
     * A restaurant beside the start of the route projects to distance zero
     * legitimately — it is at the start. One that projects to zero from
     * kilometres away has nowhere earlier to go, which is the signature of
     * sitting behind the origin.
     */
    private const BACKTRACK_TOLERANCE_METRES = 500.0;

    /**
     * The order a traveller reads the list in.
     *
     * Journey order — 22 km, 61 km, 105 km — because the list is a sequence of
     * chances to stop, and any other order asks the reader to re-sort it in
     * their head.
     *
     * With one exception, and it is the reason this is a method rather than a
     * comparator written inline. A restaurant behind the origin projects to zero
     * metres along the route, so in pure journey order it sorts **first** — the
     * app would open with "turn round and drive back" presented as the traveller's
     * next stop. Backtracking stops go last: still offered, because the customer
     * may be standing beside one, never offered first.
     *
     * @param  list<DiscoveredRestaurant>  $discovered
     */
    private function orderForReading(array &$discovered): void
    {
        usort(
            $discovered,
            static fn (DiscoveredRestaurant $a, DiscoveredRestaurant $b): int => [$a->requiresBacktracking, $a->projection->alongRouteMetres]
                <=> [$b->requiresBacktracking, $b->projection->alongRouteMetres],
        );
    }

    /**
     * Travel time from the origin to a point along the route.
     *
     * Scaled from the route's own duration by how far along the point is. It is
     * an interpolation of a real figure, not a speed model, and it is presented
     * as "about an hour ahead" rather than as a time of arrival — the honest
     * precision for a number derived this way.
     *
     * The traffic-aware duration is preferred where the provider gave one, so
     * this figure and the route screen's own travel time come from the same
     * source.
     */
    private function timeAhead(TripRoute $route, float $fraction): ?int
    {
        $duration = $route->traffic_duration_seconds ?? $route->duration_seconds;

        if ($duration <= 0) {
            return null;
        }

        return (int) round($duration * $fraction);
    }

    /**
     * Keyed by the route, so a different or recalculated route never reuses a
     * result, and by the discovery configuration, so changing a threshold
     * invalidates every cached answer rather than leaving a mixture of old and
     * new rules in flight.
     */
    private function cacheKey(TripRoute $route): string
    {
        $settings = md5(serialize(config('foodonthego.discovery')));

        return "discovery:result:{$route->uuid}:{$settings}";
    }
}
