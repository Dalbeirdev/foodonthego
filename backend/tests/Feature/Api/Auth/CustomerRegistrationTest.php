<?php

declare(strict_types=1);

namespace Tests\Feature\Api\Auth;

use App\Enums\AccountStatus;
use App\Enums\Role;
use App\Models\User;
use App\Services\Otp\OtpDeliveryProvider;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\Str;
use Tests\Support\RecordingOtpProvider;
use Tests\TestCase;

final class CustomerRegistrationTest extends TestCase
{
    use RefreshDatabase;

    private RecordingOtpProvider $provider;

    protected function setUp(): void
    {
        parent::setUp();

        $this->provider = new RecordingOtpProvider;
        $this->app->instance(OtpDeliveryProvider::class, $this->provider);
    }

    /** Completes a real OTP round trip and returns the registration token. */
    private function registrationTokenFor(string $phone = '9876543210'): string
    {
        RateLimiter::clear('otp:phone:'.hash('sha256', '+91'.ltrim($phone, '+91')));
        $this->postJson('/api/v1/auth/customer/otp/request', ['phone' => $phone])->assertOk();

        return $this->postJson('/api/v1/auth/customer/otp/verify', [
            'phone' => $phone,
            'otp' => $this->provider->lastCode(),
        ])->assertOk()->json('data.registration_token');
    }

    public function test_registration_creates_an_account_and_returns_a_session(): void
    {
        $token = $this->registrationTokenFor();

        $response = $this->postJson('/api/v1/auth/customer/register', [
            'registration_token' => $token,
            'first_name' => 'Ravi',
            'last_name' => 'Kumar',
            'email' => 'ravi@example.com',
        ]);

        $response->assertCreated()
            ->assertJsonPath('data.token_type', 'Bearer')
            ->assertJsonPath('data.user.first_name', 'Ravi')
            ->assertJsonPath('data.user.phone', '+919876543210')
            ->assertJsonPath('data.user.phone_verified', true)
            // Typing an address is not owning it.
            ->assertJsonPath('data.user.email_verified', false);

        $this->assertDatabaseHas('users', [
            'phone_e164' => '+919876543210',
            'role' => Role::Customer->value,
            'status' => AccountStatus::Active->value,
        ]);
    }

    public function test_the_account_is_created_for_the_verified_number_and_not_one_supplied_by_the_caller(): void
    {
        $token = $this->registrationTokenFor('9876543210');

        // The attack: verify a number you control, then name somebody else's.
        $this->postJson('/api/v1/auth/customer/register', [
            'registration_token' => $token,
            'first_name' => 'Mallory',
            'phone' => '+919812345678',
            'phone_e164' => '+919812345678',
        ])->assertCreated()->assertJsonPath('data.user.phone', '+919876543210');

        $this->assertDatabaseMissing('users', ['phone_e164' => '+919812345678']);
    }

    public function test_registration_without_a_token_is_refused(): void
    {
        $this->postJson('/api/v1/auth/customer/register', ['first_name' => 'Ravi'])
            ->assertStatus(422)
            ->assertJsonPath('error.code', 'VALIDATION_FAILED');

        $this->assertDatabaseCount('users', 0);
    }

    public function test_a_forged_token_is_refused(): void
    {
        $this->postJson('/api/v1/auth/customer/register', [
            'registration_token' => 'clearly-not-a-real-token',
            'first_name' => 'Mallory',
        ])
            ->assertStatus(401)
            ->assertJsonPath('error.code', 'REGISTRATION_TOKEN_INVALID');

        $this->assertDatabaseCount('users', 0);
    }

    public function test_an_expired_token_is_refused_with_its_own_code(): void
    {
        config(['foodonthego.otp.registration_token_ttl_seconds' => 900]);
        $token = $this->registrationTokenFor();

        $this->travel(901)->seconds();

        // A distinct code so the client can say "that took too long, start again"
        // rather than the generic "something is wrong".
        $this->postJson('/api/v1/auth/customer/register', [
            'registration_token' => $token,
            'first_name' => 'Ravi',
        ])
            ->assertStatus(401)
            ->assertJsonPath('error.code', 'REGISTRATION_TOKEN_EXPIRED');
    }

    public function test_a_first_name_is_required_and_nothing_else_is(): void
    {
        $token = $this->registrationTokenFor();

        $this->postJson('/api/v1/auth/customer/register', [
            'registration_token' => $token,
            'first_name' => '  ',
        ])->assertStatus(422);

        $this->postJson('/api/v1/auth/customer/register', [
            'registration_token' => $token,
            'first_name' => 'Ravi',
        ])->assertCreated()->assertJsonPath('data.user.last_name', null);
    }

    public function test_a_malformed_email_is_rejected_but_a_blank_one_is_fine(): void
    {
        $token = $this->registrationTokenFor();

        $this->postJson('/api/v1/auth/customer/register', [
            'registration_token' => $token,
            'first_name' => 'Ravi',
            'email' => 'not-an-email',
        ])->assertStatus(422)->assertJsonPath('error.code', 'VALIDATION_FAILED');

        $this->postJson('/api/v1/auth/customer/register', [
            'registration_token' => $token,
            'first_name' => 'Ravi',
            'email' => null,
        ])->assertCreated();
    }

    public function test_names_are_stored_as_typed_and_not_executed_anywhere(): void
    {
        $token = $this->registrationTokenFor();

        $this->postJson('/api/v1/auth/customer/register', [
            'registration_token' => $token,
            'first_name' => "<script>alert('x')</script>",
        ])->assertCreated();

        // Storage is verbatim — escaping is the renderer's job, and mangling input
        // on the way in loses data for anyone whose name contains an apostrophe.
        $this->assertDatabaseHas('users', ['first_name' => "<script>alert('x')</script>"]);
    }

    public function test_a_retried_registration_returns_the_same_account_rather_than_a_second_one(): void
    {
        $token = $this->registrationTokenFor();

        $first = $this->postJson('/api/v1/auth/customer/register', [
            'registration_token' => $token,
            'first_name' => 'Ravi',
        ])->assertCreated()->json('data.user.id');

        // A lost response on a patchy connection, or a double tap.
        $second = $this->postJson('/api/v1/auth/customer/register', [
            'registration_token' => $token,
            'first_name' => 'Ravi',
        ])->assertCreated()->json('data.user.id');

        $this->assertSame($first, $second);
        $this->assertDatabaseCount('users', 1);
    }

    public function test_registration_never_downgrades_an_existing_non_customer_account(): void
    {
        // A restaurant owner whose personal number is the same. Registering as a
        // customer must not touch their existing account.
        $owner = User::create([
            'uuid' => (string) Str::uuid(),
            'name' => 'Owner',
            'first_name' => 'Owner',
            'email' => 'owner@example.com',
            'phone_e164' => '+919812345678',
            'role' => Role::RestaurantOwner->value,
            'status' => AccountStatus::Active->value,
            'password' => bcrypt('secret'),
        ]);

        $token = $this->registrationTokenFor('9812345678');

        // The unique index on phone_e164 means this cannot create a second row,
        // and the owner's role is untouched either way.
        $this->postJson('/api/v1/auth/customer/register', [
            'registration_token' => $token,
            'first_name' => 'Ravi',
        ]);

        $this->assertSame(Role::RestaurantOwner, $owner->fresh()->role);
        $this->assertDatabaseCount('users', 1);
    }

    public function test_the_issued_token_actually_works_against_a_protected_endpoint(): void
    {
        $token = $this->registrationTokenFor();

        $access = $this->postJson('/api/v1/auth/customer/register', [
            'registration_token' => $token,
            'first_name' => 'Ravi',
        ])->assertCreated()->json('data.access_token');

        $this->withHeader('Authorization', 'Bearer '.$access)
            ->getJson('/api/v1/customer/me')
            ->assertOk()
            ->assertJsonPath('data.first_name', 'Ravi');
    }
}
