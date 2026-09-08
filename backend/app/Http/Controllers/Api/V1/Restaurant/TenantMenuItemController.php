<?php

declare(strict_types=1);

namespace App\Http\Controllers\Api\V1\Restaurant;

use App\Enums\ApiErrorCode;
use App\Exceptions\ApiException;
use App\Http\Responses\ApiResponse;
use App\Models\MenuItem;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Gate;

/**
 * Menu items, reached two ways on purpose.
 *
 * **`show()` is the most valuable route in this module.** It takes a menu item's
 * *own* identifier and nothing else: no restaurant in the path, nothing in the
 * request that names a tenant. That is the shape where cross-tenant holes
 * actually live, because the obvious implementation — `MenuItem::where('uuid',
 * $uuid)->first()` — is correct-looking, passes every test somebody writes about
 * menu items, and hands one restaurant's prices to another.
 *
 * It is scoped through `inReachableTenant`, which reaches back through the owning
 * restaurant and filters in the query. There is no moment at which an unscoped
 * row exists to be checked or forgotten.
 *
 * `index()` is the easy shape, present as its control: if only the nested route
 * were tested, a pass would say nothing about the dangerous one.
 */
final class TenantMenuItemController
{
    /**
     * Items belonging to one tenant, named in the path.
     *
     * @throws ApiException
     */
    public function index(Request $request, string $restaurant): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();

        $found = Restaurant::query()
            ->reachableBy($user)
            ->where('restaurants.uuid', $restaurant)
            ->first();

        if ($found === null) {
            throw new ApiException(
                ApiErrorCode::NotFound,
                'That restaurant is not available on this account.',
            );
        }

        Gate::forUser($user)->authorize('manageMenu', $found);

        $items = MenuItem::query()
            ->where('restaurant_id', $found->id)
            ->orderBy('name')
            ->get();

        return ApiResponse::ok([
            'items' => $items->map(fn (MenuItem $item): array => $this->summary($item))->all(),
        ]);
    }

    /**
     * One item, by its own id, with no tenant anywhere in the request.
     *
     * @throws ApiException
     */
    public function show(Request $request, string $item): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();

        $found = MenuItem::query()
            ->inReachableTenant($user)
            ->where('menu_items.uuid', $item)
            ->with('restaurant')
            ->first();

        if ($found === null) {
            throw new ApiException(
                ApiErrorCode::NotFound,
                'That menu item is not available on this account.',
            );
        }

        // The tenant scope decided reachability; the policy decides depth. Staff
        // may not read the menu editor, and finding that out here rather than in
        // the scope keeps the two questions apart.
        Gate::forUser($user)->authorize('manageMenu', $found->restaurant);

        return ApiResponse::ok(['item' => $this->summary($found)]);
    }

    /** @return array<string, mixed> */
    private function summary(MenuItem $item): array
    {
        return [
            'id' => $item->uuid,
            'name' => $item->name,
            'base_price_minor' => $item->base_price_minor,
            'currency' => $item->currency,
            'stock_status' => $item->stock_status,
            'is_active' => (bool) $item->is_active,
        ];
    }
}
