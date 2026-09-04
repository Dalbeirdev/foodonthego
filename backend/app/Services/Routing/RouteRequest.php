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
    ) {}
}
