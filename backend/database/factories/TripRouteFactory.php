<?php

declare(strict_types=1);

namespace Database\Factories;

use App\Models\Trip;
use App\Models\TripRoute;
use App\Support\Route\PolylineCodec;
use App\Support\Trip\EndpointFingerprint;
use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<TripRoute>
 */
final class TripRouteFactory extends Factory
{
    protected $model = TripRoute::class;

    /**
     * A route between two real places, with a geometry that decodes.
     *
     * The coordinates are the real published positions of Hauz Khas and Jaipur
     * airport, as Module 05's factory uses. The distance and duration are
     * *fixture values* and are not claimed to be Google's: a factory exists so a
     * test can assert on persistence, ownership and selection, none of which care
     * what the numbers are.
     */
    public function definition(): array
    {
        $points = [];
        for ($i = 0; $i <= 20; $i++) {
            $fraction = $i / 20;
            $points[] = [
                28.5494 + (26.8242 - 28.5494) * $fraction,
                77.2001 + (75.8122 - 77.2001) * $fraction,
            ];
        }

        return [
            'provider' => 'fixture',
            'provider_route_index' => 0,
            'summary' => 'via NH 48',
            'distance_meters' => 278_000,
            'duration_seconds' => 16_200,
            'traffic_duration_seconds' => 17_100,
            'encoded_polyline' => PolylineCodec::encode($points),
            'bounds_north' => 28.5494,
            'bounds_south' => 26.8242,
            'bounds_east' => 77.2001,
            'bounds_west' => 75.8122,
            'is_recommended' => true,
            'is_selected' => false,
            'calculated_at' => CarbonImmutable::now(),
        ];
    }

    /** Attaches the route to a trip, with that trip's own endpoint fingerprint. */
    public function ofTrip(Trip $trip): self
    {
        return $this->state(fn (): array => [
            'trip_id' => $trip->getKey(),
            'endpoints_fingerprint' => EndpointFingerprint::of($trip),
        ]);
    }

    public function selected(): self
    {
        return $this->state(fn (): array => ['is_selected' => true]);
    }

    public function alternative(int $index): self
    {
        return $this->state(fn (): array => [
            'provider_route_index' => $index,
            'is_recommended' => false,
            'is_selected' => false,
            'summary' => 'via NH 148N',
            'distance_meters' => 265_000,
            'duration_seconds' => 17_040,
            'traffic_duration_seconds' => null,
        ]);
    }

    /** A route whose fingerprint no longer matches any trip. */
    public function stale(): self
    {
        return $this->state(fn (): array => [
            'endpoints_fingerprint' => str_repeat('0', 64),
        ]);
    }
}
