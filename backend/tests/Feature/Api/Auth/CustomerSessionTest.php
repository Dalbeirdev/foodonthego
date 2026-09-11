<?php

declare(strict_types=1);

namespace Tests\Feature\Api\Auth;

use App\Enums\AccountStatus;
use App\Enums\Role;
use App\Models\User;
use App\Services\Auth\CustomerAuthService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\TestCase;

final class CustomerSessionTest extends TestCase
{
    use RefreshDatabase;

    private User $customer;

    private string $accessToken;

    protected function setUp(): void
    {
        parent::setUp();

        $this->customer = User::create([
            'uuid' => (string) Str::uuid(),
            'name' => 'Ravi Kumar',
            'first_name' => 'Ravi',
            'last_name' => 'Kumar',
            'email' => 'ravi@example.com',
            'phone_e164' => '+919876543210',
            'phone_verified_at' => now(),
            'role' => Role::Customer->value,
            'status' => AccountStatus::Active->value,
        ]);

        $this->accessToken = $this->app->make(CustomerAuthService::class)
            ->issueSession($this->customer)
            ->plainTextToken;
    }

    private function asCustomer(): self
    {
        return $this->asToken($this->accessToken);
    }

    /**
     * Presents a bearer token on a fresh request cycle.
     *
     * forgetGuards() is not ceremony. In production every request is a new
     * process and the guard resolves the token from the database each time. In a
     * feature test the application object is reused across calls and Sanctum's
     * RequestGuard memoises the user it resolved — so a revoked token would keep
     * working here while failing in production. Clearing the guard makes the test
     * measure the API rather than the harness.
     */
    private function asToken(string $token): self
    {
        $this->app['auth']->forgetGuards();

        return $this->withHeader('Authorization', 'Bearer '.$token);
    }

    public function test_the_profile_endpoint_returns_the_signed_in_customer(): void
    {
        $this->asCustomer()->getJson('/api/v1/customer/me')
            ->assertOk()
            ->assertJsonPath('data.id', $this->customer->uuid)
            ->assertJsonPath('data.full_name', 'Ravi Kumar')
            ->assertJsonPath('data.phone', '+919876543210');
    }

    public function test_the_profile_never_includes_credential_material(): void
    {
        $body = $this->asCustomer()->getJson('/api/v1/customer/me')->json('data');

        foreach (['password', 'remember_token', 'otp_hash', 'token'] as $forbidden) {
            $this->assertArrayNotHasKey($forbidden, $body);
        }

        // The internal primary key is not an identifier clients should ever see:
        // sequential ids are enumerable and disclose how many customers exist.
        $this->assertArrayNotHasKey('user_id', $body);
        $this->assertNotSame((string) $this->customer->getKey(), $body['id']);
    }

    public function test_no_token_is_a_standardized_401(): void
    {
        $this->getJson('/api/v1/customer/me')
            ->assertStatus(401)
            ->assertJsonPath('error.code', 'UNAUTHENTICATED')
            ->assertJsonStructure(['error' => ['code', 'message', 'request_id']]);
    }

    public function test_a_garbage_token_is_a_401_not_a_500(): void
    {
        foreach (['', 'Bearer', 'Bearer nonsense', 'Bearer 1|'.str_repeat('a', 40)] as $header) {
            $this->app['auth']->forgetGuards();
            $this->withHeader('Authorization', $header)
                ->getJson('/api/v1/customer/me')
                ->assertStatus(401)
                ->assertJsonPath('error.code', 'UNAUTHENTICATED');
        }
    }

    public function test_an_expired_token_stops_working(): void
    {
        config(['foodonthego.auth.token_ttl_seconds' => 60]);

        $token = $this->app->make(CustomerAuthService::class)
            ->issueSession($this->customer)->plainTextToken;

        $this->asToken($token)->getJson('/api/v1/customer/me')->assertOk();

        $this->travel(61)->seconds();

        $this->asToken($token)->getJson('/api/v1/customer/me')->assertStatus(401);
    }

    public function test_logout_revokes_the_token_immediately(): void
    {
        $this->asCustomer()->postJson('/api/v1/auth/logout')->assertNoContent();

        $this->asCustomer()->getJson('/api/v1/customer/me')->assertStatus(401);
        $this->assertDatabaseCount('personal_access_tokens', 0);
    }

    public function test_logout_signs_out_one_device_and_not_the_others(): void
    {
        $tablet = $this->app->make(CustomerAuthService::class)
            ->issueSession($this->customer)->plainTextToken;

        $this->asCustomer()->postJson('/api/v1/auth/logout')->assertNoContent();

        // Signing out on a phone must not sign the customer out of a tablet they
        // left at home.
        $this->asToken($tablet)->getJson('/api/v1/customer/me')->assertOk();
    }

    public function test_logout_without_a_token_is_a_401_rather_than_a_silent_success(): void
    {
        $this->postJson('/api/v1/auth/logout')
            ->assertStatus(401)
            ->assertJsonPath('error.code', 'UNAUTHENTICATED');
    }

    public function test_an_account_suspended_after_sign_in_is_refused_on_its_next_request(): void
    {
        // A Sanctum token is a bearer credential, so suspending the account does
        // not reach into the handset holding it. What ends the session is the
        // server refusing to honour it, and the refusal has to happen on the
        // request rather than at sign-in: the account was healthy when it signed
        // in, which is precisely the case that matters.
        $this->customer->forceFill(['status' => AccountStatus::Suspended->value])->save();

        $this->asCustomer()->getJson('/api/v1/customer/me')
            ->assertStatus(403)
            ->assertJsonPath('error.code', 'ACCOUNT_SUSPENDED');
    }

    public function test_a_suspended_account_is_refused_on_the_surface_where_money_is_spent(): void
    {
        // The reason this gap could not stay open. When it was first recorded the
        // customer surface read a profile; it now places orders and pays for
        // them. A suspended account reaching /customer/me is a privacy problem,
        // and a suspended account reaching the ordering surface is a commercial
        // one -- so the boundary is asserted on both rather than on the endpoint
        // that happens to be easiest to call.
        $this->customer->forceFill(['status' => AccountStatus::Suspended->value])->save();

        $this->asCustomer()->getJson('/api/v1/customer/orders')
            ->assertStatus(403)
            ->assertJsonPath('error.code', 'ACCOUNT_SUSPENDED');
    }

    public function test_a_deactivated_account_is_refused_on_its_next_request(): void
    {
        // The other column, and it means something different: `status` is the
        // account's standing, `is_active` is the switch. Both are checked,
        // because an operator who reaches for one of them expects the account to
        // stop working and does not know which one this codebase considers
        // authoritative.
        $this->customer->forceFill(['is_active' => false])->save();

        $this->asCustomer()->getJson('/api/v1/customer/me')
            ->assertStatus(403)
            ->assertJsonPath('error.code', 'ACCOUNT_DISABLED');
    }

    public function test_an_account_in_good_standing_still_reaches_the_api(): void
    {
        // THE CONTROL THAT MAKES THE THREE ABOVE WORTH ANYTHING.
        //
        // A gate that denied every request would pass all three refusal tests
        // and lock out every real customer, so the passing case is asserted
        // beside them rather than assumed.
        //
        // The first draft of this control tried to write `is_active` NULL, on
        // the strength of TenantAccessService::accountUsable()'s note that an
        // unsaved model holds NULL. MySQL refused it: `users.is_active` is
        // `boolean NOT NULL default true`, so a STORED row cannot be NULL and a
        // request -- which always loads its user from the database -- cannot
        // carry one. The note is about an in-memory model and is right about
        // that; it is not a statement about rows. Recorded here because the
        // failing write is what established the difference.
        $this->asCustomer()->getJson('/api/v1/customer/me')->assertOk();
        $this->asCustomer()->getJson('/api/v1/customer/orders')->assertOk();
    }

    public function test_revoking_the_tokens_also_ends_the_session(): void
    {
        // Still true, and still the thing admin tooling should do on suspension:
        // the per-request check stops a suspended account being served, and
        // deleting the tokens stops the credential existing at all. Neither
        // replaces the other.
        $this->customer->tokens()->delete();

        $this->asCustomer()->getJson('/api/v1/customer/me')->assertStatus(401);
    }

    public function test_the_token_is_not_accepted_as_a_query_parameter(): void
    {
        // A token in a URL ends up in access logs, proxy logs and Referer headers.
        $this->app['auth']->forgetGuards();
        $this->getJson('/api/v1/customer/me?token='.$this->accessToken)->assertStatus(401);
        $this->app['auth']->forgetGuards();
        $this->getJson('/api/v1/customer/me?api_token='.$this->accessToken)->assertStatus(401);
    }

    public function test_a_session_cookie_cannot_authenticate_the_api(): void
    {
        // sanctum.guard is deliberately empty: an ambient cookie authenticating a
        // state-changing API route is the shape CSRF exploits.
        $this->actingAs($this->customer, 'web')
            ->getJson('/api/v1/customer/me')
            ->assertStatus(401);
    }
}
