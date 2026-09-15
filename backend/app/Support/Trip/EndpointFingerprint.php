<?php

declare(strict_types=1);

namespace App\Support\Trip;

use App\Models\Trip;

/**
 * A deterministic fingerprint of a trip's two endpoints.
 *
 * The mechanism that stops a route calculated for one journey being shown for
 * another. Each route row stores the fingerprint it was calculated under; the
 * trip's own is computed from its columns whenever it is asked for. When they
 * differ, the route is stale — and a stale route is worse than none, because it
 * is real geometry for the wrong journey and looks entirely convincing.
 *
 * Derived rather than stored on the trip on purpose. A stored copy is a second
 * thing to update whenever an endpoint changes, and the day somebody forgets,
 * the route silently stops being invalidated.
 */
final class EndpointFingerprint
{
    /**
     * Seven decimal places — about a centimetre, and the precision the columns
     * hold. Rounding coarser would let a real endpoint change slip through as
     * "the same place"; finer would make the fingerprint depend on float
     * formatting.
     */
    private const PRECISION = 7;

    public static function of(Trip $trip): string
    {
        return self::fromParts(
            (string) $trip->origin_latitude,
            (string) $trip->origin_longitude,
            $trip->origin_place_id,
            (string) $trip->destination_latitude,
            (string) $trip->destination_longitude,
            $trip->destination_place_id,
        );
    }

    public static function fromParts(
        string $originLatitude,
        string $originLongitude,
        ?string $originPlaceId,
        string $destinationLatitude,
        string $destinationLongitude,
        ?string $destinationPlaceId,
    ): string {
        $canonical = implode('|', [
            self::coordinate($originLatitude),
            self::coordinate($originLongitude),
            // The place id is part of the identity because two different places
            // can share a coordinate to seven decimals — a terminal and the road
            // outside it — and a route to one is not a route to the other.
            $originPlaceId ?? '',
            self::coordinate($destinationLatitude),
            self::coordinate($destinationLongitude),
            $destinationPlaceId ?? '',
        ]);

        return hash('sha256', $canonical);
    }

    private static function coordinate(string $value): string
    {
        return number_format((float) $value, self::PRECISION, '.', '');
    }
}
