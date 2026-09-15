<?php

declare(strict_types=1);

namespace App\Enums;

/**
 * What somebody may do *inside* one restaurant.
 *
 * Deliberately not `App\Enums\Role`. That enum answers "which surface does this
 * person sign in to"; this one answers "and what may they do at this particular
 * restaurant". They are different questions, and conflating them is what makes a
 * platform single-tenant by accident: a person who is an owner at one restaurant
 * and a part-time cook at another cannot be described by a single column on
 * `users`, and any model that tries will eventually grant the wrong one.
 *
 * So the tenant role lives on the assignment row, one per (restaurant, user).
 */
enum TenantRole: string
{
    case Owner = 'owner';
    case Manager = 'manager';
    case Staff = 'staff';

    public function label(): string
    {
        return match ($this) {
            self::Owner => 'Owner',
            self::Manager => 'Manager',
            self::Staff => 'Staff',
        };
    }

    /**
     * Whether this role includes another's capabilities.
     *
     * An owner can do anything a manager can, a manager anything staff can. This
     * is an ordering, not a set of independent flags — and it is written once,
     * here, so that a policy method cannot quietly disagree with it.
     */
    public function includes(self $other): bool
    {
        return $this->rank() >= $other->rank();
    }

    private function rank(): int
    {
        return match ($this) {
            self::Owner => 3,
            self::Manager => 2,
            self::Staff => 1,
        };
    }

    /**
     * The platform role a person must hold to be assignable at all.
     *
     * Assignment is not a way around the surface split: somebody whose account is
     * a customer does not become restaurant staff because a row says so. Both are
     * checked, and this is the half that belongs to the assignment.
     */
    public static function assignableTo(Role $role): bool
    {
        return $role->isRestaurantRole();
    }
}
