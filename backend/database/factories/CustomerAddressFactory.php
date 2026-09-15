<?php

declare(strict_types=1);

namespace Database\Factories;

use App\Enums\AddressType;
use App\Models\CustomerAddress;
use App\Support\Address\AddressFormatter;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Support\Str;

/**
 * @extends Factory<CustomerAddress>
 */
final class CustomerAddressFactory extends Factory
{
    protected $model = CustomerAddress::class;

    /** @return array<string, mixed> */
    public function definition(): array
    {
        $parts = [
            'address_line_1' => '12 Green Park Road',
            'address_line_2' => null,
            'city' => 'New Delhi',
            'state' => 'Delhi',
            'postal_code' => '110016',
            'country_code' => 'IN',
        ];

        return [
            'uuid' => (string) Str::uuid(),
            'type' => AddressType::Home,
            'label' => 'Home',
            ...$parts,
            'landmark' => null,
            'formatted_address' => AddressFormatter::compose($parts),
            // Never invented. A factory that fabricated coordinates would let a
            // test pass against data production can never produce.
            'latitude' => null,
            'longitude' => null,
            'place_id' => null,
            'is_default' => false,
        ];
    }

    public function work(): self
    {
        return $this->state(fn (): array => [
            'type' => AddressType::Work,
            'label' => 'Work',
            'address_line_1' => 'Connaught Place',
            'postal_code' => '110001',
            'formatted_address' => 'Connaught Place, New Delhi, Delhi 110001, IN',
        ]);
    }

    public function isDefault(): self
    {
        return $this->state(fn (): array => ['is_default' => true]);
    }
}
