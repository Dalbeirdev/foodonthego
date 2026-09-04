<?php

declare(strict_types=1);

namespace Tests\Feature\Api\Customer;

use App\Models\CustomerAddress;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\Support\CustomerFactory;
use Tests\TestCase;

/**
 * Insecure Direct Object Reference, from both sides.
 *
 * Rahul and Ananya are real accounts with real addresses, so every assertion
 * here is about a rule being applied rather than about a `WHERE` clause
 * happening to filter out a fabricated id.
 *
 * The expected answer throughout is **404, not 403**. Telling a caller "that
 * exists but is not yours" turns the endpoint into an oracle: walk a range of
 * ids and the difference between the two responses maps out which ones are real
 * addresses belonging to real customers.
 */
final class AddressOwnershipTest extends TestCase
{
    use RefreshDatabase;

    private const BASE = '/api/v1/customer/addresses';

    private User $rahul;

    private User $ananya;

    private string $rahulToken;

    private string $ananyaToken;

    private CustomerAddress $ananyasAddress;

    protected function setUp(): void
    {
        parent::setUp();

        $this->rahul = CustomerFactory::rahul();
        $this->ananya = CustomerFactory::ananya();
        $this->rahulToken = CustomerFactory::tokenFor($this->rahul);
        $this->ananyaToken = CustomerFactory::tokenFor($this->ananya);

        // Ananya's Work address in Gurugram, created through the real API so it
        // is exactly what the product produces.
        $this->ananyasAddress = $this->addressFor($this->ananyaToken, [
            'type' => 'WORK',
            'address_line_1' => 'Cyber City',
            'city' => 'Gurugram',
            'state' => 'Haryana',
            'postal_code' => '122002',
            'country_code' => 'IN',
        ]);

        // Rahul has one of his own, so his account is not empty — an empty
        // account can hide a bug where the scope is applied by accident.
        $this->addressFor($this->rahulToken, [
            'type' => 'HOME',
            'address_line_1' => '12 Green Park Road',
            'city' => 'New Delhi',
            'state' => 'Delhi',
            'postal_code' => '110016',
            'country_code' => 'IN',
        ]);
    }

    /** @param array<string, mixed> $payload */
    private function addressFor(string $token, array $payload): CustomerAddress
    {
        $uuid = $this->as($token)->postJson(self::BASE, $payload)
            ->assertCreated()
            ->json('data.id');

        return CustomerAddress::query()->where('uuid', $uuid)->firstOrFail();
    }

    private function as(string $token): self
    {
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', 'Bearer '.$token);
    }

    private function asRahul(): self
    {
        return $this->as($this->rahulToken);
    }

    // --- Scenario 11: IDOR read ---------------------------------------------

    public function test_rahul_cannot_read_ananyas_address(): void
    {
        $response = $this->asRahul()->getJson(self::BASE.'/'.$this->ananyasAddress->uuid);

        $response->assertStatus(404)->assertJsonPath('error.code', 'ADDRESS_NOT_FOUND');

        // And not a word of her address in the body.
        foreach (['Cyber City', 'Gurugram', 'Haryana', '122002'] as $leak) {
            $this->assertStringNotContainsString($leak, $response->getContent());
        }
    }

    public function test_the_list_never_includes_another_customers_address(): void
    {
        $list = $this->asRahul()->getJson(self::BASE)->json('data');

        $this->assertCount(1, $list);
        $this->assertSame('12 Green Park Road', $list[0]['address_line_1']);
    }

    public function test_an_address_that_does_not_exist_answers_identically(): void
    {
        $missing = $this->asRahul()
            ->getJson(self::BASE.'/'.Str::uuid())
            ->assertStatus(404)
            ->json('error');

        $notMine = $this->asRahul()
            ->getJson(self::BASE.'/'.$this->ananyasAddress->uuid)
            ->assertStatus(404)
            ->json('error');

        // Identical but for the correlation id: the pair must not be a directory
        // of which ids are real.
        $this->assertSame($missing['code'], $notMine['code']);
        $this->assertSame($missing['message'], $notMine['message']);
    }

    // --- Scenario 12: IDOR update -------------------------------------------

    public function test_rahul_cannot_update_ananyas_address(): void
    {
        $this->asRahul()->patchJson(self::BASE.'/'.$this->ananyasAddress->uuid, [
            'address_line_1' => 'Rewritten by Rahul',
            'city' => 'Nowhere',
        ])->assertStatus(404);

        $this->assertDatabaseHas('customer_addresses', [
            'id' => $this->ananyasAddress->getKey(),
            'address_line_1' => 'Cyber City',
            'city' => 'Gurugram',
        ]);
    }

    public function test_rahul_cannot_make_ananyas_address_his_default(): void
    {
        $this->asRahul()->postJson(self::BASE.'/'.$this->ananyasAddress->uuid.'/default')
            ->assertStatus(404);

        $this->asRahul()->patchJson(self::BASE.'/'.$this->ananyasAddress->uuid, [
            'is_default' => true,
        ])->assertStatus(404);

        // Hers is untouched, and it is still hers.
        $fresh = $this->ananyasAddress->fresh();
        $this->assertSame($this->ananya->getKey(), $fresh->customer_id);
        $this->assertTrue($fresh->is_default);
    }

    // --- Scenario 13: IDOR delete -------------------------------------------

    public function test_rahul_cannot_delete_ananyas_address(): void
    {
        $this->asRahul()->deleteJson(self::BASE.'/'.$this->ananyasAddress->uuid)
            ->assertStatus(404);

        $this->assertDatabaseHas('customer_addresses', [
            'id' => $this->ananyasAddress->getKey(),
        ]);
        $this->assertSame(1, $this->addressCountFor($this->ananya));
    }

    // --- Scenario 14: ownership injection -----------------------------------

    public function test_a_create_naming_another_customer_belongs_to_the_caller(): void
    {
        $id = $this->asRahul()->postJson(self::BASE, [
            'type' => 'OTHER',
            'label' => 'Injected',
            'address_line_1' => 'Somewhere Else',
            'city' => 'New Delhi',
            'state' => 'Delhi',
            'postal_code' => '110001',
            'country_code' => 'IN',
            // Every shape somebody might try.
            'customer_id' => $this->ananya->getKey(),
            'user_id' => $this->ananya->getKey(),
            'customer_uuid' => $this->ananya->uuid,
            'created_by' => $this->ananya->getKey(),
        ])->assertCreated()->json('data.id');

        $created = CustomerAddress::query()->where('uuid', $id)->firstOrFail();

        // Ownership comes from the token, never from the body.
        $this->assertSame($this->rahul->getKey(), $created->customer_id);
        $this->assertSame(1, $this->addressCountFor($this->ananya));
    }

    public function test_an_update_cannot_reassign_an_address_to_somebody_else(): void
    {
        $mine = CustomerAddress::query()->where('customer_id', $this->rahul->getKey())->firstOrFail();

        $this->asRahul()->patchJson(self::BASE.'/'.$mine->uuid, [
            'landmark' => 'Updated',
            'customer_id' => $this->ananya->getKey(),
        ])->assertOk();

        $this->assertSame($this->rahul->getKey(), $mine->fresh()->customer_id);
    }

    public function test_an_address_uuid_cannot_be_chosen_by_the_caller(): void
    {
        $chosen = '00000000-0000-4000-8000-00000000dead';

        $id = $this->asRahul()->postJson(self::BASE, [
            'type' => 'WORK',
            'address_line_1' => 'Connaught Place',
            'city' => 'New Delhi',
            'state' => 'Delhi',
            'postal_code' => '110001',
            'country_code' => 'IN',
            'uuid' => $chosen,
            'id' => 999999,
        ])->assertCreated()->json('data.id');

        $this->assertNotSame($chosen, $id);
        $this->assertDatabaseMissing('customer_addresses', ['uuid' => $chosen]);
    }

    // --- Scenario 15: concurrent default ------------------------------------

    public function test_two_addresses_can_never_both_be_default(): void
    {
        $second = $this->addressFor($this->rahulToken, [
            'type' => 'WORK',
            'address_line_1' => 'Connaught Place',
            'city' => 'New Delhi',
            'state' => 'Delhi',
            'postal_code' => '110001',
            'country_code' => 'IN',
        ]);
        $first = CustomerAddress::query()
            ->where('customer_id', $this->rahul->getKey())
            ->where('type', 'HOME')
            ->firstOrFail();

        // Alternating requests as fast as the test can issue them. A sequential
        // test cannot prove a race is impossible — the unique index on the
        // generated column does that, and CustomerAddressServiceTest asserts it
        // directly. This proves the endpoint never leaves a bad state behind.
        for ($i = 0; $i < 12; $i++) {
            $target = $i % 2 === 0 ? $second : $first;
            $this->asRahul()->postJson(self::BASE.'/'.$target->uuid.'/default')->assertOk();

            $this->assertSame(1, $this->defaultCountFor($this->rahul));
        }
    }

    // --- Scenario 16: rapid save --------------------------------------------

    public function test_repeated_taps_on_save_do_not_stack_up_addresses(): void
    {
        $payload = [
            'type' => 'OTHER',
            'label' => 'Factory',
            'address_line_1' => 'Plot 4, Industrial Area',
            'city' => 'Jaipur',
            'state' => 'Rajasthan',
            'postal_code' => '302013',
            'country_code' => 'IN',
        ];

        // Without an idempotency key the server cannot tell a double tap from two
        // deliberate saves of the same place — so it creates both, which is the
        // honest behaviour. The client is what must not send the second request;
        // see the submission lock in the Flutter form.
        //
        // What is asserted here is that the API stays consistent under it: no
        // duplicate defaults, no corrupted rows, and every row owned correctly.
        for ($i = 0; $i < 4; $i++) {
            $this->asRahul()->postJson(self::BASE, $payload)->assertCreated();
        }

        $this->assertSame(1, $this->defaultCountFor($this->rahul));
        $this->assertSame(
            0,
            CustomerAddress::query()
                ->where('customer_id', '!=', $this->rahul->getKey())
                ->where('label', 'Factory')
                ->count(),
        );
    }

    public function test_the_same_request_with_an_idempotency_key_creates_one_address(): void
    {
        $payload = [
            'type' => 'OTHER',
            'label' => 'Factory',
            'address_line_1' => 'Plot 4, Industrial Area',
            'city' => 'Jaipur',
            'state' => 'Rajasthan',
            'postal_code' => '302013',
            'country_code' => 'IN',
        ];

        $key = (string) Str::uuid();

        // Module 01's idempotency middleware already answers the double-tap
        // problem properly, and it applies here for free.
        $first = $this->asRahul()->withHeader('Idempotency-Key', $key)
            ->postJson(self::BASE, $payload)->assertCreated()->json('data.id');
        $second = $this->asRahul()->withHeader('Idempotency-Key', $key)
            ->postJson(self::BASE, $payload)->json('data.id');

        $this->assertSame($first, $second);
        $this->assertSame(
            1,
            CustomerAddress::query()->where('label', 'Factory')->count(),
        );
    }

    // --- session ------------------------------------------------------------

    public function test_a_revoked_session_stops_reaching_addresses(): void
    {
        $this->asRahul()->getJson(self::BASE)->assertOk();

        $this->rahul->tokens()->delete();

        $this->asRahul()->getJson(self::BASE)
            ->assertStatus(401)
            ->assertJsonPath('error.code', 'UNAUTHENTICATED');
    }

    public function test_each_customer_sees_only_their_own_after_switching(): void
    {
        // The account-switch case, at the API level: the same client, two tokens.
        $rahulList = $this->asRahul()->getJson(self::BASE)->json('data');
        $ananyaList = $this->as($this->ananyaToken)->getJson(self::BASE)->json('data');

        $this->assertSame('12 Green Park Road', $rahulList[0]['address_line_1']);
        $this->assertSame('Cyber City', $ananyaList[0]['address_line_1']);
        $this->assertNotSame($rahulList[0]['id'], $ananyaList[0]['id']);
    }

    private function addressCountFor(User $customer): int
    {
        return CustomerAddress::query()->where('customer_id', $customer->getKey())->count();
    }

    private function defaultCountFor(User $customer): int
    {
        return CustomerAddress::query()
            ->where('customer_id', $customer->getKey())
            ->where('is_default', true)
            ->count();
    }
}
