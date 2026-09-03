<?php

declare(strict_types=1);

namespace Tests\Unit;

use App\Enums\Role;
use PHPUnit\Framework\TestCase;

final class RoleTest extends TestCase
{
    public function test_every_role_required_by_the_specification_exists(): void
    {
        $expected = [
            'customer', 'restaurant_owner', 'restaurant_manager',
            'restaurant_staff', 'support_agent', 'admin', 'super_admin',
        ];

        $this->assertSame($expected, Role::values());
    }

    public function test_restaurant_and_platform_roles_are_disjoint(): void
    {
        foreach (Role::cases() as $role) {
            $this->assertFalse(
                $role->isRestaurantRole() && $role->isPlatformRole(),
                "{$role->value} claims to be both a restaurant and a platform role",
            );
        }
    }

    public function test_a_customer_is_neither_a_restaurant_nor_a_platform_role(): void
    {
        $this->assertFalse(Role::Customer->isRestaurantRole());
        $this->assertFalse(Role::Customer->isPlatformRole());
    }

    public function test_each_role_is_routed_to_exactly_one_surface(): void
    {
        $this->assertSame('mobile', Role::Customer->surface());
        $this->assertSame('restaurant', Role::RestaurantOwner->surface());
        $this->assertSame('restaurant', Role::RestaurantStaff->surface());
        $this->assertSame('admin', Role::SupportAgent->surface());
        $this->assertSame('admin', Role::SuperAdmin->surface());
    }

    public function test_every_role_has_a_human_label(): void
    {
        foreach (Role::cases() as $role) {
            $this->assertNotSame('', $role->label());
        }
    }
}
