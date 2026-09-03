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

    public function test_an_account_suspended_after_sign_in_keeps_its_token_until_it_is_revoked(): void
    {
        // Documents the current behaviour honestly: Sanctum tokens are bearer
        // credentials and this module does not re-check status per request. The
        // admin tooling that suspends an account is responsible for deleting its
        // tokens, and that module does not exist yet — recorded as KI-004.
        $this->customer->forceFill(['status' => AccountStatus::Suspended->value])->save();

        $this->asCustomer()->getJson('/api/v1/customer/me')->assertOk();

        // Revoking the tokens is what actually ends the session today.
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
