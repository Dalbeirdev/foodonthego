<?php

declare(strict_types=1);

namespace App\Policies;

use App\Enums\TenantRole;
use App\Models\Restaurant;
use App\Models\User;
use App\Services\Tenancy\TenantAccessService;

/**
 * What somebody may do to a restaurant they can reach.
 *
 * The policy layer this project said would arrive with the first resource more
 * than one role can reach ([07-security.md]). A restaurant is that resource.
 *
 * **Every method here delegates the "may they reach it at all" question to
 * {@see TenantAccessService}** and only decides the depth. That split matters:
 * reachability is the tenant boundary and must have exactly one implementation,
 * while depth is a per-action judgement that will grow as the operator module
 * does. Writing the boundary check again in each method is how one of them ends
 * up subtly different.
 *
 * There is no `before()` hook granting everything to an administrator. That hook
 * is the usual way "super admin sees all" becomes true by omission, and this
 * platform requires the breadth to be an explicit grant instead — so a super
 * administrator arrives here like everybody else and is allowed by a row.
 */
final class RestaurantPolicy
{
    public function __construct(
        private readonly TenantAccessService $access,
    ) {}

    /** Seeing the restaurant at all: its dashboard, its name, its status. */
    public function view(User $user, Restaurant $restaurant): bool
    {
        return $this->access->allows($user, $restaurant, TenantRole::Staff);
    }

    /**
     * Changing operational settings — accepting orders, preparation times.
     *
     * Manager and above. Staff can read the dashboard; turning the restaurant
     * off to customers is not a shift-level decision.
     */
    public function update(User $user, Restaurant $restaurant): bool
    {
        return $this->access->allows($user, $restaurant, TenantRole::Manager);
    }

    /** Menu, prices and availability. Manager and above. */
    public function manageMenu(User $user, Restaurant $restaurant): bool
    {
        return $this->access->allows($user, $restaurant, TenantRole::Manager);
    }

    /**
     * Adding and removing colleagues.
     *
     * Owner only. A manager who could assign staff could assign themselves an
     * owner's capability, and then the ordering in {@see TenantRole} would be
     * decoration rather than a rule.
     */
    public function manageStaff(User $user, Restaurant $restaurant): bool
    {
        return $this->access->allows($user, $restaurant, TenantRole::Owner);
    }

    /** Settlements, commission, bank details. Owner only. */
    public function viewFinancials(User $user, Restaurant $restaurant): bool
    {
        return $this->access->allows($user, $restaurant, TenantRole::Owner);
    }
}
