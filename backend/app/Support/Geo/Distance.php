<?php

declare(strict_types=1);

namespace App\Support\Geo;

/**
 * Distances on the Earth, to the accuracy this module actually needs.
 *
 * Two functions, and the difference between them matters.
 *
 * {@see haversineMetres()} is the real great-circle distance and is used
 * wherever a number is reported to a customer or compared against a configured
 * threshold.
 *
 * {@see equirectangularMetres()} projects a small patch of the Earth flat before
 * measuring. Over the few kilometres a corridor spans its error is under a tenth
 * of a percent, and it costs one trigonometric call instead of seven — which is
 * the difference between a discovery request that runs in milliseconds and one
 * that does not, because the inner loop runs candidates times segments times.
 * It is used only inside the projection search, never to produce a reported
 * figure.
 */
final class Distance
{
    /** Mean Earth radius, metres. The value WGS-84 rounds to. */
    public const EARTH_RADIUS_METRES = 6_371_008.8;

    public static function haversineMetres(Coordinate $a, Coordinate $b): float
    {
        $latA = deg2rad($a->latitude);
        $latB = deg2rad($b->latitude);
        $dLat = $latB - $latA;
        $dLon = deg2rad($b->longitude - $a->longitude);

        $h = sin($dLat / 2) ** 2 + cos($latA) * cos($latB) * sin($dLon / 2) ** 2;

        return 2 * self::EARTH_RADIUS_METRES * asin(min(1.0, sqrt($h)));
    }

    /**
     * Flat-Earth distance, good for short spans.
     *
     * The longitude difference is scaled by the cosine of the latitude, which is
     * what stops a degree of longitude being treated as the same width in Delhi
     * as at the equator — the mistake that makes naive "distance" code place
     * things hundreds of kilometres out.
     */
    public static function equirectangularMetres(Coordinate $a, Coordinate $b): float
    {
        $meanLat = deg2rad(($a->latitude + $b->latitude) / 2);

        $x = deg2rad($b->longitude - $a->longitude) * cos($meanLat);
        $y = deg2rad($b->latitude - $a->latitude);

        return sqrt($x * $x + $y * $y) * self::EARTH_RADIUS_METRES;
    }

    /**
     * How many degrees of latitude and longitude a distance spans here.
     *
     * Used to grow a bounding box by a corridor width. Longitude degrees narrow
     * towards the poles, so the two are different numbers and returning one
     * would make a box that is right in one axis and wrong in the other.
     *
     * @return array{0: float, 1: float} degrees of latitude, degrees of longitude
     */
    public static function degreesFor(float $metres, float $atLatitude): array
    {
        $latDegrees = rad2deg($metres / self::EARTH_RADIUS_METRES);

        // Guard the poles: cos(90 degrees) is zero, and a corridor there would
        // otherwise ask for an infinite span of longitude.
        $cos = max(0.01, cos(deg2rad($atLatitude)));

        return [$latDegrees, $latDegrees / $cos];
    }
}
