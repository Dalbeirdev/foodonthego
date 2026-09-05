<?php

declare(strict_types=1);

namespace App\Http\Controllers\Api\V1\Customer;

use App\Enums\ApiErrorCode;
use App\Exceptions\ApiException;
use App\Http\Responses\ApiResponse;
use App\Models\MenuCategory;
use App\Models\MenuItem;
use App\Models\User;
use App\Services\Menu\CustomerMenuService;
use App\Services\Menu\MenuQuery;
use App\Services\Restaurant\RestaurantDetailService;
use App\Services\Trip\TripService;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * A restaurant's menu, for a customer on a route.
 *
 * Nested under the restaurant, which is nested under the trip. The path is long
 * and every segment earns its place: the trip proves the journey is the
 * customer's, and the restaurant is validated through exactly the same
 * {@see RestaurantDetailService} Module 09 uses — so a menu cannot be opened
 * for a restaurant whose *page* could not be opened.
 *
 * That is the whole eligibility story, and it is reuse rather than
 * reimplementation. A suspended restaurant's menu is unreachable because
 * `orderingContext()` refuses before this controller has anything to render,
 * and there is no second set of `where` clauses here to get wrong. It is the
 * lighter of that service's two entry points: the menu screen shows a name and
 * whether an order can be placed, so it does not pay for the photographs,
 * cuisines, facilities and fortnight of opening hours the profile screen needs.
 *
 * Opening a menu calls no routing provider. `orderingContext()` reaches Module
 * 07's cached discovery result, which is the only thing in the application that
 * can reach one, and it is already warm from the list the customer came
 * through.
 *
 * Read-only. There is no sibling write endpoint, and no route through which a
 * customer could change a price, a stock status or an item.
 */
final class RestaurantMenuController
{
    public function __construct(
        private readonly TripService $trips,
        private readonly RestaurantDetailService $detail,
        private readonly CustomerMenuService $menu,
    ) {}

    public function index(Request $request, string $trip, string $restaurant): JsonResponse
    {
        /** @var User $customer */
        $customer = $request->user();

        $found = $this->trips->ownedByOrFail($customer, $trip);

        // Validated before the search string is even read: a malformed query on
        // a suspended restaurant is refused for the restaurant, not the query.
        $now = CarbonImmutable::now();
        $context = $this->detail->orderingContext($found, $restaurant, $now);

        $query = MenuQuery::fromRequest($request);

        $menu = $this->menu->menu($context->discovered->restaurant, $query, $now);

        return ApiResponse::ok([
            // A compact header, not the whole restaurant page again. What the
            // menu screen needs is the name and whether an order can be placed.
            'restaurant' => [
                'id' => $context->discovered->restaurant->uuid,
                'name' => $context->discovered->restaurant->name,
                'availability' => $context->discovered->availability->value,
                'ordering' => [
                    'state' => $context->ordering->value,
                    'can_order' => $context->ordering->canOrder(),
                    'can_browse_menu' => $context->ordering->permitsBrowsing(),
                ],
            ],
            ...$menu->toApiArray(),
        ]);
    }

    /**
     * One item, read-only.
     *
     * Everything the list already carried, fetched again rather than trusted:
     * a customer may have had the menu open for ten minutes, and a preview that
     * echoed the payload it was opened from would show a price that had since
     * changed.
     */
    public function show(
        Request $request,
        string $trip,
        string $restaurant,
        string $item,
    ): JsonResponse {
        /** @var User $customer */
        $customer = $request->user();

        $found = $this->trips->ownedByOrFail($customer, $trip);

        $now = CarbonImmutable::now();
        $context = $this->detail->orderingContext($found, $restaurant, $now);

        $menuItem = $this->menu->item($context->discovered->restaurant, $item);

        if ($menuItem === null) {
            // No such item, another restaurant's item, or one withdrawn from
            // the menu. Answered identically: telling them apart would let
            // anybody with a list of ids map a competitor's menu.
            throw new ApiException(
                ApiErrorCode::ItemNotFound,
                'That menu item could not be found.',
            );
        }

        // Eager-loaded by the service; the composite foreign key guarantees it
        // exists, so this is a type narrowing rather than a fallback.
        $category = $menuItem->category;

        if ($category === null) {
            throw new ApiException(
                ApiErrorCode::ItemNotFound,
                'That menu item could not be found.',
            );
        }

        $rendered = $this->render($menuItem, $category);

        return ApiResponse::ok([
            'restaurant' => [
                'id' => $context->discovered->restaurant->uuid,
                'name' => $context->discovered->restaurant->name,
                'ordering' => [
                    'state' => $context->ordering->value,
                    'can_order' => $context->ordering->canOrder(),
                    'can_browse_menu' => $context->ordering->permitsBrowsing(),
                ],
            ],
            'item' => $rendered,
            'category' => [
                'id' => $category->uuid,
                'name' => $category->name,
            ],
            'generated_at' => $now->utc()->toIso8601String(),
        ]);
    }

    /**
     * @return array<string, mixed>
     *
     * @throws ApiException
     */
    private function render(MenuItem $item, MenuCategory $category): array
    {
        $rendered = $item->toCustomerArray($category);

        if ($rendered === null) {
            // The row exists and cannot be shown honestly — today, only a price
            // that will not parse. Refused rather than rendered with a
            // guessed-at figure.
            throw new ApiException(
                ApiErrorCode::ItemUnavailable,
                'That menu item is not available.',
            );
        }

        return $rendered;
    }
}
