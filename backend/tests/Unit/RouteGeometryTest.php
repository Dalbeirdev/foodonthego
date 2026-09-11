<?php

declare(strict_types=1);

namespace Tests\Unit;

use App\Support\Geo\Coordinate;
use App\Support\Geo\Distance;
use App\Support\Geo\RouteGeometry;
use App\Support\Route\PolylineCodec;
use PHPUnit\Framework\TestCase;

/**
 * The arithmetic every discovery figure is built on.
 *
 * These are the numbers a customer acts on — "68 km ahead", "1.8 km off your
 * route" — so they are tested against distances that can be checked by hand
 * rather than against whatever the implementation happened to return the first
 * time it ran.
 */
final class RouteGeometryTest extends TestCase
{
    /** Delhi to Jaipur, near enough. */
    private const ORIGIN = [28.5590, 77.2070];

    private const DESTINATION = [26.8242, 75.8122];

    private function straightRoute(int $steps = 64): RouteGeometry
    {
        $points = [];

        for ($i = 0; $i <= $steps; $i++) {
            $f = $i / $steps;

            $points[] = new Coordinate(
                self::ORIGIN[0] + (self::DESTINATION[0] - self::ORIGIN[0]) * $f,
                self::ORIGIN[1] + (self::DESTINATION[1] - self::ORIGIN[1]) * $f,
            );
        }

        return RouteGeometry::fromPoints($points);
    }

    public function test_the_route_length_matches_the_distance_between_its_ends(): void
    {
        $route = $this->straightRoute();

        $direct = Distance::haversineMetres(
            new Coordinate(...self::ORIGIN),
            new Coordinate(...self::DESTINATION),
        );

        // A straight line's accumulated segments must add up to its own length.
        // If they do not, every distance-ahead figure is wrong by the difference.
        $this->assertEqualsWithDelta($direct, $route->totalMetres(), 50.0);
    }

    public function test_a_point_on_the_route_has_no_meaningful_proximity(): void
    {
        $route = $this->straightRoute();
        $midpoint = $route->points()[32];

        $projection = $route->project($midpoint);

        $this->assertLessThan(1.0, $projection->proximityMetres);
        $this->assertEqualsWithDelta(0.5, $projection->progressFraction(), 0.02);
    }

    public function test_proximity_is_the_perpendicular_distance_not_the_distance_to_a_vertex(): void
    {
        // A route of two points 200 km apart, and somewhere 3 km off the middle
        // of it. Measuring to the nearest *vertex* would answer about 100 km.
        $route = RouteGeometry::fromPoints([
            new Coordinate(28.0, 77.0),
            new Coordinate(28.0, 79.0),
        ]);

        $projection = $route->project(new Coordinate(28.027, 78.0));

        $this->assertEqualsWithDelta(3_000.0, $projection->proximityMetres, 120.0);
    }

    public function test_distance_ahead_increases_along_the_route(): void
    {
        $route = $this->straightRoute();

        $near = $route->project($route->points()[8]);
        $middle = $route->project($route->points()[32]);
        $far = $route->project($route->points()[56]);

        // The list a traveller reads is ordered by this. Out of order, it reads
        // as a random pile of restaurants.
        $this->assertLessThan($middle->alongRouteMetres, $near->alongRouteMetres);
        $this->assertLessThan($far->alongRouteMetres, $middle->alongRouteMetres);
    }

    public function test_a_point_behind_the_origin_projects_to_the_start(): void
    {
        $route = $this->straightRoute();

        // North-east of Delhi: the wrong way entirely.
        $behind = new Coordinate(28.70, 77.35);

        $projection = $route->project($behind);

        // There is nowhere earlier on the route to project to, which is the
        // signature this module reads as "reaching here means turning round".
        $this->assertTrue($projection->isAtRouteStart());
        $this->assertSame(0.0, $projection->progressFraction());
    }

    public function test_a_point_beyond_the_destination_projects_to_the_end(): void
    {
        $route = $this->straightRoute();

        $beyond = new Coordinate(26.60, 75.60);

        $projection = $route->project($beyond);

        $this->assertEqualsWithDelta(1.0, $projection->progressFraction(), 0.001);
    }

    public function test_a_self_crossing_route_resolves_to_the_earlier_leg(): void
    {
        // Out east along one line, back west along another a little to the
        // north. A restaurant between them is genuinely near both.
        $points = [];

        for ($i = 0; $i <= 20; $i++) {
            $points[] = new Coordinate(28.0, 77.0 + $i * 0.05);
        }

        for ($i = 20; $i >= 0; $i--) {
            $points[] = new Coordinate(28.02, 77.0 + $i * 0.05);
        }

        $route = RouteGeometry::fromPoints($points);

        $projection = $route->project(new Coordinate(28.01, 77.5));

        // Picking the return leg would report this restaurant as 150 km into
        // the journey instead of 49 km — the same place, described as somewhere
        // else entirely. Being early is the error that costs the traveller
        // nothing.
        $this->assertLessThan(0.4, $projection->progressFraction());
    }

    public function test_simplification_never_moves_a_point_across_the_corridor(): void
    {
        $curvy = [];

        for ($i = 0; $i <= 500; $i++) {
            $curvy[] = new Coordinate(28.0 + 0.002 * sin($i / 8), 77.0 + $i * 0.002);
        }

        $full = RouteGeometry::fromPoints($curvy);

        $simplified = RouteGeometry::fromEncoded(
            PolylineCodec::encode(array_map(
                static fn (Coordinate $c): array => [$c->latitude, $c->longitude],
                $curvy,
            )),
            150.0,
        );

        $this->assertLessThan($full->pointCount(), $simplified->pointCount());

        $probe = new Coordinate(28.03, 77.5);

        // The whole safety argument for simplifying: the tolerance is an order
        // of magnitude below the corridor, so a restaurant cannot be admitted or
        // rejected because of it.
        $this->assertEqualsWithDelta(
            $full->project($probe)->proximityMetres,
            $simplified->project($probe)->proximityMetres,
            200.0,
        );
    }

    public function test_the_bounding_box_contains_the_route_and_its_margin(): void
    {
        $route = $this->straightRoute();
        $box = $route->boundingBox(5_000);

        foreach ($route->points() as $point) {
            $this->assertGreaterThanOrEqual($box['south'], $point->latitude);
            $this->assertLessThanOrEqual($box['north'], $point->latitude);
            $this->assertGreaterThanOrEqual($box['west'], $point->longitude);
            $this->assertLessThanOrEqual($box['east'], $point->longitude);
        }

        // And the margin is real: a point 4 km off the origin must be inside it,
        // or the corridor search would never see the restaurants it exists for.
        $this->assertGreaterThan(0.03, $box['north'] - self::ORIGIN[0]);
    }

    public function test_a_repeated_point_does_not_divide_by_zero(): void
    {
        // Providers do emit consecutive identical points.
        $route = RouteGeometry::fromPoints([
            new Coordinate(28.0, 77.0),
            new Coordinate(28.0, 77.0),
            new Coordinate(28.0, 77.5),
        ]);

        $projection = $route->project(new Coordinate(28.01, 77.25));

        $this->assertGreaterThan(0.0, $projection->proximityMetres);
        $this->assertGreaterThan(0.0, $projection->alongRouteMetres);
    }

    public function test_the_flat_metric_agrees_with_the_round_one_over_short_spans(): void
    {
        // The projection loop uses the cheap metric to choose a segment. That is
        // only safe while the two agree at corridor scale.
        $a = new Coordinate(28.0000, 77.0000);
        $b = new Coordinate(28.0300, 77.0300);

        $exact = Distance::haversineMetres($a, $b);
        $flat = Distance::equirectangularMetres($a, $b);

        $this->assertEqualsWithDelta($exact, $flat, $exact * 0.001);
    }
}
