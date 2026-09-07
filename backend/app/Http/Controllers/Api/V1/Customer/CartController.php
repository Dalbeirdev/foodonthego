<?php

declare(strict_types=1);

namespace App\Http\Controllers\Api\V1\Customer;

use App\Enums\ApiErrorCode;
use App\Exceptions\ApiException;
use App\Http\Responses\ApiResponse;
use App\Models\Cart;
use App\Models\User;
use App\Services\Cart\CartLineRepricer;
use App\Services\Cart\CartService;
use App\Services\Cart\CartTotalsService;
use App\Services\Trip\TripService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Reading a cart, correcting it, and emptying it.
 *
 * {@see CartItemController} puts things in. This takes them out again, changes
 * how many there are, and answers "what do I owe" — the half of a cart Module
 * 11 deliberately did not build, because a cart you can fill and cannot empty
 * is worse than one you cannot fill.
 *
 * **No request here carries a price, and none of these handlers reads one.**
 * A quantity change re-prices the line from live menu rows; the number the
 * client sends is a count, and the only thing it is allowed to influence is how
 * many times the server multiplies its own figure.
 *
 * Ownership is proved the same way it is everywhere else in this module: the
 * journey in the path must belong to the caller, and everything else hangs off
 * that. A cart line id names nothing on its own.
 *
 * None of these endpoints calls a routing provider or a places provider. The
 * cart is rows this platform already holds.
 */
final class CartController
{
    public function __construct(
        private readonly TripService $trips,
        private readonly CartService $carts,
        private readonly CartLineRepricer $repricer,
        private readonly CartTotalsService $totals,
    ) {}

    /**
     * The whole cart: its lines, its options, and what it costs.
     *
     * Module 11 answered this with a count and a subtotal, for a badge. The
     * shape is extended rather than replaced — every field that endpoint
     * returned it still returns, in the same place — because a client already
     * ships against it.
     *
     * @throws ApiException
     */
    public function show(Request $request, string $trip): JsonResponse
    {
        /** @var User $customer */
        $customer = $request->user();

        $found = $this->trips->ownedByOrFail($customer, $trip);

        $cart = $this->carts->activeCartWithLines($customer, $found);

        return ApiResponse::ok($this->payload($cart));
    }

    /**
     * Changes how many of one line the customer wants.
     *
     * Priced from the menu as it stands, never by scaling the stored figure.
     * The price on the row was authoritative when the line was added; charging
     * it a week later because it happens to be written down is how a stale
     * number becomes a real charge.
     *
     * @throws ApiException
     */
    public function updateItem(Request $request, string $trip, string $item): JsonResponse
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

        $line = $this->carts->lineOrFail($cart, $item);
        $quantity = $this->readQuantity($request);

        $restaurant = $cart->restaurant;

        if ($restaurant === null) {
            // A cart whose restaurant row has gone. Nothing here can be priced,
            // and pretending otherwise would produce a total from snapshots.
            throw new ApiException(
                ApiErrorCode::RestaurantUnavailable,
                'This restaurant is no longer available.',
            );
        }

        $priced = $this->repricer->reprice($restaurant, $line, $quantity);

        $updated = $this->carts->setQuantity($cart, $line, $priced);

        return ApiResponse::ok($this->payload($updated));
    }

    /**
     * Takes one line out of the cart.
     *
     * The cart closes if that was the last line. It is not deleted, and the
     * client is told the difference: the response is the same shape as an empty
     * cart on a fresh journey, which is what an empty cart is.
     *
     * @throws ApiException
     */
    public function destroyItem(Request $request, string $trip, string $item): JsonResponse
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

        $line = $this->carts->lineOrFail($cart, $item);

        $updated = $this->carts->removeLine($cart, $line);

        return ApiResponse::ok($this->payload($updated));
    }

    /**
     * Empties the cart, at the customer's explicit request.
     *
     * Idempotent on purpose: emptying a cart that is already empty is a
     * success, not a 404. A customer who taps twice, or a client that retries a
     * request whose response was lost, has got what they asked for both times.
     *
     * @throws ApiException
     */
    public function destroy(Request $request, string $trip): JsonResponse
    {
        /** @var User $customer */
        $customer = $request->user();

        $found = $this->trips->ownedByOrFail($customer, $trip);

        $cart = $this->carts->activeCartWithLines($customer, $found);

        if ($cart === null) {
            return ApiResponse::ok($this->payload(null));
        }

        $updated = $this->carts->emptyCart($cart);

        return ApiResponse::ok($this->payload($updated));
    }

    /**
     * One response shape for every handler here.
     *
     * A cart that has just been closed reports as no cart, deliberately: to the
     * customer, an emptied cart and a journey they have not started ordering on
     * look the same, and a client that had to tell them apart would need state
     * it has no reason to hold.
     *
     * @return array<string, mixed>
     */
    private function payload(?Cart $cart): array
    {
        if ($cart === null || ! $cart->isActive()) {
            return [
                'cart' => null,
                'item_count' => 0,
                'line_count' => 0,
            ];
        }

        return [
            'cart' => $cart->toCustomerArray($this->totals->totalsFor($cart)),
            'item_count' => $cart->itemCount(),
            'line_count' => $cart->items->count(),
        ];
    }

    /**
     * The requested quantity, or a refusal.
     *
     * **Zero is refused, not treated as removal.** A client that means "remove"
     * says DELETE. Overloading nought as deletion makes an off-by-one in a
     * stepper destroy a customer's selection, and leaves the server unable to
     * tell a mistake from an intention.
     *
     * Strict about the type, like the add path: "2" is fine, 2.5 and "two" are
     * not, and coercing them would turn a client bug into a quiet half-portion.
     *
     * @throws ApiException
     */
    private function readQuantity(Request $request): int
    {
        $raw = $request->input('quantity');

        if (is_string($raw) && ctype_digit($raw)) {
            $raw = (int) $raw;
        }

        if (! is_int($raw)) {
            throw new ApiException(
                ApiErrorCode::QuantityInvalid,
                'Say how many you would like.',
            );
        }

        if ($raw < 1) {
            throw new ApiException(
                ApiErrorCode::QuantityInvalid,
                'Choose at least one, or remove the item.',
            );
        }

        $max = (int) config('foodonthego.cart.max_quantity_per_line');

        if ($raw > $max) {
            throw new ApiException(
                ApiErrorCode::QuantityLimitExceeded,
                "You can have up to {$max} of one item.",
                ['max_quantity' => $max],
            );
        }

        return $raw;
    }
}
