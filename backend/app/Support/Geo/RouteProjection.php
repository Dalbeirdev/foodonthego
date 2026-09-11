<?php

declare(strict_types=1);

namespace App\Support\Geo;

/**
 * Where a point sits relative to a route.
 *
 * The two numbers answer different questions and are never interchangeable.
 *
 * {@see proximityMetres} is how far the restaurant is from the road as the crow
 * flies. It is a filter, and it is shown as "1.8 km off your route" — it is
 * **not** a detour, because a restaurant 300 m from a motorway with no junction
 * for 20 km is 300 m away and forty minutes' driving.
 *
 * {@see alongRouteMetres} is how far into the journey the closest approach
 * happens, which is what "68 km ahead" is measured from.
 */
final readonly class RouteProjection
{
    public function __construct(
        public Coordinate $point,
        public int $segmentIndex,
        public float $proximityMetres,
        public float $alongRouteMetres,
        public float $routeTotalMetres,
    ) {}

    /**
     * 0.0 at the origin, 1.0 at the destination.
     *
     * Internal ordering arithmetic, and deliberately not customer-facing: "your
     * stop is at 0.42 of your journey" is a number nobody has ever wanted.
     */
    public function progressFraction(): float
    {
        if ($this->routeTotalMetres <= 0.0) {
            return 0.0;
        }

        return max(0.0, min(1.0, $this->alongRouteMetres / $this->routeTotalMetres));
    }

    /**
     * Whether this projection sits at the very start of the route.
     *
     * A restaurant behind the origin has nowhere earlier to project to, so it
     * lands on the first point and reports zero distance along. That is the
     * signature of "reaching this means turning round", and it is how
     * backtracking is detected without a live position to compare against.
     */
    public function isAtRouteStart(float $toleranceMetres = 1.0): bool
    {
        return $this->alongRouteMetres <= $toleranceMetres;
    }
}
