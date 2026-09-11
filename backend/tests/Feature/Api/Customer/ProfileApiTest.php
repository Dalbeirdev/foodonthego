<?php

declare(strict_types=1);

namespace Tests\Feature\Api\Customer;

use App\Enums\AccountStatus;
use App\Enums\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Support\CustomerFactory;
use Tests\TestCase;

final class ProfileApiTest extends TestCase
{
    use RefreshDatabase;

    private User $rahul;

    private string $token;

    protected function setUp(): void
    {
        parent::setUp();

        $this->rahul = CustomerFactory::rahul();
        $this->token = CustomerFactory::tokenFor($this->rahul);
    }

    private function asRahul(): self
    {
        // Guards forgotten between requests: in production every request is a new
        // process, but a feature test reuses the application and Sanctum memoises
        // the resolved user.
        $this->app['auth']->forgetGuards();

        return $this->withHeader('Authorization', 'Bearer '.$this->token);
    }

    public function test_the_profile_endpoint_returns_the_signed_in_customer(): void
    {
        $this->asRahul()->getJson('/api/v1/customer/profile')
            ->assertOk()
            ->assertJsonPath('data.id', $this->rahul->uuid)
            ->assertJsonPath('data.first_name', 'Rahul')
            ->assertJsonPath('data.phone', '+919999900101')
            ->assertJsonPath('data.phone_verified', true)
            ->assertJsonPath('data.email_verified', false);
    }

    public function test_it_is_unreachable_without_a_token(): void
    {
        $this->getJson('/api/v1/customer/profile')
            ->assertStatus(401)
            ->assertJsonPath('error.code', 'UNAUTHENTICATED');

        $this->app['auth']->forgetGuards();
        $this->patchJson('/api/v1/customer/profile', ['first_name' => 'Mallory'])
            ->assertStatus(401);

        $this->assertSame('Rahul', $this->rahul->fresh()->first_name);
    }

    public function test_the_profile_never_carries_credential_material(): void
    {
        $body = $this->asRahul()->getJson('/api/v1/customer/profile')->json('data');

        foreach (['password', 'remember_token', 'role', 'is_active'] as $forbidden) {
            $this->assertArrayNotHasKey($forbidden, $body);
        }

        // The uuid, never the sequential key — which is enumerable and discloses
        // how many customers exist.
        $this->assertNotSame((string) $this->rahul->getKey(), $body['id']);
    }

    public function test_a_customer_can_change_their_own_name_and_email(): void
    {
        $this->asRahul()->patchJson('/api/v1/customer/profile', [
            'first_name' => 'Rahul',
            'last_name' => 'S. Sharma',
            'email' => 'rahul.updated@foodonthego.example',
        ])
            ->assertOk()
            ->assertJsonPath('data.full_name', 'Rahul S. Sharma')
            ->assertJsonPath('data.email', 'rahul.updated@foodonthego.example');

        $this->assertDatabaseHas('users', [
            'id' => $this->rahul->getKey(),
            'last_name' => 'S. Sharma',
        ]);
    }

    public function test_the_verified_phone_cannot_be_changed_through_the_profile_form(): void
    {
        $this->asRahul()->patchJson('/api/v1/customer/profile', [
            'first_name' => 'Rahul',
            'phone_e164' => '+919999999999',
            'phone' => '+919999999999',
            'phone_verified_at' => null,
        ])->assertOk();

        $fresh = $this->rahul->fresh();

        // The number is identity, established by an OTP in Module 03. Changing it
        // will one day be its own re-verification flow; it is never a PATCH.
        $this->assertSame('+919999900101', $fresh->phone_e164);
        $this->assertNotNull($fresh->phone_verified_at);
    }

    public function test_role_and_status_cannot_be_escalated_through_the_profile_form(): void
    {
        $this->asRahul()->patchJson('/api/v1/customer/profile', [
            'first_name' => 'Rahul',
            'role' => Role::SuperAdmin->value,
            'status' => AccountStatus::Active->value,
            'is_active' => true,
            'uuid' => 'attacker-chosen-uuid',
            'id' => 424242,
        ])->assertOk();

        $fresh = $this->rahul->fresh();

        $this->assertSame(Role::Customer, $fresh->role);
        $this->assertSame($this->rahul->uuid, $fresh->uuid);
        $this->assertSame($this->rahul->getKey(), $fresh->getKey());
    }

    public function test_an_unknown_field_is_ignored_rather_than_rejected(): void
    {
        // Rejecting would tell a prober which field names the server knows about.
        $this->asRahul()->patchJson('/api/v1/customer/profile', [
            'first_name' => 'Rahul',
            'wallet_balance' => 100000,
        ])->assertOk();

        $this->assertSame('Rahul', $this->rahul->fresh()->first_name);
    }

    public function test_a_blank_first_name_is_rejected(): void
    {
        foreach (['', '   ', "\t"] as $blank) {
            $this->app['auth']->forgetGuards();
            $this->asRahul()->patchJson('/api/v1/customer/profile', ['first_name' => $blank])
                ->assertStatus(422)
                ->assertJsonPath('error.code', 'VALIDATION_FAILED');
        }

        $this->assertSame('Rahul', $this->rahul->fresh()->first_name);
    }

    public function test_a_name_is_trimmed_before_it_is_stored(): void
    {
        $this->asRahul()->patchJson('/api/v1/customer/profile', ['first_name' => '  Rahul  '])
            ->assertOk()
            ->assertJsonPath('data.first_name', 'Rahul');
    }

    public function test_unicode_and_punctuated_names_are_accepted(): void
    {
        foreach (['José', "O'Brien", 'Aarav-Krishna', 'प्रिया', '李'] as $name) {
            $this->app['auth']->forgetGuards();
            $this->asRahul()->patchJson('/api/v1/customer/profile', ['first_name' => $name])
                ->assertOk()
                ->assertJsonPath('data.first_name', $name);
        }
    }

    public function test_a_name_with_no_letters_at_all_is_rejected(): void
    {
        foreach (['12345', '...', '!!!'] as $notAName) {
            $this->app['auth']->forgetGuards();
            $this->asRahul()->patchJson('/api/v1/customer/profile', ['first_name' => $notAName])
                ->assertStatus(422);
        }
    }

    public function test_an_over_long_name_is_rejected(): void
    {
        $this->asRahul()->patchJson('/api/v1/customer/profile', [
            'first_name' => str_repeat('A', 200),
        ])->assertStatus(422);
    }

    public function test_a_malformed_email_is_rejected_and_a_blank_one_clears_it(): void
    {
        $this->asRahul()->patchJson('/api/v1/customer/profile', ['email' => 'not-an-email'])
            ->assertStatus(422);

        $this->app['auth']->forgetGuards();
        $this->asRahul()->patchJson('/api/v1/customer/profile', ['email' => ''])
            ->assertOk()
            ->assertJsonPath('data.email', null);
    }

    public function test_an_email_already_on_another_account_is_refused(): void
    {
        CustomerFactory::ananya();

        $this->asRahul()->patchJson('/api/v1/customer/profile', [
            'email' => 'ananya.test@foodonthego.example',
        ])->assertStatus(422);
    }

    public function test_changing_the_email_never_claims_it_is_verified(): void
    {
        $this->asRahul()->patchJson('/api/v1/customer/profile', [
            'email' => 'brand.new@foodonthego.example',
        ])
            ->assertOk()
            // There is no email verification flow, so the API must not imply one.
            ->assertJsonPath('data.email_verified', false);
    }

    public function test_markup_in_a_name_is_stored_and_returned_verbatim(): void
    {
        $payload = "<script>alert('x')</script>";

        $this->asRahul()->patchJson('/api/v1/customer/profile', ['first_name' => $payload])
            ->assertOk()
            ->assertJsonPath('data.first_name', $payload);

        $this->assertDatabaseHas('users', ['first_name' => $payload]);
    }

    public function test_a_sql_shaped_payload_is_data_not_a_query(): void
    {
        $payload = "Rahul'; DROP TABLE users; --";

        $this->asRahul()->patchJson('/api/v1/customer/profile', ['first_name' => $payload])
            ->assertOk();

        // The table is still there, and the string was stored as typed.
        $this->assertDatabaseHas('users', ['first_name' => $payload]);
        $this->assertDatabaseCount('users', 1);
    }

    public function test_a_restaurant_account_cannot_reach_the_customer_profile(): void
    {
        $owner = CustomerFactory::make(
            'Owner', null, '+919999900199', 'owner@example.com',
            role: Role::RestaurantOwner,
        );
        $token = $owner->createToken('test', ['restaurant'])->plainTextToken;

        $this->app['auth']->forgetGuards();
        $this->withHeader('Authorization', 'Bearer '.$token)
            ->getJson('/api/v1/customer/profile')
            ->assertStatus(403)
            ->assertJsonPath('error.code', 'FORBIDDEN');
    }

    public function test_the_response_follows_the_standard_envelope(): void
    {
        $this->asRahul()->getJson('/api/v1/customer/profile')
            ->assertJsonStructure(['data' => ['id', 'first_name', 'phone'], 'meta' => ['request_id']]);
    }
}
