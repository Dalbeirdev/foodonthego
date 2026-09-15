<?php

declare(strict_types=1);

namespace Tests\Unit;

use App\Enums\AddressType;
use App\Enums\ApiErrorCode;
use App\Exceptions\ApiException;
use App\Models\CustomerAddress;
use App\Models\User;
use App\Services\Address\CustomerAddressService;
use Illuminate\Database\UniqueConstraintViolationException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\Support\CustomerFactory;
use Tests\TestCase;

/**
 * The default-address invariant and the ownership boundary, which are the two
 * things in this module that are dangerous to get wrong.
 */
final class CustomerAddressServiceTest extends TestCase
{
    use RefreshDatabase;

    private CustomerAddressService $service;

    private User $rahul;

    private User $ananya;

    protected function setUp(): void
    {
        parent::setUp();

        $this->service = $this->app->make(CustomerAddressService::class);
        $this->rahul = CustomerFactory::rahul();
        $this->ananya = CustomerFactory::ananya();
    }

    /** @param array<string, mixed> $overrides */
    private function attributes(array $overrides = []): array
    {
        return array_merge([
            'type' => AddressType::Home->value,
            'label' => 'Home',
            'address_line_1' => '12 Green Park Road',
            'city' => 'New Delhi',
            'state' => 'Delhi',
            'postal_code' => '110016',
            'country_code' => 'IN',
        ], $overrides);
    }

    public function test_the_first_address_a_customer_saves_becomes_their_default(): void
    {
        $address = $this->service->create($this->rahul, $this->attributes(), makeDefault: false);

        // Even though the request did not ask. A saved-address list with no
        // default makes the trip planner ask "from where?" to somebody who has
        // already answered that once.
        $this->assertTrue($address->is_default);
    }

    public function test_a_second_address_does_not_steal_the_default(): void
    {
        $home = $this->service->create($this->rahul, $this->attributes(), makeDefault: false);
        $work = $this->service->create(
            $this->rahul,
            $this->attributes(['type' => AddressType::Work->value, 'label' => 'Work']),
            makeDefault: false,
        );

        $this->assertTrue($home->fresh()->is_default);
        $this->assertFalse($work->fresh()->is_default);
    }

    public function test_making_one_default_clears_the_other(): void
    {
        $home = $this->service->create($this->rahul, $this->attributes(), makeDefault: false);
        $work = $this->service->create(
            $this->rahul,
            $this->attributes(['type' => AddressType::Work->value, 'label' => 'Work']),
            makeDefault: false,
        );

        $this->service->makeDefault($this->rahul, $work);

        $this->assertFalse($home->fresh()->is_default);
        $this->assertTrue($work->fresh()->is_default);
        $this->assertSame(1, $this->defaultCountFor($this->rahul));
    }

    public function test_the_database_itself_refuses_a_second_default(): void
    {
        $home = $this->service->create($this->rahul, $this->attributes(), makeDefault: false);
        $work = $this->service->create(
            $this->rahul,
            $this->attributes(['type' => AddressType::Work->value, 'label' => 'Work']),
            makeDefault: false,
        );

        // Bypassing the service entirely — the guarantee has to survive a code
        // path that forgets the lock, because one day some code path will.
        $this->expectException(UniqueConstraintViolationException::class);

        CustomerAddress::query()->whereKey($work->getKey())->update(['is_default' => true]);
        $this->assertNotNull($home);
    }

    public function test_two_customers_may_each_have_their_own_default(): void
    {
        $this->service->create($this->rahul, $this->attributes(), makeDefault: false);
        $this->service->create($this->ananya, $this->attributes(), makeDefault: false);

        // The uniqueness is per customer, not global — an obvious statement that
        // a naive unique index on `is_default` would have got wrong.
        $this->assertSame(1, $this->defaultCountFor($this->rahul));
        $this->assertSame(1, $this->defaultCountFor($this->ananya));
    }

    public function test_deleting_the_default_promotes_the_newest_survivor(): void
    {
        $home = $this->service->create($this->rahul, $this->attributes(), makeDefault: false);
        $work = $this->service->create(
            $this->rahul,
            $this->attributes(['type' => AddressType::Work->value, 'label' => 'Work']),
            makeDefault: false,
        );
        $other = $this->service->create(
            $this->rahul,
            $this->attributes(['type' => AddressType::Other->value, 'label' => "Parents' House"]),
            makeDefault: false,
        );

        $this->service->delete($this->rahul, $home);

        // Deterministic: the newest remaining address, which is the best guess at
        // where somebody is living or working now.
        $this->assertTrue($other->fresh()->is_default);
        $this->assertFalse($work->fresh()->is_default);
        $this->assertSame(1, $this->defaultCountFor($this->rahul));
    }

    public function test_deleting_a_non_default_leaves_the_default_alone(): void
    {
        $home = $this->service->create($this->rahul, $this->attributes(), makeDefault: false);
        $work = $this->service->create(
            $this->rahul,
            $this->attributes(['type' => AddressType::Work->value, 'label' => 'Work']),
            makeDefault: false,
        );

        $this->service->delete($this->rahul, $work);

        $this->assertTrue($home->fresh()->is_default);
    }

    public function test_deleting_the_last_address_leaves_no_default_and_no_error(): void
    {
        $home = $this->service->create($this->rahul, $this->attributes(), makeDefault: false);

        $this->service->delete($this->rahul, $home);

        $this->assertSame(0, $this->defaultCountFor($this->rahul));
        $this->assertDatabaseCount('customer_addresses', 0);
    }

    public function test_an_address_belonging_to_somebody_else_is_reported_as_missing(): void
    {
        $hers = $this->service->create($this->ananya, $this->attributes(), makeDefault: false);

        try {
            $this->service->ownedByOrFail($this->rahul, $hers->uuid);
            $this->fail("One customer reached another customer's address.");
        } catch (ApiException $e) {
            // Deliberately the same answer as an address that does not exist.
            // 403-versus-404 would tell a prober which ids are real.
            $this->assertSame(ApiErrorCode::AddressNotFound, $e->errorCode);
        }
    }

    public function test_an_address_that_does_not_exist_gives_the_same_answer(): void
    {
        try {
            $this->service->ownedByOrFail($this->rahul, (string) Str::uuid());
            $this->fail('A missing address resolved.');
        } catch (ApiException $e) {
            $this->assertSame(ApiErrorCode::AddressNotFound, $e->errorCode);
        }
    }

    public function test_the_list_is_scoped_and_ordered_default_first(): void
    {
        $this->service->create($this->ananya, $this->attributes(), makeDefault: false);

        $home = $this->service->create($this->rahul, $this->attributes(), makeDefault: false);
        $work = $this->service->create(
            $this->rahul,
            $this->attributes(['type' => AddressType::Work->value, 'label' => 'Work']),
            makeDefault: false,
        );
        $this->service->makeDefault($this->rahul, $work);

        $list = $this->service->listFor($this->rahul);

        $this->assertCount(2, $list);
        $this->assertSame($work->uuid, $list->first()->uuid);
        $this->assertSame($home->uuid, $list->last()->uuid);
    }

    public function test_the_one_line_address_is_composed_rather_than_typed(): void
    {
        $address = $this->service->create($this->rahul, $this->attributes(), makeDefault: false);

        $this->assertSame(
            '12 Green Park Road, New Delhi, Delhi 110016, IN',
            $address->formatted_address,
        );
    }

    public function test_a_partial_update_recomposes_the_whole_one_line_address(): void
    {
        $address = $this->service->create($this->rahul, $this->attributes(), makeDefault: false);

        $updated = $this->service->update(
            $this->rahul,
            $address,
            ['city' => 'Gurugram'],
            makeDefault: null,
        );

        // The street has to survive a PATCH that only mentioned the city.
        $this->assertStringContainsString('12 Green Park Road', $updated->formatted_address);
        $this->assertStringContainsString('Gurugram', $updated->formatted_address);
    }

    public function test_a_missing_label_falls_back_to_the_type(): void
    {
        $address = $this->service->create(
            $this->rahul,
            $this->attributes(['type' => AddressType::Work->value, 'label' => '']),
            makeDefault: false,
        );

        $this->assertSame('Work', $address->label);
    }

    public function test_coordinates_stay_null_when_nothing_geocoded(): void
    {
        $address = $this->service->create($this->rahul, $this->attributes(), makeDefault: false);

        // Null, not 0,0 — which is a real place in the Gulf of Guinea and would
        // route a traveller into the Atlantic.
        $this->assertNull($address->latitude);
        $this->assertNull($address->longitude);
        $this->assertNull($address->place_id);
    }

    public function test_the_saved_address_limit_is_enforced(): void
    {
        config(['foodonthego.addresses.max_per_customer' => 3]);

        for ($i = 0; $i < 3; $i++) {
            $this->service->create(
                $this->rahul,
                $this->attributes(['address_line_1' => "House {$i} Road"]),
                makeDefault: false,
            );
        }

        try {
            $this->service->create($this->rahul, $this->attributes(), makeDefault: false);
            $this->fail('The limit was not enforced.');
        } catch (ApiException $e) {
            $this->assertSame(ApiErrorCode::AddressLimitReached, $e->errorCode);
        }

        $this->assertDatabaseCount('customer_addresses', 3);
    }

    private function defaultCountFor(User $customer): int
    {
        return CustomerAddress::query()
            ->where('customer_id', $customer->getKey())
            ->where('is_default', true)
            ->count();
    }
}
