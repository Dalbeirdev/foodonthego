<?php

declare(strict_types=1);

namespace App\Services\Discovery;

use App\Enums\RestaurantAvailability;
use App\Models\Restaurant;
use App\Support\Geo\RouteProjection;

/**
 * A restaurant, and everything this route says about it.
 *
 * The route figures are kept beside the restaurant rather than written onto it,
 * because they are not properties of the restaurant at all: the same restaurant
 * is 68 km ahead on one journey and behind the driver on another. Nothing here
 * is persisted.
 */
final readonly class DiscoveredRestaurant
{
    public function __construct(
        public Restaurant $restaurant,
        public RouteProjection $projection,
        public RestaurantAvailability $availability,
        public ?DetourEstimate $detour,
        /** Travel time from the route origin to the projection, seconds. Null when it cannot be derived. */
        public ?int $timeAheadSeconds,
        public float $relevanceScore,
        /** True when reaching this restaurant would mean driving back the way you came. */
        public bool $requiresBacktracking,
    ) {}

    /**
     * The customer-safe shape.
     *
     * The `route` block is deliberately a block: the four numbers in it are all
     * about this journey and would be meaningless flattened onto the restaurant.
     *
     * Every field can be null, and null means "not established" — never zero. A
     * detour of null is an absent badge on the card; a detour of 0 is a claim
     * that stopping is free.
     *
     * @return array<string, mixed>
     */
    public function toApiArray(): array
    {
        return [
            ...$this->restaurant->toDiscoveryArray(),
            'availability' => $this->availability->value,
            'is_accepting_orders' => $this->restaurant->is_accepting_orders,
            'route' => [
                // How far off the road it sits. A filter and a secondary
                // signal — never presented as a detour.
                'proximity_meters' => (int) round($this->projection->proximityMetres),

                // What stopping costs. Null when no provider could say.
                'detour_distance_meters' => $this->detour?->extraDistanceMetres,
                'detour_duration_seconds' => $this->detour?->extraDurationSeconds,
                'detour_provider' => $this->detour?->provider,

                // How far into the journey it is.
                'distance_ahead_meters' => (int) round($this->projection->alongRouteMetres),
                'time_ahead_seconds' => $this->timeAheadSeconds,

                // Ordering arithmetic, exposed because the client sorts the list
                // it already holds when the customer switches between map and
                // list. Not rendered as a number anywhere.
                'progress_fraction' => round($this->projection->progressFraction(), 4),
                'requires_backtracking' => $this->requiresBacktracking,
            ],
        ];
    }
}
