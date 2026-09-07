<?php

declare(strict_types=1);

namespace Tests\Support;

use App\Enums\RouteStatus;
use App\Models\Restaurant;
use App\Models\Trip;
use App\Models\TripRoute;
use App\Models\User;
use App\Support\Geo\Coordinate;
use App\Support\Geo\Distance;
use App\Support\Route\PolylineCodec;
use App\Support\Trip\EndpointFingerprint;
use Carbon\CarbonImmutable;

/**
 * Building the world a discovery test needs.
 *
 * A discovery test needs a customer, a trip, a selected route with real
 * geometry, and restaurants placed at known distances from that geometry. Doing
 * that by hand in each test would be forty lines of setup before the first
 * assertion, and the interesting part — *where* a restaurant is relative to the
 * route — would be buried in it.
 *
 * Positions are computed rather than typed, for the same reason as in the
 * seeder: "1.2 km off the route" should be a fact the helper guarantees, not a
 * plausible-looking coordinate somebody hoped was right.
 */
final class RestaurantFixtures
{
    /** Green Park, New Delhi. */
    public const ORIGIN = [28.5590, 77.2070];

    /** Jaipur International Airport. */
    public const DESTINATION = [26.8242, 75.8122];

    /**
     * A trip with a READY, selected route whose geometry is a real polyline.
     *
     * The geometry is a many-point line between the two endpoints. It is not a
     * road — no test in this suite can produce one — but it is genuine polyline
     * data with genuine cumulative distances, which is what the projection
     * arithmetic under test operates on.
     */
    public static function tripWithSelectedRoute(
        User $customer,
        ?array $origin = null,
        ?array $destination = null,
    ): Trip {
        $origin ??= self::ORIGIN;
        $destination ??= self::DESTINATION;

        $trip = Trip::factory()->ownedBy($customer)->create([
            'origin_latitude' => $origin[0],
            'origin_longitude' => $origin[1],
            'destination_latitude' => $destination[0],
            'destination_longitude' => $destination[1],
            'route_status' => RouteStatus::Ready,
        ]);

        $points = self::line($origin, $destination, 64);

        TripRoute::factory()->ofTrip($trip)->selected()->create([
            'encoded_polyline' => PolylineCodec::encode($points),
            'distance_meters' => (int) round(self::lengthOf($points)),
            'duration_seconds' => 14_000,
            // Explicit, because the factory's default carries one and leaving it
            // would make every derived figure — time-ahead, and the base a detour
            // is measured against — come from a duration this fixture never set.
            'traffic_duration_seconds' => null,
            'endpoints_fingerprint' => EndpointFingerprint::of($trip),
            'calculated_at' => CarbonImmutable::now(),
        ]);

        return $trip->refresh();
    }

    /**
     * A discoverable restaurant a stated distance off the route, a stated
     * fraction along it.
     *
     * A negative fraction places it behind the origin, which is how the
     * backtracking case is set up.
     *
     * @param  list<string>  $cuisines
     * @param  list<string>  $facilities
     */
    public static function nearRoute(
        float $fraction,
        float $offsetMetres,
        string $name = 'Test Kitchen',
        bool $open = true,
        array $cuisines = ['North Indian'],
        array $facilities = ['Parking'],
        ?array $origin = null,
        ?array $destination = null,
    ): Restaurant {
        [$latitude, $longitude] = self::offset(
            $fraction,
            $offsetMetres,
            $origin ?? self::ORIGIN,
            $destination ?? self::DESTINATION,
        );

        $restaurant = Restaurant::factory()
            ->discoverable()
            ->named($name)
            ->at($latitude, $longitude)
            ->create();

        foreach ($cuisines as $position => $cuisine) {
            $restaurant->cuisines()->create(['cuisine' => $cuisine, 'position' => $position]);
        }

        foreach ($facilities as $position => $facility) {
            $restaurant->facilities()->create(['facility' => $facility, 'position' => $position]);
        }

        if ($open) {
            self::openAllWeek($restaurant);
        }

        return $restaurant->load(['cuisines', 'facilities', 'openingHours']);
    }

    /**
     * Open every hour of every day, so a test never fails on the clock.
     *
     * That promise was false for half an hour a night until the availability
     * rule was fixed. `23:59:59` is a closing time, and a restaurant within
     * thirty minutes of closing reads CLOSING_SOON — so every assertion of OPEN
     * against this fixture failed between 23:30 and 23:59 local, which is 18:00
     * to 18:29 UTC. CI found it on a docs-only commit.
     *
     * It holds now because `closesWithin` asks whether the restaurant will be
     * *shut* soon rather than whether the current window ends soon, and a
     * window that hands straight over to the next one is not closing.
     */
    public static function openAllWeek(Restaurant $restaurant): void
    {
        foreach (range(0, 6) as $day) {
            $restaurant->openingHours()->create([
                'day_of_week' => $day,
                'opens_at' => '00:00:00',
                'closes_at' => '23:59:59',
            ]);
        }
    }

    /** One window a day, in the restaurant's own local time. */
    public static function openDaily(Restaurant $restaurant, string $from, string $to): void
    {
        foreach (range(0, 6) as $day) {
            $restaurant->openingHours()->create([
                'day_of_week' => $day,
                'opens_at' => $from,
                'closes_at' => $to,
            ]);
        }
    }

    /**
     * A point a fraction along the origin-destination line, offset
     * perpendicular to it.
     *
     * @return array{0: float, 1: float}
     */
    public static function offset(
        float $fraction,
        float $offsetMetres,
        array $origin,
        array $destination,
    ): array {
        $latitude = $origin[0] + ($destination[0] - $origin[0]) * $fraction;
        $longitude = $origin[1] + ($destination[1] - $origin[1]) * $fraction;

        $cos = cos(deg2rad($latitude));

        $dx = ($destination[1] - $origin[1]) * $cos;
        $dy = $destination[0] - $origin[0];
        $length = sqrt($dx * $dx + $dy * $dy);

        $degreesPerMetre = rad2deg(1 / 6_371_008.8);

        return [
            $latitude + ($dx / $length) * $offsetMetres * $degreesPerMetre,
            $longitude + ((-$dy / $length) * $offsetMetres * $degreesPerMetre) / $cos,
        ];
    }

    /** @return list<array{0: float, 1: float}> */
    public static function line(array $from, array $to, int $steps): array
    {
        $points = [];

        for ($i = 0; $i <= $steps; $i++) {
            $f = $i / $steps;

            $points[] = [
                $from[0] + ($to[0] - $from[0]) * $f,
                $from[1] + ($to[1] - $from[1]) * $f,
            ];
        }

        return $points;
    }

    /** @param list<array{0: float, 1: float}> $points */
    public static function lengthOf(array $points): float
    {
        $total = 0.0;

        for ($i = 1, $n = count($points); $i < $n; $i++) {
            $total += Distance::haversineMetres(
                new Coordinate($points[$i - 1][0], $points[$i - 1][1]),
                new Coordinate($points[$i][0], $points[$i][1]),
            );
        }

        return $total;
    }
}
