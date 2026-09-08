<?php

declare(strict_types=1);

namespace App\Services\Tenancy;

use App\Enums\AccountStatus;
use App\Enums\TenantRole;
use App\Models\PlatformTenantGrant;
use App\Models\Restaurant;
use App\Models\RestaurantMembership;
use App\Models\User;
use Illuminate\Database\Eloquent\Builder;

/**
 * The one place that answers "may this person reach this restaurant, and as what".
 *
 * Everything else — the policy, the query scopes, the controllers — asks this.
 * Two implementations of a tenancy rule is one implementation and one hole, and
 * the hole is always in the copy somebody wrote in a hurry for a new endpoint.
 *
 * THE RULES, IN ONE PLACE
 *
 *  1. **Default deny.** Every method here starts from "no" and requires a row to
 *     say otherwise. There is no branch that grants on a role string alone.
 *
 *  2. **Two checks, not one.** `users.role` decides which surface somebody signs
 *     in to; the assignment decides which tenant and what depth. A customer
 *     account with an assignment row still reaches nothing, because the first
 *     check fails — so a mistaken or malicious insert into `restaurant_user`
 *     does not by itself hand out a restaurant.
 *
 *  3. **Revoked is not absent.** Assignments and grants are withdrawn by status,
 *     never deleted, and every read filters on it. That filter lives in the
 *     `active` scopes so it cannot be remembered in one query and forgotten in
 *     the next.
 *
 *  4. **Super administrators are scoped too.** Breadth comes from a
 *     PlatformTenantGrant row. With none, a super administrator reaches nothing.
 *     "May access multiple tenants" is not "may access all tenants implicitly".
 *
 *  5. **Scope in the query, never after the fetch.** {@see reachableBy()} is a
 *     `whereIn` against a subquery, so a list is filtered by the database rather
 *     than by a `->filter()` somebody can forget. A lookup that fetches first and
 *     compares second has already told the caller the row exists.
 */
final class TenantAccessService
{
    /**
     * Constrain a restaurant query to the tenants this user may reach.
     *
     * The workhorse. Applied to a list endpoint it filters it; applied to a
     * single-record lookup with a `where uuid`, it turns "not yours" into the
     * same empty result as "not real", which is the answer an attacker learns
     * nothing from.
     */
    public function reachableBy(Builder $query, User $user): Builder
    {
        if ($this->hasPlatformWideGrant($user)) {
            return $query;
        }

        return $query->where(function (Builder $scoped) use ($user): void {
            $scoped
                ->whereIn('restaurants.id', $this->assignedRestaurantIds($user))
                ->orWhereIn('restaurants.id', $this->grantedRestaurantIds($user));
        });
    }

    /**
     * The capability this user holds at this restaurant, or null for none.
     *
     * Null is the answer for "no assignment", "revoked assignment", "wrong
     * surface" and "restaurant does not exist as far as they are concerned".
     * Callers turn all four into the same 404 rather than distinguishing them.
     */
    public function capabilityFor(User $user, Restaurant $restaurant): ?TenantRole
    {
        $fromGrant = $this->grantedCapability($user, $restaurant);

        if (! $this->isRestaurantOperator($user)) {
            // Platform people reach tenants only through grants; a support agent
            // has no assignment and should not be looked up as though they might.
            return $fromGrant;
        }

        $membership = RestaurantMembership::query()
            ->active()
            ->where('user_id', $user->id)
            ->where('restaurant_id', $restaurant->id)
            ->first();

        $fromMembership = $membership?->tenant_role;

        // Somebody could hold both — a platform person who also runs a
        // restaurant. The stronger of the two applies, worked out by the enum's
        // own ordering rather than by a comparison written again here.
        return $this->stronger($fromMembership, $fromGrant);
    }

    /** Whether this user holds at least [$required] at this restaurant. */
    public function allows(User $user, Restaurant $restaurant, TenantRole $required): bool
    {
        return $this->capabilityFor($user, $restaurant)?->includes($required) ?? false;
    }

    /**
     * Whether this account may reach the restaurant surface at all.
     *
     * The first of the two checks. A customer with an assignment row fails here,
     * which is why an insert into `restaurant_user` is not by itself a way in.
     */
    public function isRestaurantOperator(User $user): bool
    {
        return $user->role !== null
            && $user->role->isRestaurantRole()
            && $this->accountUsable($user);
    }

    /** Whether this account may reach the platform surface at all. */
    public function isPlatformOperator(User $user): bool
    {
        return $user->role !== null
            && $user->role->isPlatformRole()
            && $this->accountUsable($user);
    }

    /**
     * A suspended account reaches no tenant, whatever its assignments say.
     *
     * Both columns, because they mean different things and disagree in practice:
     * `status` is the account's standing and `is_active` is the switch. KI-008
     * records that an existing token outlives a suspension until it expires;
     * checking here is what stops that token still reaching a restaurant.
     *
     * `is_active` is compared against false rather than true, and the difference
     * matters. The column defaults to true in the database, so a model that has
     * not round-tripped since it was created holds NULL — and `=== true` would
     * read that absence as a disabled account. Denying by accident looks like
     * security and is not: it makes every "this account reaches nothing" test
     * pass whether the boundary works or not, which is the one bug a tenancy
     * suite must never have. Only an explicit false denies.
     */
    private function accountUsable(User $user): bool
    {
        return $user->status === AccountStatus::Active && $user->is_active !== false;
    }

    /**
     * A grant that covers every tenant.
     *
     * Only meaningful for a platform account: a restaurant owner cannot be handed
     * the whole platform by a row in a table their own module writes to.
     */
    public function hasPlatformWideGrant(User $user): bool
    {
        if (! $this->isPlatformOperator($user)) {
            return false;
        }

        return PlatformTenantGrant::query()
            ->active()
            ->where('user_id', $user->id)
            ->where('scope', 'all')
            ->exists();
    }

    /**
     * Ids this user is assigned to. A subquery rather than a fetched list, so a
     * person with a thousand restaurants does not become a thousand-element
     * `whereIn` — and so the filter happens where the rows are.
     */
    private function assignedRestaurantIds(User $user): Builder
    {
        if (! $this->isRestaurantOperator($user)) {
            // A query that cannot match. Deliberately not an empty array: this
            // keeps the return type one thing, and `whereIn` on a subquery that
            // selects nothing is the same denial without a special case.
            return RestaurantMembership::query()->whereRaw('1 = 0')->select('restaurant_id');
        }

        return RestaurantMembership::query()
            ->active()
            ->where('user_id', $user->id)
            ->select('restaurant_id');
    }

    private function grantedRestaurantIds(User $user): Builder
    {
        if (! $this->isPlatformOperator($user)) {
            return PlatformTenantGrant::query()->whereRaw('1 = 0')->select('restaurant_id');
        }

        return PlatformTenantGrant::query()
            ->active()
            ->where('user_id', $user->id)
            ->where('scope', 'restaurant')
            ->whereNotNull('restaurant_id')
            ->select('restaurant_id');
    }

    private function grantedCapability(User $user, Restaurant $restaurant): ?TenantRole
    {
        if (! $this->isPlatformOperator($user)) {
            return null;
        }

        $grant = PlatformTenantGrant::query()
            ->active()
            ->where('user_id', $user->id)
            ->where(function (Builder $query) use ($restaurant): void {
                $query
                    ->where('scope', 'all')
                    ->orWhere(function (Builder $one) use ($restaurant): void {
                        $one->where('scope', 'restaurant')->where('restaurant_id', $restaurant->id);
                    });
            })
            ->orderByRaw("FIELD(tenant_role, 'owner', 'manager', 'staff')")
            ->first();

        return $grant?->tenant_role;
    }

    private function stronger(?TenantRole $a, ?TenantRole $b): ?TenantRole
    {
        if ($a === null) {
            return $b;
        }

        if ($b === null) {
            return $a;
        }

        return $a->includes($b) ? $a : $b;
    }
}
