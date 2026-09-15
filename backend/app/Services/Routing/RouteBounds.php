<?php

declare(strict_types=1);

namespace App\Services\Routing;

/**
 * The box a route fits inside.
 *
 * Stored alongside the geometry so two things are cheap: framing a camera
 * without decoding a polyline, and — the reason it earns a column — letting
 * Module 07 reject restaurants that are nowhere near the corridor before it
 * decodes anything at all.
 */
final readonly class RouteBounds
{
    public function __construct(
        public float $north,
        public float $south,
        public float $east,
        public float $west,
    ) {}

    /**
     * Derives the box from decoded points.
     *
     * @param  list<array{0: float, 1: float}>  $points
     */
    public static function around(array $points): self
    {
        $latitudes = array_column($points, 0);
        $longitudes = array_column($points, 1);

        return new self(
            north: max($latitudes),
            south: min($latitudes),
            east: max($longitudes),
            west: min($longitudes),
        );
    }

    public function isSane(): bool
    {
        return $this->north >= $this->south
            && $this->north <= 90 && $this->south >= -90
            && $this->east <= 180 && $this->west >= -180;
    }
}
