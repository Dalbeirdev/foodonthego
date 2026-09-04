<?php

declare(strict_types=1);

namespace App\Services\Routing;

use Carbon\CarbonImmutable;

/**
 * What a provider is asked for.
 *
 * A value object rather than a `Trip`, so the provider layer never sees a
 * customer, a trip id or anything else it has no business knowing. It asks for a
 * route between two points; that is all a routing provider is for.
 */
final readonly class RouteRequest
{
    public function __construct(
        public float $originLatitude,
        public float $originLongitude,
        public float $destinationLatitude,
        public float $destinationLongitude,

        /** DRIVE. Configurable, but not customer-facing: this product is road travel. */
        public string $travelMode = 'DRIVE',

        /**
         * Whether to ask for alternatives at all.
         *
         * Off by default at the type level, because alternatives cost more per
         * call and the product decides — not the adapter.
         */
        public bool $withAlternatives = false,

        /**
         * Whether to ask for a traffic-aware duration.
         *
         * Separate from [departureTime] because the two mean different things to
         * a provider: this chooses the routing preference, that anchors it.
         */
        public bool $trafficAware = true,

        /** When the journey starts. Now, for a route being planned now. */
        public ?CarbonImmutable $departureTime = null,

        /**
         * Points the route must pass through, in order.
         *
         * Added by Module 07, which asks a question Module 06 never needed: not
         * "how do I get there" but "how much longer does it take if I stop
         * here". That is the same route with one intermediate point, so it is a
         * property of the request rather than a second provider method — one
         * adapter to keep correct instead of two.
         *
         * Empty for every Module 06 call, which is why it is last and defaulted.
         *
         * @var list<array{0: float, 1: float}> latitude, longitude pairs
         */
        public array $waypoints = [],
    ) {}

    /** Whether this asks for a route through somewhere, not merely between two points. */
    public function hasWaypoints(): bool
    {
        return $this->waypoints !== [];
    }
}
