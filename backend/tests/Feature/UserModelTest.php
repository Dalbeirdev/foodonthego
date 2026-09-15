<?php

declare(strict_types=1);

namespace Tests\Feature;

use App\Enums\Role;
use App\Models\User;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Establishes the database conventions later modules inherit
 * (docs/06-database-conventions.md).
 */
final class UserModelTest extends TestCase
{
    use RefreshDatabase;

    private function makeUser(array $attributes = []): User
    {
        return User::create(array_merge([
            'name' => 'Rahul Sharma',
            'email' => 'rahul.sharma@example.test',
            'password' => 'a-long-development-password',
            'role' => Role::Customer,
        ], $attributes));
    }

    public function test_a_uuid_is_assigned_without_the_caller_having_to_remember(): void
    {
        $user = $this->makeUser();

        $this->assertNotNull($user->uuid);
        $this->assertMatchesRegularExpression(
            '/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i',
            $user->uuid,
        );
    }

    public function test_the_api_route_key_is_the_uuid_not_the_sequential_id(): void
    {
        // Sequential ids in URLs let anyone count our customers and walk to the next.
        $this->assertSame('uuid', $this->makeUser()->getRouteKeyName());
    }

    public function test_the_password_is_hashed_and_hidden_from_serialisation(): void
    {
        $user = $this->makeUser();

        $this->assertNotSame('a-long-development-password', $user->password);
        $this->assertArrayNotHasKey('password', $user->toArray());
        $this->assertArrayNotHasKey('remember_token', $user->toArray());
    }

    public function test_the_role_round_trips_as_an_enum(): void
    {
        $owner = $this->makeUser(['email' => 'priya.verma@example.test', 'role' => Role::RestaurantOwner]);

        $this->assertInstanceOf(Role::class, $owner->fresh()->role);
        $this->assertTrue($owner->hasRole(Role::RestaurantOwner));
        $this->assertFalse($owner->hasRole(Role::Customer, Role::Admin));
    }

    public function test_a_deleted_user_is_recoverable_rather_than_erased(): void
    {
        // Orders and audit rows keep pointing at this user; a hard delete would
        // orphan an audit trail we are obliged to keep.
        $user = $this->makeUser();
        $user->delete();

        $this->assertSoftDeleted('users', ['id' => $user->id]);
        $this->assertNotNull(User::withTrashed()->find($user->id));
    }

    public function test_email_is_unique(): void
    {
        $this->makeUser();

        $this->expectException(QueryException::class);
        $this->makeUser();
    }

    public function test_a_new_account_defaults_to_the_least_privileged_role(): void
    {
        $user = User::create([
            'name' => 'Someone New',
            'email' => 'new@example.test',
            'password' => 'a-long-development-password',
        ]);

        $this->assertSame(Role::Customer, $user->fresh()->role);
    }
}
