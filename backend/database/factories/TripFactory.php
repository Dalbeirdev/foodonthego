<?php

declare(strict_types=1);

namespace Database\Factories;

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
     * A journey between two real Indian cities, in the future, with **no
     * coordinates**.
     *
     * The absence is deliberate and load-bearing: a factory that filled in a
     * plausible latitude would make every test in this module run against
     * geocoded journeys, and the production reality — nothing is geocoded yet —
     * would be the one case never covered.
     *
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        $departure = CarbonImmutable::now()->addDays(fake()->numberBetween(1, 20))->addHours(3);

        return [
            'customer_id' => User::factory(),
            'status' => TripStatus::Planned,

            'origin_address_id' => null,
            'origin_label' => 'Home',
            'origin_formatted_address' => 'Hauz Khas, New Delhi, Delhi',
            'origin_city' => 'New Delhi',
            'origin_country_code' => 'IN',
            'origin_latitude' => null,
            'origin_longitude' => null,
            'origin_place_id' => null,

            'destination_address_id' => null,
            'destination_label' => 'Jaipur',
            'destination_formatted_address' => 'MI Road, Jaipur, Rajasthan',
            'destination_city' => 'Jaipur',
            'destination_country_code' => 'IN',
            'destination_latitude' => null,
            'destination_longitude' => null,
            'destination_place_id' => null,

            'departure_at' => $departure,
            'expected_arrival_at' => null,
            'traveller_count' => 1,
            'note' => null,
            'cancelled_at' => null,
            'cancellation_reason' => null,
        ];
    }

    public function ownedBy(User $customer): self
    {
        return $this->state(fn (): array => ['customer_id' => $customer->getKey()]);
    }

    public function departingAt(CarbonImmutable $when): self
    {
        return $this->state(fn (): array => ['departure_at' => $when]);
    }

    /** A journey whose departure has passed — history, not a plan. */
    public function departed(): self
    {
        return $this->state(fn (): array => [
            'departure_at' => CarbonImmutable::now()->subDays(3),
        ]);
    }

    public function cancelled(?string $reason = null): self
    {
        return $this->state(fn (): array => [
            'status' => TripStatus::Cancelled,
            'cancelled_at' => CarbonImmutable::now()->subHour(),
            'cancellation_reason' => $reason,
        ]);
    }
}
