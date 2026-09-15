<?php

declare(strict_types=1);

namespace Tests\Support;

use App\Enums\Role;
use App\Enums\TenantRole;
use App\Models\PlatformTenantGrant;
use App\Models\Restaurant;
use App\Models\RestaurantMembership;
use App\Models\User;
use Illuminate\Support\Str;

/**
 * Two tenants and the people around them.
 *
 * Assignments and grants are inserted directly rather than through a service,
 * because no service creates them yet — staff management is an operator-module
 * concern. What is under test is whether the *authorisation* layer honours these
 * rows, so writing them by hand is the honest setup.
 */
final class TenancyFixtures
{
    public static function operator(
        string $firstName,
        string $phoneE164,
        Role $role = Role::RestaurantManager,
    ): User {
        return CustomerFactory::make(
            $firstName,
            'Operator',
            $phoneE164,
            Str::lower($firstName).'.test@foodonthego.example',
            role: $role,
        );
    }

    /** Puts [$user] on [$restaurant]'s staff. */
    public static function assign(
        User $user,
        Restaurant $restaurant,
        TenantRole $tenantRole = TenantRole::Manager,
        string $status = 'active',
    ): RestaurantMembership {
        $membership = new RestaurantMembership;

        $membership->forceFill([
            'uuid' => (string) Str::uuid(),
            'restaurant_id' => $restaurant->id,
            'user_id' => $user->id,
            'tenant_role' => $tenantRole->value,
            'status' => $status,
            'granted_at' => now(),
            'revoked_at' => $status === 'revoked' ? now() : null,
        ])->save();

        return $membership;
    }

    /** A platform grant: every tenant, or one named one. */
    public static function grant(
        User $user,
        ?Restaurant $restaurant,
        TenantRole $tenantRole = TenantRole::Staff,
        string $status = 'active',
    ): PlatformTenantGrant {
        $grant = new PlatformTenantGrant;

        $grant->forceFill([
            'uuid' => (string) Str::uuid(),
            'user_id' => $user->id,
            'scope' => $restaurant === null ? 'all' : 'restaurant',
            'restaurant_id' => $restaurant?->id,
            'tenant_role' => $tenantRole->value,
            'status' => $status,
            'granted_at' => now(),
        ])->save();

        return $grant;
    }

    /**
     * A Sanctum token for an operator.
     *
     * No ability, because no operator login exists to define one. The role gate
     * is what keeps these tokens on their own surface, and the tenancy layer is
     * what keeps them in their own restaurant.
     */
    public static function tokenFor(User $user): string
    {
        return $user->createToken('operator-test')->plainTextToken;
    }
}
