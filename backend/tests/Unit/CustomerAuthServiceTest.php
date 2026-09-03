<?php

declare(strict_types=1);

namespace Tests\Unit;

use App\Enums\AccountStatus;
use App\Enums\ApiErrorCode;
use App\Enums\Role;
use App\Exceptions\ApiException;
use App\Models\User;
use App\Services\Auth\CustomerAuthService;
use App\Support\Phone\PhoneNumber;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\TestCase;

final class CustomerAuthServiceTest extends TestCase
{
    use RefreshDatabase;

    private CustomerAuthService $service;

    private PhoneNumber $phone;

    protected function setUp(): void
    {
        parent::setUp();

        $this->service = $this->app->make(CustomerAuthService::class);
        $this->phone = PhoneNumber::fromE164('+919876543210');
    }

    public function test_registration_creates_a_verified_active_customer(): void
    {
        $user = $this->service->register($this->phone, 'Ravi', 'Kumar', 'ravi@example.com');

        $this->assertSame('+919876543210', $user->phone_e164);
        $this->assertSame(Role::Customer, $user->role);
        $this->assertSame(AccountStatus::Active, $user->status);
        $this->assertNotNull($user->phone_verified_at);
    }

    public function test_a_customer_account_has_no_password_at_all(): void
    {
        $user = $this->service->register($this->phone, 'Ravi', null, null);

        // Phone-only sign-in means there is nothing to stuff, phish or leak. A
        // stored placeholder hash would quietly reintroduce a password surface.
        $this->assertNull($user->fresh()->password);
    }

    public function test_verifying_a_phone_does_not_verify_an_email(): void
    {
        $user = $this->service->register($this->phone, 'Ravi', null, 'ravi@example.com');

        // Owning a phone says nothing about owning the address typed next to it.
        $this->assertNull($user->email_verified_at);
    }

    public function test_the_optional_fields_really_are_optional(): void
    {
        $user = $this->service->register($this->phone, 'Ravi', null, null);

        $this->assertNull($user->last_name);
        $this->assertNull($user->email);
        $this->assertSame('Ravi', $user->displayName());
    }

    public function test_lookup_is_scoped_to_customers(): void
    {
        // A restaurant owner sharing a number must not be returned to the
        // customer sign-in path — that would hand a customer session to a
        // restaurant account.
        User::create([
            'uuid' => (string) Str::uuid(),
            'name' => 'Owner',
            'first_name' => 'Owner',
            'email' => 'owner@example.com',
            'phone_e164' => $this->phone->e164,
            'role' => Role::RestaurantOwner->value,
            'status' => AccountStatus::Active->value,
            'password' => bcrypt('secret'),
        ]);

        $this->assertNull($this->service->findCustomerByPhone($this->phone));
    }

    public function test_a_session_is_issued_with_the_customer_ability_only(): void
    {
        $user = $this->service->register($this->phone, 'Ravi', null, null);

        $token = $this->service->issueSession($user);

        $this->assertSame(['customer'], $token->accessToken->abilities);
        $this->assertNotNull($token->accessToken->expires_at);
        $this->assertNotNull($user->fresh()->last_login_at);
    }

    public function test_the_plaintext_token_is_never_stored(): void
    {
        $user = $this->service->register($this->phone, 'Ravi', null, null);
        $token = $this->service->issueSession($user);

        [, $plain] = explode('|', $token->plainTextToken, 2);

        // The database holds a hash. A dumped personal_access_tokens table must
        // not be a set of working credentials.
        $this->assertDatabaseMissing('personal_access_tokens', ['token' => $plain]);
        $this->assertSame(hash('sha256', $plain), $token->accessToken->token);
    }

    public function test_a_suspended_account_cannot_get_a_session_even_with_a_correct_code(): void
    {
        $user = $this->service->register($this->phone, 'Ravi', null, null);
        $user->forceFill(['status' => AccountStatus::Suspended->value])->save();

        try {
            $this->service->issueSession($user->fresh());
            $this->fail('A suspended account was given a session.');
        } catch (ApiException $e) {
            $this->assertSame(ApiErrorCode::AccountSuspended, $e->errorCode);
        }

        $this->assertDatabaseCount('personal_access_tokens', 0);
    }

    public function test_a_disabled_account_cannot_get_a_session(): void
    {
        $user = $this->service->register($this->phone, 'Ravi', null, null);
        $user->forceFill(['status' => AccountStatus::Disabled->value])->save();

        try {
            $this->service->issueSession($user->fresh());
            $this->fail('A disabled account was given a session.');
        } catch (ApiException $e) {
            $this->assertSame(ApiErrorCode::AccountDisabled, $e->errorCode);
        }
    }

    public function test_a_deleted_account_reports_as_disabled_rather_than_confirming_deletion(): void
    {
        $user = $this->service->register($this->phone, 'Ravi', null, null);
        $user->forceFill(['status' => AccountStatus::Deleted->value])->save();

        try {
            $this->service->issueSession($user->fresh());
            $this->fail('A deleted account was given a session.');
        } catch (ApiException $e) {
            // "Deleted" would confirm to whoever holds the number that an account
            // once existed. Disabled says only that this is not usable.
            $this->assertSame(ApiErrorCode::AccountDisabled, $e->errorCode);
        }
    }

    public function test_the_profile_projection_exposes_the_uuid_and_not_the_primary_key(): void
    {
        $user = $this->service->register($this->phone, 'Ravi', 'Kumar', 'ravi@example.com');

        $profile = $user->toCustomerProfile();

        $this->assertSame($user->uuid, $profile['id']);
        $this->assertNotSame($user->getKey(), $profile['id']);
        $this->assertArrayNotHasKey('password', $profile);
        $this->assertTrue($profile['phone_verified']);
        $this->assertFalse($profile['email_verified']);
    }

    public function test_registering_a_number_that_already_has_an_account_returns_the_existing_one(): void
    {
        $first = $this->service->register($this->phone, 'Ravi', null, null);

        // The unique index turns the race into this, rather than a 500 or a
        // second account for the same person.
        $second = $this->service->register($this->phone, 'Someone', 'Else', null);

        $this->assertSame($first->getKey(), $second->getKey());
        $this->assertSame('Ravi', $second->fresh()->first_name);
        $this->assertDatabaseCount('users', 1);
    }
}
