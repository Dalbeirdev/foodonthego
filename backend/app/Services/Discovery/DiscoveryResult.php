<?php

declare(strict_types=1);

namespace App\Services\Discovery;

use App\Enums\RestaurantAvailability;
use App\Models\TripRoute;

/**
 * What a discovery search found, and what it cost to find it.
 *
 * The counts are here rather than only in a log line because the API returns
 * them: a client that can see "300 candidates became 4 results" can say
 * something useful about an empty screen, and the performance evidence this
 * module owes is a measurement rather than an assertion.
 */
final readonly class DiscoveryResult
{
    /** @param list<DiscoveredRestaurant> $restaurants */
    public function __construct(
        public TripRoute $route,
        public array $restaurants,
        /** Rows the bounding-box query returned. */
        public int $candidateCount,
        /** Of those, how many were actually within the corridor. */
        public int $withinCorridorCount,
        /** Of those, how many a routing provider was asked about. */
        public int $detourEvaluatedCount,
        public int $durationMs,
        public bool $fromCache,
    ) {}

    public function isEmpty(): bool
    {
        return $this->restaurants === [];
    }

    /**
     * Whether there are restaurants but none a customer could order from.
     *
     * Its own state on purpose. "There is nothing on this route" and "there are
     * four places and all of them are shut" call for different words and
     * different buttons, and reporting the second as the first tells a customer
     * to change a route that is perfectly good.
     */
    public function isClosedOnly(): bool
    {
        if ($this->restaurants === []) {
            return false;
        }

        foreach ($this->restaurants as $restaurant) {
            if ($restaurant->availability->isActionable()) {
                return false;
            }
        }

        return true;
    }

    /** @return array<string, mixed> */
    public function toApiArray(): array
    {
        return [
            'route' => [
                'route_id' => $this->route->uuid,
                'distance_meters' => $this->route->distance_meters,
                'duration_seconds' => $this->route->traffic_duration_seconds
                    ?? $this->route->duration_seconds,
                // Carried so the client can label a synthetic result exactly as
                // the route screen does, rather than presenting a development
                // detour as a real one.
                'provider' => $this->route->provider,
            ],
            'restaurants' => array_map(
                static fn (DiscoveredRestaurant $d): array => $d->toApiArray(),
                $this->restaurants,
            ),
            'meta' => [
                'returned' => count($this->restaurants),
                'candidates_considered' => $this->candidateCount,
                'within_corridor' => $this->withinCorridorCount,
                'detour_evaluated' => $this->detourEvaluatedCount,
                'closed_only' => $this->isClosedOnly(),
                'from_cache' => $this->fromCache,
                'corridor_meters' => (int) config('foodonthego.discovery.corridor_metres'),
                'max_detour_duration_seconds' => (int) config(
                    'foodonthego.discovery.max_detour_duration_seconds',
                ),
            ],
        ];
    }

    /** @return list<RestaurantAvailability> */
    public function availabilities(): array
    {
        return array_map(
            static fn (DiscoveredRestaurant $d): RestaurantAvailability => $d->availability,
            $this->restaurants,
        );
    }
}
