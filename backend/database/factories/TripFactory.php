<?php

declare(strict_types=1);

namespace Database\Factories;

use App\Enums\LocationSourceType;
use App\Enums\RouteStatus;
use App\Enums\TripStatus;
use App\Models\Trip;
use App\Models\User;
use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<Trip>
 */
final class TripFactory extends Factory
{
    protected $model = Trip::class;

    /**
     * New Delhi to Jaipur, with the real coordinates of two real places.
     *
     * Real ones rather than `fake()->latitude()`, because half the rules in this
     * module are about distance: a random pair would make the same-location
     * threshold and any future corridor test meaningless, and two random points
     * are occasionally the same place by accident.
     *
     * `route_status` is NOT_CALCULATED and there is nowhere to put a distance,
     * so no test can accidentally be written against fabricated routing.
     *
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        return [
            'customer_id' => User::factory(),
            'status' => TripStatus::RoutePending,
            'route_status' => RouteStatus::NotCalculated,

            'origin_source_type' => LocationSourceType::PlaceSearch,
            'origin_saved_address_id' => null,
            'origin_place_id' => 'dev:hauz-khas',
            'origin_name' => 'Hauz Khas Village',
            'origin_formatted_address' => 'Hauz Khas, New Delhi, Delhi 110016',
            'origin_latitude' => '28.5494000',
            'origin_longitude' => '77.2001000',
            'origin_city' => 'New Delhi',
            'origin_region' => 'Delhi',
            'origin_country_code' => 'IN',
            'origin_postal_code' => '110016',

            'destination_source_type' => LocationSourceType::PlaceSearch,
            'destination_saved_address_id' => null,
            'destination_place_id' => 'dev:jaipur-airport',
            'destination_name' => 'Jaipur International Airport',
            'destination_formatted_address' => 'Airport Road, Sanganer, Jaipur, Rajasthan 302029',
            'destination_latitude' => '26.8242000',
            'destination_longitude' => '75.8122000',
            'destination_city' => 'Jaipur',
            'destination_region' => 'Rajasthan',
            'destination_country_code' => 'IN',
            'destination_postal_code' => '302029',

            'cancelled_at' => null,
        ];
    }

    public function ownedBy(User $customer): self
    {
        return $this->state(fn (): array => ['customer_id' => $customer->getKey()]);
    }

    public function discarded(): self
    {
        return $this->state(fn (): array => [
            'status' => TripStatus::Cancelled,
            'cancelled_at' => CarbonImmutable::now()->subHour(),
        ]);
    }

    /** A different pair of real places, for tests that need two distinct trips. */
    public function delhiToAgra(): self
    {
        return $this->state(fn (): array => [
            'destination_place_id' => 'dev:taj-mahal',
            'destination_name' => 'Taj Mahal',
            'destination_formatted_address' => 'Dharmapuri, Tajganj, Agra, Uttar Pradesh 282001',
            'destination_latitude' => '27.1751000',
            'destination_longitude' => '78.0421000',
            'destination_city' => 'Agra',
            'destination_region' => 'Uttar Pradesh',
            'destination_postal_code' => '282001',
        ]);
    }
}
