<?php

declare(strict_types=1);

namespace App\Services\Routing;

/**
 * One route, in this application's own shape.
 *
 * Deliberately not a provider's JSON. Business logic that reads
 * `routes[0].legs[0].duration` is business logic coupled to Google, and the
 * abstraction the module is built on would be decorative.
 *
 * Units are the point of this class: **metres and seconds**, always, as
 * integers. A formatted string cannot be summed, compared, or shown in miles to
 * somebody who wants miles, and a float second is a rounding argument nobody
 * needs.
 */
final readonly class RouteOption
{
    public function __construct(
        /** The provider's own ordering; 0 is the one it recommends. */
        public int $index,

        public int $distanceMeters,

        /**
         * The journey without traffic.
         *
         * Google's Routes API calls this `staticDuration`, and it is the one that
         * stays put: `duration` moves with the traffic model. Mapping them the
         * other way round would make every route look congested by exactly zero.
         */
        public int $durationSeconds,

        /**
         * The journey in current traffic, or null when the provider was not asked
         * for one or did not give one.
         *
         * Null rather than a copy of [durationSeconds]. Copying it would claim a
         * traffic reading of precisely zero delay, which is a claim about the
         * roads rather than an absence of one.
         */
        public ?int $trafficDurationSeconds,

        public string $encodedPolyline,

        public RouteBounds $bounds,

        /** "via NH 48" — the provider's words, or nothing. */
        public ?string $summary = null,
    ) {}

    /**
     * How much longer traffic is making this, in seconds.
     *
     * Null when there is no traffic-aware figure, and **never negative**: a
     * provider that returns a traffic-aware duration shorter than its own static
     * one is not reporting a time saving, it is reporting two figures computed
     * under different assumptions. Presenting that as "12 minutes quicker
     * because of traffic" would be nonsense.
     */
    public function trafficDelaySeconds(): ?int
    {
        if ($this->trafficDurationSeconds === null) {
            return null;
        }

        $delay = $this->trafficDurationSeconds - $this->durationSeconds;

        return $delay > 0 ? $delay : null;
    }
}
