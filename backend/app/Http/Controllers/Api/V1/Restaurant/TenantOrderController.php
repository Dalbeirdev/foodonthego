<?php

declare(strict_types=1);

namespace App\Http\Controllers\Api\V1\Restaurant;

use App\Enums\ApiErrorCode;
use App\Exceptions\ApiException;
use App\Http\Responses\ApiResponse;
use App\Models\Order;
use App\Models\User;
use App\Support\Orders\OrderPresenter;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Orders, for the people who have to cook them.
 *
 * Tenant-scoped in the query through `BelongsToTenant`, so an operator sees
 * orders for the restaurants they are assigned to and no others. `show()` takes
 * an order's **own** identifier and names no restaurant — the shape Module 14T
 * exists for, and the one where an unscoped lookup would hand one tenant's
 * customers and totals to another.
 */
final class TenantOrderController
{
    /** Orders for the restaurants this operator may reach. */
    public function index(Request $request): JsonResponse
    {
        /** @var User $operator */
        $operator = $request->user();

        $orders = Order::query()
            ->inReachableTenant($operator)
            ->with('restaurant')
            ->orderByDesc('id')
            ->limit(100)
            ->get();

        return ApiResponse::ok([
            'orders' => $orders->map(OrderPresenter::summary(...))->all(),
        ]);
    }

    /**
     * One order, by its own id, if this operator's tenants include its
     * restaurant.
     *
     * @throws ApiException
     */
    public function show(Request $request, string $order): JsonResponse
    {
        /** @var User $operator */
        $operator = $request->user();

        $found = Order::query()
            ->inReachableTenant($operator)
            ->where('uuid', $order)
            ->with(['items.modifiers', 'restaurant'])
            ->first();

        if ($found === null) {
            // The same 404 an order that does not exist gets. An operator
            // probing identifiers must not be able to tell another tenant's
            // order from a fictional one.
            throw new ApiException(
                ApiErrorCode::OrderNotFound,
                'That order could not be found.',
            );
        }

        return ApiResponse::ok(OrderPresenter::detail($found));
    }
}
