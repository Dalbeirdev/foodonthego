<?php

declare(strict_types=1);

namespace Tests\Feature\Logging;

use App\Enums\AccountStatus;
use App\Enums\Role;
use App\Models\User;
use App\Services\Auth\CustomerAuthService;
use App\Support\RequestContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * Who the log line says was making the request.
 *
 * WRITTEN BECAUSE ITS ABSENCE HID A BUG FOR SIXTEEN MODULES. `LogApiRequests`
 * recorded the actor's role with `is_string($user->role ?? null) ? $user->role
 * : null`, which was correct while `users.role` was a string column and became
 * permanently false the moment it was cast to a backed enum. Every
 * authenticated request since has logged `actor_role: null`.
 *
 * Nothing failed. 1,301 tests passed throughout, because not one of them
 * asserted what a log line contains -- the branch was dead rather than wrong,
 * and dead code is invisible to a test suite by definition. Static analysis
 * (KI-003) found it on its first run.
 *
 * So this file exists to make the same class of defect loud next time: the
 * actor is part of the audit trail, and an audit trail that silently forgets
 * who did something is worse than one that was never claimed.
 */
final class ActorContextTest extends TestCase
{
    use RefreshDatabase;

    protected function tearDown(): void
    {
        RequestContext::reset();
        parent::tearDown();
    }

    private function customer(): User
    {
        return User::create([
            'uuid' => (string) Str::uuid(),
            'name' => 'Ravi Kumar',
            'first_name' => 'Ravi',
            'last_name' => 'Kumar',
            'phone_e164' => '+919876500011',
            'phone_verified_at' => now(),
            'role' => Role::Customer->value,
            'status' => AccountStatus::Active->value,
        ]);
    }

    public function test_an_authenticated_request_records_the_actors_role(): void
    {
        $customer = $this->customer();

        $token = $this->app->make(CustomerAuthService::class)
            ->issueSession($customer)->plainTextToken;

        $this->app['auth']->forgetGuards();

        $this->withHeader('Authorization', 'Bearer '.$token)
            ->getJson('/api/v1/customer/me')
            ->assertOk();

        // The value, not the enum instance: the log envelope is JSON, and an
        // enum serialised by accident would land as an object or a fatal
        // depending on the encoder's mood.
        $this->assertSame(
            Role::Customer->value,
            RequestContext::actorRole(),
            'The request logged no actor role for an authenticated customer.',
        );

        $this->assertSame(
            (string) $customer->getKey(),
            RequestContext::actorId(),
        );
    }

    public function test_an_unauthenticated_request_records_no_actor(): void
    {
        // THE CONTROL. Without it, a setActor() that hardcoded 'customer'
        // would pass the test above. An anonymous request must leave both
        // fields empty rather than inheriting whoever came before.
        RequestContext::reset();

        $this->getJson('/api/v1/customer/me')->assertStatus(401);

        $this->assertNull(RequestContext::actorRole());
        $this->assertNull(RequestContext::actorId());
    }
}
