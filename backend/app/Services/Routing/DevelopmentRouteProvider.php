<?php

declare(strict_types=1);

namespace App\Services\Routing;

use App\Support\ProductionConfigGuard;
use App\Support\Route\PolylineCodec;

/**
 * A stand-in that exercises the routing pipeline where no provider credentials
 * exist. **It does not produce real routes, and it says so.**
 *
 * ## Read this before using anything it returns
 *
 * This provider cannot know where the roads are. What it returns is a straight
 * line between two real coordinates, with a distance that is the great-circle
 * distance between them and a duration derived from a single assumed speed. Every
 * one of those numbers is **synthetic**. None of them is a routing result, and
 * none may ever be shown to a customer as one.
 *
 * Three things keep that from happening:
 *
 * 1. It throws if constructed outside development, exactly as Module 03's
 *    `LogOtpProvider` and Module 05's `DevelopmentGazetteerProvider` do.
 * 2. {@see ProductionConfigGuard} refuses to boot a production
 *    application configured to use it.
 * 3. Its {@see name()} is stored in `trip_routes.provider` and returned in the
 *    API payload, so a synthetic row is identifiable for ever — in the database,
 *    in a log, and on the screen, where the app renders a development notice
 *    over any route whose provider is not a real one.
 *
 * ## Why it exists at all
 *
 * Without it, every code path this module owns — persistence, the one-selected
 * invariant, endpoint invalidation, selection, staleness, rendering, camera fit,
 * the failure screens — would be unreachable in an environment with no key, and
 * would ship having never run. This makes the plumbing testable. It does not
 * make the routing real, and the module's completion report says so plainly.
 */
final class DevelopmentRouteProvider implements RouteProvider
{
    /**
     * A single assumed average speed, in metres per second (≈ 60 km/h).
     *
     * Deliberately one flat number rather than anything that might look like a
     * model. There is no model. A plausible-looking speed profile would make the
     * output harder to recognise as synthetic, which is the opposite of what this
     * class is for.
     */
    private const ASSUMED_SPEED_MS = 16.7;

    public function __construct(bool $isProduction)
    {
        if ($isProduction) {
            throw new \RuntimeException(
                'DevelopmentRouteProvider must never run in production. Configure a real routing provider.',
            );
        }
    }

    public function name(): string
    {
        return 'development';
    }

    public function calculate(RouteRequest $request): RouteResult
    {
        $distance = (int) round($this->metresBetween(
            $request->originLatitude,
            $request->originLongitude,
            $request->destinationLatitude,
            $request->destinationLongitude,
        ));

        if ($distance <= 0) {
            // Two points in the same place. The real providers answer this with
            // no route, and so does this one.
            return new RouteResult([], $this->name());
        }

        $options = [new RouteOption(
            index: 0,
            distanceMeters: $distance,
            durationSeconds: (int) round($distance / self::ASSUMED_SPEED_MS),
            // No traffic figure. This provider has no idea what the traffic is,
            // and a made-up delay is the single most misleading number this
            // module could produce.
            trafficDurationSeconds: null,
            encodedPolyline: PolylineCodec::encode($this->straightLine($request)),
            bounds: new RouteBounds(
                north: max($request->originLatitude, $request->destinationLatitude),
                south: min($request->originLatitude, $request->destinationLatitude),
                east: max($request->originLongitude, $request->destinationLongitude),
                west: min($request->originLongitude, $request->destinationLongitude),
            ),
            summary: 'Development stand-in — not a real route',
        )];

        // Deliberately never more than one. Fabricating a second "alternative"
        // would invent a choice the customer does not have, and the module's
        // alternative-route test reports NOT APPLICABLE rather than passing
        // against something made up.
        return new RouteResult($options, $this->name());
    }

    /** @return list<array{0: float, 1: float}> */
    private function straightLine(RouteRequest $request): array
    {
        $points = [];
        $steps = 24;

        for ($i = 0; $i <= $steps; $i++) {
            $fraction = $i / $steps;

            $points[] = [
                $request->originLatitude
                    + ($request->destinationLatitude - $request->originLatitude) * $fraction,
                $request->originLongitude
                    + ($request->destinationLongitude - $request->originLongitude) * $fraction,
            ];
        }

        return $points;
    }

    private function metresBetween(float $lat1, float $lon1, float $lat2, float $lon2): float
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
