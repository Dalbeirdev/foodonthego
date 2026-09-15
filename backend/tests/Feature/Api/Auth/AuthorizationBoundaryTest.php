<?php

declare(strict_types=1);

namespace Tests\Feature\Api\Auth;

use App\Enums\AccountStatus;
use App\Enums\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Route;
use Illuminate\Support\Str;
use Illuminate\Testing\TestResponse;
use Tests\TestCase;

/**
 * A customer token is a valid credential. It is not a licence to reach every
 * endpoint.
 *
 * The restaurant and admin APIs arrive in later modules, so the routes exercised
 * here are registered by the test itself — with exactly the middleware stack those
 * modules will use. That is the point: this proves the *gate* works before there
 * is anything behind it, so the first restaurant route to be written inherits a
 * guard that has been tested rather than one that has only been intended.
 */
final class AuthorizationBoundaryTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        Route::middleware(['api', 'auth:sanctum', 'role:restaurant_owner,restaurant_manager,restaurant_staff'])
            ->get('/api/v1/test-only/restaurant/orders', static fn (): array => ['data' => 'restaurant']);

        Route::middleware(['api', 'auth:sanctum', 'role:admin,super_admin'])
            ->get('/api/v1/test-only/admin/users', static fn (): array => ['data' => 'admin']);

        Route::middleware(['api', 'auth:sanctum', 'abilities:restaurant'])
            ->get('/api/v1/test-only/restaurant/ability', static fn (): array => ['data' => 'ability']);
    }

    private function user(Role $role, array $abilities): string
    {
        $user = User::create([
            'uuid' => (string) Str::uuid(),
            'name' => $role->label(),
            'first_name' => $role->label(),
            'email' => Str::uuid().'@example.com',
            'phone_e164' => '+9198'.random_int(10000000, 99999999),
            'role' => $role->value,
            'status' => AccountStatus::Active->value,
        ]);

        return $user->createToken('test', $abilities)->plainTextToken;
    }

    private function getAs(string $uri, string $token): TestResponse
    {
        $this->app['auth']->forgetGuards();

        return $this->withHeader('Authorization', 'Bearer '.$token)->getJson($uri);
    }

    public function test_a_customer_token_cannot_reach_restaurant_endpoints(): void
    {
        $token = $this->user(Role::Customer, ['customer']);

        $this->getAs('/api/v1/test-only/restaurant/orders', $token)
            ->assertStatus(403)
            ->assertJsonPath('error.code', 'FORBIDDEN');
    }

    public function test_a_customer_token_cannot_reach_admin_endpoints(): void
    {
        $token = $this->user(Role::Customer, ['customer']);

        $this->getAs('/api/v1/test-only/admin/users', $token)
            ->assertStatus(403)
            ->assertJsonPath('error.code', 'FORBIDDEN');
    }

    public function test_a_customer_token_cannot_reach_an_endpoint_requiring_another_ability(): void
    {
        $token = $this->user(Role::Customer, ['customer']);

        // Second, independent gate: even if a role check were forgotten on some
        // future route, the token itself was never minted for that work.
        $this->getAs('/api/v1/test-only/restaurant/ability', $token)->assertStatus(403);
    }

    public function test_a_restaurant_token_cannot_reach_the_customer_profile(): void
    {
        $token = $this->user(Role::RestaurantOwner, ['restaurant']);

        // Symmetry matters: the boundary is not "customers are less trusted", it
        // is that each surface only serves its own accounts.
        $this->getAs('/api/v1/customer/me', $token)
            ->assertStatus(403)
            ->assertJsonPath('error.code', 'FORBIDDEN');
    }

    public function test_an_admin_token_cannot_reach_the_customer_profile_either(): void
    {
        $token = $this->user(Role::SuperAdmin, ['admin']);

        // A super admin is not an exception. Impersonation, if it is ever built,
        // will be an explicit feature with its own audit trail — not a side
        // effect of a missing role check.
        $this->getAs('/api/v1/customer/me', $token)->assertStatus(403);
    }

    public function test_a_role_carrying_token_still_needs_the_customer_ability(): void
    {
        // Right role, wrong ability: a token minted for something else must not
        // be usable on the customer app's endpoints.
        $token = $this->user(Role::Customer, ['some-other-ability']);

        $this->getAs('/api/v1/customer/me', $token)->assertStatus(403);
    }

    public function test_the_gate_that_fires_first_is_authentication(): void
    {
        // No credential at all is 401, not 403 — the distinction tells a client
        // whether to re-authenticate or to give up.
        $this->app['auth']->forgetGuards();
        $this->getJson('/api/v1/test-only/admin/users')
            ->assertStatus(401)
            ->assertJsonPath('error.code', 'UNAUTHENTICATED');
    }

    public function test_the_forbidden_message_does_not_describe_what_lies_behind_it(): void
    {
        $token = $this->user(Role::Customer, ['customer']);

        $message = $this->getAs('/api/v1/test-only/admin/users', $token)->json('error.message');

        // "You need the super_admin role" is a map of the privilege model.
        foreach (['super_admin', 'admin', 'restaurant_owner', 'role:'] as $leak) {
            $this->assertStringNotContainsString($leak, $message);
        }
    }
}
