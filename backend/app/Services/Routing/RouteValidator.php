<?php

declare(strict_types=1);

namespace App\Services\Routing;

use App\Support\Route\PolylineCodec;
use App\Support\Route\PolylineException;

/**
 * Checks what a provider sent before any of it is stored.
 *
 * A provider is a third party over a network. It can be wrong, it can change its
 * contract without telling anybody, and between here and there sits a proxy that
 * could truncate a response. "It came from Google" is not a validation strategy.
 *
 * Every rule here exists because the alternative is a specific visible failure:
 * a zero distance renders as "0 km", a zero duration as "0 min", a truncated
 * polyline draws a line that stops in a field, and a route for the wrong request
 * draws a perfectly convincing journey between two places the customer never
 * chose.
 */
final class RouteValidator
{
    public function __construct(
        private readonly int $maxPolylineBytes,
        private readonly int $endpointToleranceMetres,
    ) {}

    /**
     * @return list<RouteOption> the options that survived
     */
    public function usableOptions(RouteResult $result, RouteRequest $request): array
    {
        $usable = [];

        foreach ($result->options as $option) {
            if ($this->isUsable($option, $request)) {
                $usable[] = $option;
            }
        }

        return $usable;
    }

    public function isUsable(RouteOption $option, RouteRequest $request): bool
    {
        // A route of zero length between two different places is not a route,
        // and a route of zero duration is not one either. Both render as a
        // confident "0" on a screen.
        if ($option->distanceMeters <= 0 || $option->durationSeconds <= 0) {
            return false;
        }

        // A traffic-aware duration of zero is the same failure wearing a
        // different hat.
        if ($option->trafficDurationSeconds !== null && $option->trafficDurationSeconds <= 0) {
            return false;
        }

        // Bounded before decoding. The decoder allocates as it reads, so the
        // size check has to come first to be worth anything.
        if (strlen($option->encodedPolyline) > $this->maxPolylineBytes) {
            return false;
        }

        try {
            $points = PolylineCodec::decode($option->encodedPolyline);
        } catch (PolylineException) {
            return false;
        }

        // A polyline of one point is not a line. Two is allowed — a genuinely
        // short route can be that — and what stops a straight line across the
        // countryside getting through is the endpoint check below plus the fact
        // that no production provider returns one.
        if (count($points) < 2) {
            return false;
        }

        foreach ($points as [$latitude, $longitude]) {
            if ($latitude < -90 || $latitude > 90 || $longitude < -180 || $longitude > 180) {
                return false;
            }
        }

        if (! $option->bounds->isSane()) {
            return false;
        }

        return $this->answersTheQuestionAsked($points, $request);
    }

    /**
     * Whether this geometry is a route between the two places we asked about.
     *
     * The check that catches a mismatched, cached or crossed-over response —
     * the failure mode where everything is internally consistent and describes
     * somebody else's journey. Providers snap to the nearest road, so the
     * tolerance is generous: metres in a city, a kilometre or two in open
     * country. It is there to catch a route that starts in a different *region*,
     * not to second-guess a road network.
     *
     * @param  list<array{0: float, 1: float}>  $points
     */
    private function answersTheQuestionAsked(array $points, RouteRequest $request): bool
    {
        $first = $points[0];
        $last = $points[count($points) - 1];

        return self::metresBetween(
            $first[0], $first[1],
            $request->originLatitude, $request->originLongitude,
        ) <= $this->endpointToleranceMetres
            && self::metresBetween(
                $last[0], $last[1],
                $request->destinationLatitude, $request->destinationLongitude,
            ) <= $this->endpointToleranceMetres;
    }

    public static function metresBetween(float $lat1, float $lon1, float $lat2, float $lon2): float
    {
        $earthRadius = 6_371_000.0;

        $phi1 = deg2rad($lat1);
        $phi2 = deg2rad($lat2);
        $deltaPhi = $phi2 - $phi1;
        $deltaLambda = deg2rad($lon2 - $lon1);

        $a = sin($deltaPhi / 2) ** 2 + cos($phi1) * cos($phi2) * sin($deltaLambda / 2) ** 2;

        return $earthRadius * 2 * atan2(sqrt($a), sqrt(1 - $a));
    }
}
