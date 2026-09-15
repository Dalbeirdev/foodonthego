<?php

declare(strict_types=1);

namespace App\Http\Controllers\Api\V1\Restaurant;

use App\Enums\ApiErrorCode;
use App\Exceptions\ApiException;
use App\Http\Responses\ApiResponse;
use App\Models\Restaurant;
use App\Models\User;
use App\Services\Tenancy\TenantAccessService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Gate;

/**
 * The restaurants an operator may reach, and one of them.
 *
 * **This is not the operator dashboard.** It is the smallest surface that makes
 * tenant isolation testable the way it has to be tested — over HTTP, with a real
 * token, substituting a real identifier belonging to somebody else. A service
 * method cannot be IDOR-tested; only a route can. The dashboard is a later
 * module and will add to this rather than replace it.
 *
 * There is no login flow that mints a token for these roles yet. That is
 * deliberate and recorded in docs/07-security.md: the isolation is the thing
 * being built, and authenticating a restaurant user is a different module. The
 * routes are guarded by `auth:sanctum` and the role gate regardless, so the day
 * that login arrives it arrives behind a boundary that already exists and is
 * already tested.
 */
final class TenantRestaurantController
{
    public function __construct(
        private readonly TenantAccessService $access,
    ) {}

    /**
     * Every tenant this operator may reach.
     *
     * Filtered by the database, not by the caller. A restaurant this person is
     * not assigned to is not in the result set at all — there is no moment where
     * the full list exists and something has to remember to trim it.
     */
    public function index(Request $request): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();

        $restaurants = Restaurant::query()
            ->reachableBy($user)
            ->orderBy('name')
            ->get();

        return ApiResponse::ok([
            'restaurants' => $restaurants
                ->map(fn (Restaurant $restaurant): array => $this->summary($user, $restaurant))
                ->all(),
        ]);
    }

    /**
     * One tenant.
     *
     * Resolved through the reachable scope rather than fetched and then checked.
     * A restaurant that exists but belongs to somebody else produces exactly the
     * same 404 as one that never existed, because the query returns nothing in
     * both cases — the difference between "not yours" and "not real" is what an
     * attacker is enumerating for.
     *
     * @throws ApiException
     */
    public function show(Request $request, string $restaurant): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();

        $found = $this->reachableOrFail($user, $restaurant);

        // Belt as well as braces. The scope already refused anything unreachable,
        // so this can only fail if the two disagree — and if they ever do, the
        // policy is the one to trust and this is where that shows up.
        Gate::forUser($user)->authorize('view', $found);

        return ApiResponse::ok(['restaurant' => $this->summary($user, $found)]);
    }

    /**
     * Change an operational setting.
     *
     * Present so that *write* isolation is tested rather than assumed. Reads and
     * writes fail differently often enough that testing one proves little about
     * the other: a read might be scoped by a shared query builder while a write
     * uses a direct `find()` somebody added later.
     *
     * One field, chosen because it is genuinely useful and genuinely
     * consequential: switching a restaurant off to customers. Manager and above,
     * per the policy — not a shift-level decision.
     *
     * @throws ApiException
     */
    public function update(Request $request, string $restaurant): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();

        $found = $this->reachableOrFail($user, $restaurant);

        Gate::forUser($user)->authorize('update', $found);

        $validated = $request->validate([
            'is_accepting_orders' => ['required', 'boolean'],
        ]);

        // forceFill against a named column, not the request array. `$fillable` is
        // empty on this model for exactly this reason, and a mass-assigned
        // `status` here would be a way to un-suspend a restaurant.
        $found->forceFill(['is_accepting_orders' => $validated['is_accepting_orders']])->save();

        return ApiResponse::ok(['restaurant' => $this->summary($user, $found->refresh())]);
    }

    /**
     * The tenant named in the path, if this operator may reach it.
     *
     * @throws ApiException
     */
    private function reachableOrFail(User $user, string $uuid): Restaurant
    {
        $found = Restaurant::query()
            ->reachableBy($user)
            ->where('restaurants.uuid', $uuid)
            ->first();

        if ($found === null) {
            throw new ApiException(
                ApiErrorCode::NotFound,
                'That restaurant is not available on this account.',
            );
        }

        return $found;
    }

    /**
     * What an operator is told about a tenant.
     *
     * An allow-list, like every other projection in this codebase. Nothing from
     * the private columns — commission, bank reference, internal notes — reaches
     * here: those are an owner-only concern and will arrive with the screen that
     * needs them, behind `viewFinancials`.
     *
     * @return array<string, mixed>
     */
    private function summary(User $user, Restaurant $restaurant): array
    {
        return [
            'id' => $restaurant->uuid,
            'name' => $restaurant->name,
            'city' => $restaurant->city,
            'timezone' => $restaurant->timezone,
            'status' => $restaurant->status?->value,
            'is_accepting_orders' => (bool) $restaurant->is_accepting_orders,

            // What this person may do here, so a client can render the right
            // controls. Advisory only: hiding a button is a courtesy, and every
            // endpoint checks for itself regardless.
            'capability' => $this->access->capabilityFor($user, $restaurant)?->value,
        ];
    }
}
