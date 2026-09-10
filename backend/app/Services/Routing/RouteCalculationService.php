<?php

declare(strict_types=1);

namespace App\Services\Routing;

use App\Enums\ApiErrorCode;
use App\Enums\RouteStatus;
use App\Enums\TripStatus;
use App\Exceptions\ApiException;
use App\Models\Trip;
use App\Models\TripRoute;
use App\Support\Trip\EndpointFingerprint;
use Carbon\CarbonImmutable;
use Illuminate\Contracts\Cache\LockProvider;
use Illuminate\Contracts\Cache\Repository as Cache;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

/**
 * Turning a trip into routes.
 *
 * The one place that talks to a routing provider, and the one place that decides
 * a trip's `route_status`. Four things it is careful about, in the order they
 * bite:
 *
 * **Not calling the provider.** Every call is billed. A trip whose route is
 * already calculated, still fresh and still for these endpoints is served from
 * the database. Opening the route screen twice must cost once.
 *
 * **Not calling it twice at the same time.** Two taps, or two devices, take a
 * row lock on the trip; the second finds the first's result and returns it.
 *
 * **Not half-storing.** Options, the default selection and the trip's status
 * commit together or not at all.
 *
 * **Not storing something wrong.** {@see RouteValidator} runs on everything the
 * provider sent, and a result with nothing usable left is a failure rather than
 * an empty success.
 */
final class RouteCalculationService
{
    /**
     * The cache is required to be a lock provider, and now says so.
     *
     * `lock()` is the only thing this service asks of it, and `lock()` lives on
     * LockProvider rather than on the Repository contract -- so the native type
     * alone described a dependency that could not do the one job it is here
     * for. The intersection is documented rather than declared because the
     * container autowires the native type; a store without locking would fail
     * at the call either way, and this at least makes the requirement legible
     * before that happens.
     *
     * @param  Cache&LockProvider  $cache
     */
    public function __construct(
        private readonly RouteProvider $provider,
        private readonly RouteValidator $validator,
        private readonly Cache $cache,
    ) {}

    /**
     * Calculates, or returns what is already known.
     *
     * @param  bool  $force  Skips the freshness check. For an explicit "refresh",
     *                       never for an ordinary screen open.
     * @return Collection<int, TripRoute>
     *
     * @throws ApiException
     */
    public function calculate(Trip $trip, CarbonImmutable $now, bool $force = false): Collection
    {
        $this->assertRoutable($trip);

        if (! $force) {
            $existing = $this->freshRoutes($trip, $now);

            if ($existing !== null) {
                // The cost control. No provider call, no write, no log noise.
                return $existing;
            }
        }

        return $this->withoutConcurrentCalculation($trip, function () use ($trip, $now, $force): Collection {
            // Re-checked inside the lock: while this request waited, another may
            // have done the work. Without this, two simultaneous taps are two
            // billed calls.
            if (! $force) {
                $existing = $this->freshRoutes($trip, $now);

                if ($existing !== null) {
                    return $existing;
                }
            }

            return $this->callProviderAndStore($trip, $now);
        });
    }

    /**
     * The routes currently stored for this trip, whatever their state.
     *
     * @return Collection<int, TripRoute>
     */
    public function routesFor(Trip $trip): Collection
    {
        return TripRoute::query()->forTrip($trip)->inProviderOrder()->get();
    }

    /**
     * The selected route, if there is a usable one.
     *
     * Returns null for a trip whose stored routes no longer match its endpoints,
     * because a stale route is not a route — it is a convincing picture of a
     * journey nobody is taking.
     */
    public function selectedRouteFor(Trip $trip): ?TripRoute
    {
        if (! $trip->route_status->hasUsableRoute()) {
            return null;
        }

        $selected = TripRoute::query()->forTrip($trip)->where('is_selected', true)->first();

        return $selected?->matchesEndpointsOf($trip) === true ? $selected : null;
    }

    /**
     * Marks a trip's routes stale when its endpoints have moved.
     *
     * Called on read rather than only on write, so a route cannot survive an
     * endpoint change made by any path — a future edit endpoint, a repair
     * script, a migration. The invalidation belongs to the thing that notices,
     * not to the thing that changed.
     */
    public function invalidateIfEndpointsChanged(Trip $trip): bool
    {
        if ($trip->route_status === RouteStatus::NotCalculated) {
            return false;
        }

        $fingerprint = EndpointFingerprint::of($trip);

        $mismatched = TripRoute::query()
            ->forTrip($trip)
            ->where('endpoints_fingerprint', '!=', $fingerprint)
            ->exists();

        if (! $mismatched) {
            return false;
        }

        DB::transaction(function () use ($trip): void {
            // Deleted, not archived. Keeping geometry for endpoints nobody is
            // travelling between is storage with a liability attached: it is
            // location data about a customer, for a journey that no longer
            // exists.
            TripRoute::query()->forTrip($trip)->delete();

            $trip->forceFill(['route_status' => RouteStatus::NotCalculated])->save();
        });

        Log::info('route.invalidated', [
            'trip_uuid' => $trip->uuid,
            'reason' => 'endpoints_changed',
        ]);

        return true;
    }

    /**
     * Trip-level eligibility, before a provider is troubled.
     *
     * @throws ApiException
     */
    private function assertRoutable(Trip $trip): void
    {
        if ($trip->status === TripStatus::Cancelled) {
            throw new ApiException(
                ApiErrorCode::TripNotEditable,
                'That journey has been discarded, so there is nothing to route.',
            );
        }

        $origin = [(float) $trip->origin_latitude, (float) $trip->origin_longitude];
        $destination = [(float) $trip->destination_latitude, (float) $trip->destination_longitude];

        foreach ([$origin, $destination] as [$latitude, $longitude]) {
            if ($latitude < -90 || $latitude > 90 || $longitude < -180 || $longitude > 180) {
                throw new ApiException(
                    ApiErrorCode::RouteInputInvalid,
                    'That journey has an endpoint we cannot route from.',
                );
            }

            // Module 05 refuses to store this. Checked again because this
            // service is the last thing standing between a bad coordinate and a
            // billed provider call.
            if ($latitude === 0.0 && $longitude === 0.0) {
                throw new ApiException(
                    ApiErrorCode::RouteInputInvalid,
                    'That journey has an endpoint we cannot route from.',
                );
            }
        }

        // Module 05's rule, enforced again here: a caller reaching this service
        // some other way must not be able to spend a provider call asking for a
        // route from a place to itself.
        $metres = RouteValidator::metresBetween(
            $origin[0], $origin[1], $destination[0], $destination[1],
        );

        if ($metres <= (float) config('foodonthego.trips.same_location_threshold_metres')) {
            throw new ApiException(
                ApiErrorCode::SameLocation,
                'That journey starts and ends in the same place.',
            );
        }
    }

    /**
     * The stored routes, if they are still worth serving.
     *
     * @return Collection<int, TripRoute>|null
     */
    private function freshRoutes(Trip $trip, CarbonImmutable $now): ?Collection
    {
        if ($trip->route_status !== RouteStatus::Ready) {
            return null;
        }

        $routes = $this->routesFor($trip);

        if ($routes->isEmpty()) {
            return null;
        }

        $fingerprint = EndpointFingerprint::of($trip);
        $freshness = (int) config('foodonthego.routing.freshness_seconds');

        foreach ($routes as $route) {
            // Any row for different endpoints makes the whole set stale: they
            // were calculated together and they are replaced together.
            if (! hash_equals($route->endpoints_fingerprint, $fingerprint)) {
                return null;
            }

            if ($route->calculated_at === null
                || $route->calculated_at->addSeconds($freshness)->isBefore($now)
            ) {
                return null;
            }
        }

        return $routes;
    }

    /**
     * Serialises calculations for one trip.
     *
     * A cache lock rather than only a row lock, because the provider call
     * happens *outside* the database transaction — holding a MySQL row lock open
     * across a twelve-second HTTP request is how a connection pool dies.
     *
     * @template T
     *
     * @param  callable(): T  $work
     * @return T
     *
     * @throws ApiException
     */
    private function withoutConcurrentCalculation(Trip $trip, callable $work): mixed
    {
        $lock = $this->cache->lock('route:calculate:'.$trip->uuid, 30);

        // Waits briefly rather than refusing outright: the common case is a
        // double tap a few hundred milliseconds apart, and the second one should
        // get the first one's answer rather than an error.
        if (! $lock->block(15)) {
            throw new ApiException(
                ApiErrorCode::RouteCalculationInProgress,
                'We are already working out this route. Give it a moment.',
            );
        }

        try {
            return $work();
        } finally {
            $lock->release();
        }
    }

    /**
     * @return Collection<int, TripRoute>
     *
     * @throws ApiException
     */
    private function callProviderAndStore(Trip $trip, CarbonImmutable $now): Collection
    {
        $request = new RouteRequest(
            originLatitude: (float) $trip->origin_latitude,
            originLongitude: (float) $trip->origin_longitude,
            destinationLatitude: (float) $trip->destination_latitude,
            destinationLongitude: (float) $trip->destination_longitude,
            travelMode: (string) config('foodonthego.routing.travel_mode'),
            withAlternatives: (bool) config('foodonthego.routing.alternatives_enabled'),
            trafficAware: (bool) config('foodonthego.routing.traffic_aware'),
            departureTime: $now,
        );

        $startedAt = microtime(true);

        try {
            $result = $this->provider->calculate($request);
        } catch (RouteProviderException $e) {
            $this->recordFailure($trip, RouteStatus::Failed);

            Log::warning('route.calculation_failed', [
                'trip_uuid' => $trip->uuid,
                'provider' => $this->provider->name(),
                'kind' => $e->kind->value,
                'latency_ms' => (int) round((microtime(true) - $startedAt) * 1000),
            ]);

            throw new ApiException(...$this->contractFor($e->kind));
        }

        $options = $this->validator->usableOptions($result, $request);

        if ($options === []) {
            // Two different things land here, and they are told apart by whether
            // the provider sent anything at all. Nothing sent is "there is no
            // driving route" — an answer. Something sent that did not survive
            // validation is our problem, not the customer's.
            $noRoute = $result->isEmpty();

            $this->recordFailure($trip, $noRoute ? RouteStatus::NoRoute : RouteStatus::Failed);

            Log::warning($noRoute ? 'route.no_route' : 'route.response_rejected', [
                'trip_uuid' => $trip->uuid,
                'provider' => $this->provider->name(),
                'options_returned' => count($result->options),
                'latency_ms' => (int) round((microtime(true) - $startedAt) * 1000),
            ]);

            throw $noRoute
                ? new ApiException(
                    ApiErrorCode::RouteNoRouteFound,
                    'We could not find a driving route between those two places.',
                )
                : new ApiException(
                    ApiErrorCode::RouteResponseInvalid,
                    'We could not read the route we were given. Please try again.',
                );
        }

        $fingerprint = EndpointFingerprint::of($trip);

        $stored = DB::transaction(function () use ($trip, $options, $result, $fingerprint, $now): Collection {
            // The lock that makes the whole write atomic against another
            // request reading this trip's status mid-replacement.
            $locked = Trip::query()->whereKey($trip->getKey())->lockForUpdate()->firstOrFail();

            // Replaced wholesale rather than merged. The alternatives a provider
            // returns are one answer to one question; keeping last time's third
            // option alongside this time's two would be a set that never existed.
            TripRoute::query()->forTrip($locked)->delete();

            foreach ($options as $option) {
                $route = new TripRoute;

                $route->forceFill([
                    'trip_id' => $locked->getKey(),
                    'provider' => $result->provider,
                    'provider_route_index' => $option->index,
                    'summary' => $option->summary,
                    'distance_meters' => $option->distanceMeters,
                    'duration_seconds' => $option->durationSeconds,
                    'traffic_duration_seconds' => $option->trafficDurationSeconds,
                    'encoded_polyline' => $option->encodedPolyline,
                    'bounds_north' => $option->bounds->north,
                    'bounds_south' => $option->bounds->south,
                    'bounds_east' => $option->bounds->east,
                    'bounds_west' => $option->bounds->west,
                    // The provider's own first choice.
                    'is_recommended' => $option->index === 0,
                    // Selected by default, so a customer who never opens the
                    // alternatives still has a route. The rule is documented in
                    // docs/21-maps-and-routing.md.
                    'is_selected' => $option->index === 0,
                    'endpoints_fingerprint' => $fingerprint,
                    'calculated_at' => $now,
                ])->save();
            }

            $locked->forceFill(['route_status' => RouteStatus::Ready])->save();

            // Refreshed from the caller's own instance so the object the
            // controller holds reflects what was just committed.
            $trip->setRawAttributes($locked->getAttributes(), true);

            return TripRoute::query()->forTrip($locked)->inProviderOrder()->get();
        });

        Log::info('route.calculated', [
            'trip_uuid' => $trip->uuid,
            'provider' => $result->provider,
            'route_count' => $stored->count(),
            // Whether traffic information came back at all, not what it said.
            'has_traffic' => $stored->contains(fn (TripRoute $r): bool => $r->traffic_duration_seconds !== null),
            'latency_ms' => (int) round((microtime(true) - $startedAt) * 1000),
        ]);

        return $stored;
    }

    /**
     * Records a failed attempt without destroying what is already there.
     *
     * A trip that had a working route yesterday keeps it when today's refresh
     * fails: the geometry is still valid for these endpoints, and replacing a
     * usable route with an error state punishes the customer for our outage.
     */
    private function recordFailure(Trip $trip, RouteStatus $status): void
    {
        $hasUsableRoutes = $trip->route_status === RouteStatus::Ready
            && TripRoute::query()->forTrip($trip)->exists();

        if ($hasUsableRoutes && $status === RouteStatus::Failed) {
            return;
        }

        DB::transaction(function () use ($trip, $status): void {
            if ($status === RouteStatus::NoRoute) {
                // There is no route. Anything stored describes a journey the
                // provider has just said cannot be driven.
                TripRoute::query()->forTrip($trip)->delete();
            }

            $trip->forceFill(['route_status' => $status])->save();
        });
    }

    /**
     * How a provider failure reaches a client.
     *
     * @return array{0: ApiErrorCode, 1: string}
     */
    private function contractFor(RouteFailureKind $kind): array
    {
        return match ($kind) {
            RouteFailureKind::Timeout => [
                ApiErrorCode::RouteTimeout,
                'Working out that route took too long. Please try again.',
            ],
            RouteFailureKind::RateLimited => [
                ApiErrorCode::RouteProviderRateLimited,
                'Route planning is busy right now. Please try again in a moment.',
            ],
            RouteFailureKind::InvalidResponse => [
                ApiErrorCode::RouteResponseInvalid,
                'We could not read the route we were given. Please try again.',
            ],
            // A refused key is an operational emergency and a customer-facing
            // outage. They are told the second thing and nothing about the first.
            RouteFailureKind::NotAuthorised,
            RouteFailureKind::Unavailable => [
                ApiErrorCode::RouteProviderUnavailable,
                'We could not work out your route right now. Please try again.',
            ],
        };
    }
}
