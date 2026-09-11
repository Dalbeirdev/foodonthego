<?php

declare(strict_types=1);

namespace Tests\Unit;

use App\Services\Routing\RouteBounds;
use App\Services\Routing\RouteOption;
use App\Services\Routing\RouteRequest;
use App\Services\Routing\RouteResult;
use App\Services\Routing\RouteValidator;
use App\Support\Route\PolylineCodec;
use Tests\TestCase;

/**
 * What a provider sent, checked before any of it is stored.
 *
 * Every rule here exists because the alternative is a specific visible failure.
 * A zero distance renders as "0 km". A truncated polyline draws a line that
 * stops in a field. A route for somebody else's request draws a perfectly
 * convincing journey between two places the customer never chose.
 */
final class RouteValidatorTest extends TestCase
{
    private const DELHI = [28.5494, 77.2001];

    private const JAIPUR = [26.8242, 75.8122];

    private RouteValidator $validator;

    protected function setUp(): void
    {
        parent::setUp();

        $this->validator = new RouteValidator(
            maxPolylineBytes: 512_000,
            endpointToleranceMetres: 5_000,
        );
    }

    private function request(): RouteRequest
    {
        return new RouteRequest(
            originLatitude: self::DELHI[0],
            originLongitude: self::DELHI[1],
            destinationLatitude: self::JAIPUR[0],
            destinationLongitude: self::JAIPUR[1],
        );
    }

    /** @param list<array{0: float, 1: float}>|null $points */
    private function option(
        int $distance = 278_000,
        int $duration = 16_200,
        ?int $traffic = 17_100,
        ?array $points = null,
        ?string $encoded = null,
    ): RouteOption {
        $points ??= $this->line(self::DELHI, self::JAIPUR);

        return new RouteOption(
            index: 0,
            distanceMeters: $distance,
            durationSeconds: $duration,
            trafficDurationSeconds: $traffic,
            encodedPolyline: $encoded ?? PolylineCodec::encode($points),
            bounds: RouteBounds::around($points),
            summary: 'NH 48',
        );
    }

    /**
     * @param  array{0: float, 1: float}  $from
     * @param  array{0: float, 1: float}  $to
     * @return list<array{0: float, 1: float}>
     */
    private function line(array $from, array $to, int $steps = 20): array
    {
        $points = [];

        for ($i = 0; $i <= $steps; $i++) {
            $fraction = $i / $steps;
            $points[] = [
                $from[0] + ($to[0] - $from[0]) * $fraction,
                $from[1] + ($to[1] - $from[1]) * $fraction,
            ];
        }

        return $points;
    }

    public function test_a_well_formed_route_is_usable(): void
    {
        $this->assertTrue($this->validator->isUsable($this->option(), $this->request()));
    }

    public function test_a_zero_distance_is_refused(): void
    {
        // Renders as a confident "0 km".
        $this->assertFalse($this->validator->isUsable($this->option(distance: 0), $this->request()));
    }

    public function test_a_negative_distance_is_refused(): void
    {
        $this->assertFalse($this->validator->isUsable($this->option(distance: -1), $this->request()));
    }

    public function test_a_zero_duration_is_refused(): void
    {
        $this->assertFalse($this->validator->isUsable($this->option(duration: 0), $this->request()));
    }

    public function test_a_zero_traffic_duration_is_refused(): void
    {
        // The same failure wearing a different hat: "arrives instantly, in
        // traffic".
        $this->assertFalse($this->validator->isUsable($this->option(traffic: 0), $this->request()));
    }

    public function test_a_broken_polyline_is_refused(): void
    {
        $this->assertFalse(
            $this->validator->isUsable($this->option(encoded: "\x01\x02\x03"), $this->request()),
        );
    }

    public function test_an_empty_polyline_is_refused(): void
    {
        $this->assertFalse($this->validator->isUsable($this->option(encoded: ''), $this->request()));
    }

    public function test_a_single_point_polyline_is_refused(): void
    {
        $this->assertFalse(
            $this->validator->isUsable(
                $this->option(encoded: PolylineCodec::encode([self::DELHI])),
                $this->request(),
            ),
        );
    }

    public function test_an_oversized_polyline_is_refused_before_it_is_decoded(): void
    {
        $validator = new RouteValidator(maxPolylineBytes: 100, endpointToleranceMetres: 5_000);

        // The decoder allocates as it reads, so the size check has to come first
        // to be worth anything at all.
        $this->assertFalse($validator->isUsable($this->option(), $this->request()));
    }

    public function test_a_route_that_starts_somewhere_else_is_refused(): void
    {
        // Internally perfect, and a journey from Mumbai. This is the mismatched,
        // cached or crossed-over response — the failure where nothing looks
        // wrong and everything is.
        $mumbai = [18.9401, 72.8352];

        $this->assertFalse(
            $this->validator->isUsable(
                $this->option(points: $this->line($mumbai, self::JAIPUR)),
                $this->request(),
            ),
        );
    }

    public function test_a_route_that_ends_somewhere_else_is_refused(): void
    {
        $chandigarh = [30.7412, 76.7825];

        $this->assertFalse(
            $this->validator->isUsable(
                $this->option(points: $this->line(self::DELHI, $chandigarh)),
                $this->request(),
            ),
        );
    }

    public function test_a_reversed_route_is_refused(): void
    {
        // Right two places, wrong direction. A customer would be shown a journey
        // running backwards, with an entirely plausible distance.
        $this->assertFalse(
            $this->validator->isUsable(
                $this->option(points: $this->line(self::JAIPUR, self::DELHI)),
                $this->request(),
            ),
        );
    }

    public function test_a_provider_snapping_to_a_nearby_road_is_allowed(): void
    {
        // Providers start a route at the nearest road, which is metres in a city
        // and can be a kilometre in open country. The check is for a different
        // region, not a different kerb.
        $nearby = [self::DELHI[0] + 0.01, self::DELHI[1] + 0.01];

        $this->assertTrue(
            $this->validator->isUsable(
                $this->option(points: $this->line($nearby, self::JAIPUR)),
                $this->request(),
            ),
        );
    }

    public function test_impossible_bounds_are_refused(): void
    {
        $points = $this->line(self::DELHI, self::JAIPUR);

        $option = new RouteOption(
            index: 0,
            distanceMeters: 278_000,
            durationSeconds: 16_200,
            trafficDurationSeconds: null,
            encodedPolyline: PolylineCodec::encode($points),
            bounds: new RouteBounds(north: 10, south: 40, east: 77, west: 75),
            summary: null,
        );

        $this->assertFalse($this->validator->isUsable($option, $this->request()));
    }

    public function test_it_returns_only_the_options_that_survive(): void
    {
        $result = new RouteResult(
            [$this->option(), $this->option(distance: 0), $this->option(duration: 0)],
            'google',
        );

        // One bad alternative does not sink the whole answer; a set with nothing
        // left in it is what the caller treats as a failure.
        $this->assertCount(1, $this->validator->usableOptions($result, $this->request()));
    }
}
