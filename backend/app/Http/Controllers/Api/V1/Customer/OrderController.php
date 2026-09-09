<?php

declare(strict_types=1);

namespace App\Http\Controllers\Api\V1\Customer;

use App\Enums\ApiErrorCode;
use App\Enums\OrderCreationState;
use App\Exceptions\ApiException;
use App\Http\Responses\ApiResponse;
use App\Models\Cart;
use App\Models\CheckoutQuote;
use App\Models\Order;
use App\Models\Trip;
use App\Models\User;
use App\Services\Cart\CartService;
use App\Services\Orders\OrderPlacementService;
use App\Services\Orders\OrderRecoveryService;
use App\Services\Orders\PickupCredentialService;
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
        private readonly PickupCredentialService $credentials,
        private readonly OrderRecoveryService $recovery,
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

    /**
     * This customer's orders, newest first.
     *
     * PAYMENT TARGETS ARE NOT ORDERS AND ARE NOT LISTED. A row in
     * AWAITING_PAYMENT or PAYMENT_FAILED is something a customer started and
     * did not finish paying for; showing it in the Orders tab would tell them
     * they had bought food they had not. The filter is `placed_at` being set,
     * which is written by exactly one code path — order placement — so the list
     * cannot drift from the definition by somebody adding a status later.
     *
     * Sorted on placed_at rather than id, because a recovery run can place an
     * order minutes after a later one, and the customer's history should read
     * in the order they bought things.
     */
    public function index(Request $request): JsonResponse
    {
        /** @var User $customer */
        $customer = $request->user();

        $orders = Order::query()
            ->where('customer_id', $customer->id)
            ->whereNotNull('placed_at')
            // Eager-loaded, or the summary below runs a restaurant query per
            // row and a customer with fifty orders pays for fifty round trips.
            ->with('restaurant')
            ->orderByDesc('placed_at')
            ->orderByDesc('id')
            ->limit(50)
            ->get();

        return ApiResponse::ok([
            'orders' => $orders->map(OrderPresenter::summary(...))->all(),
        ]);
    }

    /**
     * Where this purchase stands, for a customer who has come back.
     *
     * THE APP-RESTART PATH. Payment captured, app killed by the OS before the
     * confirmation rendered, customer reopens twenty minutes later on a highway
     * with two bars of signal. This endpoint answers, and answers idempotently:
     * it either finds the order or asks the same creation service every other
     * route uses, so refreshing cannot produce a second order.
     *
     * 200 with the order when it exists. 202 when the money is captured and the
     * order is still being written — never a 4xx, and never anything a client
     * could reasonably render as a failed payment.
     *
     * @throws ApiException
     */
    public function status(Request $request, string $order): JsonResponse
    {
        $outcome = $this->recovery->resolve($this->ownedOrFail($request, $order));

        $state = match (true) {
            $outcome->isPlaced => OrderCreationState::Placed,
            $outcome->isRecovering => OrderCreationState::Recovering,
            default => OrderCreationState::AwaitingPayment,
        };

        $outcome->order->loadMissing(['items.modifiers', 'restaurant']);

        return ApiResponse::ok([
            'state' => $state->value,

            /*
             | Whether the money has already left the customer's account.
             |
             | The single field a client needs in order to decide whether
             | offering a Pay button is honest or catastrophic. Sent explicitly
             | rather than left for the client to infer from the state string,
             | because inferring it means every client re-implements the rule
             | and one of them eventually gets it wrong in the direction that
             | charges somebody twice.
             */
            'is_paid_for' => $state->isPaidFor(),

            'message' => $state->isPaidFor() && $state !== OrderCreationState::Placed
                // Written for a customer, because it reaches one. It says the
                // money is safe and says not to pay again; neither half may be
                // dropped for brevity.
                ? 'Payment confirmed. We are still creating your order — please do not pay again.'
                : null,

            'order' => OrderPresenter::detail($outcome->order),
        ], status: $state->httpStatus());
    }

    /**
     * The pickup code and QR payload, on their own endpoint.
     *
     * DELIBERATELY NOT PART OF THE ORDER RESPONSE. An order is read on every
     * confirmation view, every Orders tab refresh and every poll; a credential
     * that rode along would be logged by proxies, cached by clients, and
     * present in a hundred responses that had no need of it. Separating it
     * means the credential is fetched when it is about to be shown and at no
     * other time.
     *
     * ON THE CACHE HEADERS, ACCURATELY. `SecureHeaders` sets
     * `Cache-Control: no-store, private` on every API response and runs after
     * this method, so the middleware — not this controller — is what actually
     * ships. A negative control proved it: changing the value below to
     * `private, max-age=60` left the route's own test green.
     *
     * The header is still set here, and `Pragma` with it, so that the intent
     * is legible at the one route where it matters most and so that a future
     * narrowing of the middleware cannot silently make this response
     * cacheable. It is belt to the middleware's braces, and it is documented
     * as such rather than being left to read like the guarantee.
     *
     * no-store, not no-cache, in both places. no-cache permits storing and
     * revalidating; only no-store tells every intermediary and the browser to
     * keep no copy at all.
     *
     * @throws ApiException
     */
    public function pickupCredential(Request $request, string $order): JsonResponse
    {
        $found = $this->ownedOrFail($request, $order);

        if ($found->placed_at === null || ! $found->status->isPlacedOrder()) {
            throw new ApiException(
                ApiErrorCode::OrderNotFound,
                'This order has no pickup credential.',
            );
        }

        if ($found->status->isTerminal()) {
            throw new ApiException(
                ApiErrorCode::PickupCredentialUnavailable,
                'This order can no longer be collected.',
            );
        }

        $credential = $this->credentials->derive($found);

        return ApiResponse::ok([
            'pickup' => [
                'code' => $credential->code,

                /*
                 | A versioned opaque payload, and nothing else.
                 |
                 | No name, no phone, no total, no payment identifier, no
                 | restaurant banking detail. A QR code is photographed,
                 | screenshotted and shared far more casually than anybody
                 | designing one expects, and every field inside it is a field
                 | that leaks. The version prefix is there so Module 21 can
                 | change the format without guessing what it is reading.
                 */
                'qr_payload' => 'foodonthego://pickup/v1/'.$credential->token,
                'credential_version' => $credential->version,
                'expires_at' => $found->pickup_token_expires_at?->toIso8601String(),
            ],
        ])->withHeaders([
            'Cache-Control' => 'no-store, private, max-age=0',
            'Pragma' => 'no-cache',
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
