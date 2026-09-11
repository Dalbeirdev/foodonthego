<?php

declare(strict_types=1);

namespace Database\Factories;

use App\Enums\RestaurantStatus;
use App\Enums\RestaurantVerificationStatus;
use App\Models\Restaurant;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Support\Str;

/**
 * @extends Factory<Restaurant>
 *
 * Defaults to a restaurant that is **not** discoverable — draft, unverified,
 * switched off. A test that wants a visible restaurant says so with
 * {@see discoverable()}, which means a test that forgets to cannot accidentally
 * assert against a restaurant it never meant to publish.
 */
final class RestaurantFactory extends Factory
{
    protected $model = Restaurant::class;

    public function definition(): array
    {
        return [
            'uuid' => (string) Str::uuid(),
            'name' => $this->faker->company().' Kitchen',
            'display_name' => null,
            'latitude' => null,
            'longitude' => null,
            'formatted_address' => $this->faker->streetAddress(),
            'city' => 'New Delhi',
            'region' => 'Delhi',
            'country_code' => 'IN',
            'timezone' => 'Asia/Kolkata',
            'status' => RestaurantStatus::Draft,
            'verification_status' => RestaurantVerificationStatus::Pending,
            'is_discoverable' => false,
            'is_accepting_orders' => true,
            'price_level' => 2,
            // Null, as every real row is until there is a reviews module.
            'rating_average' => null,
            'rating_count' => 0,
            // Present so privacy tests have something real to catch.
            'owner_name' => $this->faker->name(),
            'owner_phone' => '+919812345678',
            'owner_email' => $this->faker->safeEmail(),
            'tax_identifier' => '07AABCU9603R1ZM',
            'bank_account_reference' => 'HDFC-XXXX-4412',
            'commission_rate' => 18.50,
            'internal_notes' => 'Internal only. Never customer facing.',
        ];
    }

    /** Approved, verified, switched on — everything but a position. */
    public function discoverable(): self
    {
        return $this->state(fn (): array => [
            'status' => RestaurantStatus::Approved,
            'verification_status' => RestaurantVerificationStatus::Verified,
            'is_discoverable' => true,
        ]);
    }

    public function at(float $latitude, float $longitude): self
    {
        return $this->state(fn (): array => [
            'latitude' => $latitude,
            'longitude' => $longitude,
        ]);
    }

    public function suspended(): self
    {
        return $this->state(fn (): array => ['status' => RestaurantStatus::Suspended]);
    }

    public function disabled(): self
    {
        return $this->state(fn (): array => ['status' => RestaurantStatus::Disabled]);
    }

    public function pendingVerification(): self
    {
        return $this->state(fn (): array => [
            'verification_status' => RestaurantVerificationStatus::Pending,
        ]);
    }

    public function paused(): self
    {
        return $this->state(fn (): array => ['is_accepting_orders' => false]);
    }

    public function named(string $name): self
    {
        return $this->state(fn (): array => ['name' => $name]);
    }

    public function inTimezone(string $timezone): self
    {
        return $this->state(fn (): array => ['timezone' => $timezone]);
    }

    public function rated(string $average, int $count): self
    {
        return $this->state(fn (): array => [
            'rating_average' => $average,
            'rating_count' => $count,
        ]);
    }
}
