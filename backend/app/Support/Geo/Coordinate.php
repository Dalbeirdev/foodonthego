<?php

declare(strict_types=1);

namespace App\Support\Geo;

/** A position. Immutable, and compared by value rather than by identity. */
final readonly class Coordinate
{
    public function __construct(
        public float $latitude,
        public float $longitude,
    ) {}

    public static function fromPair(array $pair): self
    {
        return new self((float) $pair[0], (float) $pair[1]);
    }
}
