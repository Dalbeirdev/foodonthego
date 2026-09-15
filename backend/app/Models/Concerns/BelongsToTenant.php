<?php

declare(strict_types=1);

namespace App\Models\Concerns;

use App\Models\Restaurant;
use App\Models\User;
use App\Services\Tenancy\TenantAccessService;
use Illuminate\Database\Eloquent\Builder;

/**
 * Tenant scoping for anything that hangs off a restaurant.
 *
 * **This trait exists because of the indirect path, which is where the real
 * holes are.** Scoping a route like `/restaurants/{restaurant}/menu/items` is
 * easy: the tenant is in the URL and gets checked on the way past. The dangerous
 * shape is `/menu/items/{item}` — a resource reached by its *own* identifier,
 * where nothing in the request names a restaurant and it is entirely possible to
 * write a lookup that never asks which one it belongs to.
 *
 * So the scope reaches back through the owning restaurant and filters there, in
 * the query, before the row is ever loaded. A caller that uses it cannot forget
 * the tenant check, because there is no moment at which they hold an unscoped
 * row.
 *
 * Requires a `restaurant_id` column. Models further down — a variant belonging
 * to an item belonging to a restaurant — should scope through their own parent
 * rather than growing a denormalised column to satisfy this.
 */
trait BelongsToTenant
{
    /**
     * Restrict to records whose restaurant this user may reach.
     *
     * The subquery is deliberate. Fetching the reachable ids first and passing an
     * array would work today and fail quietly the day somebody has a lot of
     * restaurants; more importantly it would move the decision out of the
     * database, which is where this project keeps it.
     */
    public function scopeInReachableTenant(Builder $query, User $user): void
    {
        $reachable = Restaurant::query()->select('restaurants.id');

        app(TenantAccessService::class)->reachableBy($reachable, $user);

        $query->whereIn($query->getModel()->getTable().'.restaurant_id', $reachable);
    }
}
