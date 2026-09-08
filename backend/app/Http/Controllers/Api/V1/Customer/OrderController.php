<?php

declare(strict_types=1);

namespace App\Http\Controllers\Api\V1\Customer;

use App\Enums\ApiErrorCode;
use App\Exceptions\ApiException;
use App\Http\Responses\ApiResponse;
use App\Models\Cart;
use App\Models\CheckoutQuote;
use App\Models\Order;
use App\Models\Trip;
use App\Models\User;
use App\Services\Cart\CartService;
use App\Services\Orders\OrderPlacementService;
use App\Services\Trip\TripService;
use App\Support\Orders\OrderPresenter;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * A customer's own orders.
 *
 * Placement takes a checkout quote and turns it into an order. It sends no
 * amount, because there is no field for one — the price is the one the server
 * quoted, read from the quote row.
 */
final class OrderController
{
    public function __construct(
        private readonly TripService $trips,
        private readonly CartService $carts,
        private readonly OrderPlacementService $placement,
    ) {}

    /**
     * Turn an accepted quote into an order.
     *
     * Answers 201 when it created one and 200 when the quote had already made
     * one, so a retried or double-tapped request is told plainly that nothing
     * new happened rather than being handed an error.
     *
     * @throws ApiException
     */
    public function place(Request $request, string $trip, string $checkout): JsonResponse
    {
        [$customer, $found, $cart] = $this->context($request, $trip);

        $quote = $this->quoteOrFail($customer, $cart, $checkout);

        [$order, $created] = $this->placement->place($customer, $found, $cart, $quote);

        $order->loadMissing(['items.modifiers', 'restaurant']);

        $payload = OrderPresenter::detail($order);

        return $created
            ? ApiResponse::created($payload)
            : ApiResponse::ok($payload);
    }

    /** This customer's orders, newest first. */
    public function index(Request $request): JsonResponse
    {
        /** @var User $customer */
        $customer = $request->user();

        $orders = Order::query()
            ->where('customer_id', $customer->id)
            ->with('restaurant')
            ->orderByDesc('id')
            ->limit(50)
            ->get();

        return ApiResponse::ok([
            'orders' => $orders->map(OrderPresenter::summary(...))->all(),
        ]);
    }

    /**
     * One order, if it is this customer's.
     *
     * @throws ApiException
     */
    public function show(Request $request, string $order): JsonResponse
    {
        return ApiResponse::ok(OrderPresenter::detail($this->ownedOrFail($request, $order)));
    }

    /**
     * The order named in the path, if it belongs to the caller.
     *
     * Scoped by customer **in the query**, not fetched and then compared. A
     * lookup that finds the row first has already decided it exists, and the
     * difference between "not yours" and "not real" is precisely what somebody
     * trying identifiers is attempting to learn. Both answer 404.
     *
     * @throws ApiException
     */
    public static function ownedOrFail(Request $request, string $uuid): Order
    {
        /** @var User $customer */
        $customer = $request->user();

        $order = Order::query()
            ->where('uuid', $uuid)
            ->where('customer_id', $customer->id)
            ->with(['items.modifiers', 'restaurant'])
            ->first();

        if ($order === null) {
            throw new ApiException(
                ApiErrorCode::OrderNotFound,
                'That order could not be found.',
            );
        }

        return $order;
    }

    /**
     * @throws ApiException
     */
    private function quoteOrFail(User $customer, Cart $cart, string $uuid): CheckoutQuote
    {
        $quote = CheckoutQuote::query()
            ->where('uuid', $uuid)
            ->where('customer_id', $customer->id)
            ->where('cart_id', $cart->id)
            ->first();

        if ($quote === null) {
            throw new ApiException(
                ApiErrorCode::CheckoutQuoteNotFound,
                'That checkout is no longer available. Please try again.',
            );
        }

        return $quote;
    }

    /**
     * @return array{0: User, 1: Trip, 2: Cart}
     *
     * @throws ApiException
     */
    private function context(Request $request, string $trip): array
    {
        /** @var User $customer */
        $customer = $request->user();

        $found = $this->trips->ownedByOrFail($customer, $trip);

        $cart = $this->carts->activeCartWithLines($customer, $found);

        if ($cart === null) {
            throw new ApiException(
                ApiErrorCode::CartNotFound,
                'You do not have a cart on this journey.',
            );
        }

        $cart->setRelation('trip', $found);
        $cart->loadMissing(['restaurant.openingHours', 'customer']);

        return [$customer, $found, $cart];
    }
}
