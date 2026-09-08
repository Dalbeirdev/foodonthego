<?php

declare(strict_types=1);

namespace App\Services\Orders;

use App\Enums\ApiErrorCode;
use App\Enums\CheckoutQuoteStatus;
use App\Enums\OrderStatus;
use App\Exceptions\ApiException;
use App\Models\Cart;
use App\Models\CheckoutQuote;
use App\Models\Order;
use App\Models\OrderItem;
use App\Models\OrderItemModifier;
use App\Models\Trip;
use App\Models\User;
use App\Services\Checkout\CheckoutPreparationService;
use Carbon\CarbonImmutable;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;

/**
 * Turns an offer into an agreement.
 *
 * The money comes from the quote and nowhere else. Not from the request, not
 * recomputed here from the cart — from the row the server wrote when it made the
 * offer. Recomputing at this point would be subtly wrong even if the arithmetic
 * were identical: the customer agreed to a number they were shown, and the only
 * record of that number is the quote.
 *
 * The quote is re-validated first, because the gap between being shown a price
 * and tapping to accept it is exactly where a cart changes, a restaurant closes,
 * or a clock runs out.
 */
final class OrderPlacementService
{
    public function __construct(
        private readonly CheckoutPreparationService $checkout,
    ) {}

    /**
     * Place the order this quote offers, or hand back the one it already made.
     *
     * **Placement is idempotent.** A customer who double-taps, or an app that
     * retries a request whose response was lost, must not end up with two orders
     * and must not be shown an error for having tried. A quote that has already
     * been consumed returns its order, and the caller distinguishes the two
     * cases by whether the order was created just now.
     *
     * Idempotency rests on the unique index on `orders.checkout_quote_id`, not
     * on the status check below. The status check is the common path; the index
     * is what holds when two requests arrive at the same instant and both see an
     * ACTIVE quote before either has written.
     *
     * @return array{0: Order, 1: bool} The order, and whether this call created it.
     *
     * @throws ApiException
     */
    public function place(
        User $customer,
        Trip $trip,
        Cart $cart,
        CheckoutQuote $quote,
        ?CarbonImmutable $now = null,
    ): array {
        $now ??= CarbonImmutable::now();

        $existing = Order::query()->where('checkout_quote_id', $quote->id)->first();

        if ($existing !== null) {
            return [$existing, false];
        }

        $preparation = $this->checkout->validateQuote($customer, $trip, $cart, $quote, $now);

        $this->refuseUnlessPayable($preparation->status, $preparation->readyForPayment());

        try {
            $order = DB::transaction(fn (): Order => $this->write($customer, $trip, $cart, $quote, $now));
        } catch (QueryException $e) {
            // The unique index fired: another request placed this quote's order
            // between our check and our write. That is the race working as
            // designed, and the right answer is the order that won, not an error.
            $raced = Order::query()->where('checkout_quote_id', $quote->id)->first();

            if ($raced !== null) {
                return [$raced, false];
            }

            throw $e;
        }

        return [$order, true];
    }

    /**
     * @throws ApiException
     */
    private function refuseUnlessPayable(CheckoutQuoteStatus $status, bool $ready): void
    {
        $code = match ($status) {
            CheckoutQuoteStatus::Expired => ApiErrorCode::CheckoutQuoteExpired,
            CheckoutQuoteStatus::Stale => ApiErrorCode::CheckoutQuoteStale,
            CheckoutQuoteStatus::Consumed => ApiErrorCode::CheckoutQuoteConsumed,
            CheckoutQuoteStatus::Active => null,
        };

        if ($code !== null) {
            throw new ApiException($code, match ($code) {
                ApiErrorCode::CheckoutQuoteExpired => 'That checkout timed out. Please review your order again.',
                ApiErrorCode::CheckoutQuoteStale => 'Your order changed. Please review it again.',
                default => 'That checkout has already been used.',
            });
        }

        if (! $ready) {
            throw new ApiException(
                ApiErrorCode::CheckoutNotReady,
                'This order cannot be placed yet. Please review it again.',
            );
        }
    }

    private function write(
        User $customer,
        Trip $trip,
        Cart $cart,
        CheckoutQuote $quote,
        CarbonImmutable $now,
    ): Order {
        $order = new Order;

        $order->customer_id = $customer->id;
        $order->restaurant_id = $quote->restaurant_id;
        $order->trip_id = $trip->id;
        $order->cart_id = $cart->id;
        $order->checkout_quote_id = $quote->id;

        $order->pickup_start_at = $quote->pickup_start_at;
        $order->pickup_end_at = $quote->pickup_end_at;
        $order->pickup_timezone = $quote->pickup_timezone;

        $order->currency = $quote->currency;

        // Copied, not recomputed. See the class docblock.
        foreach ([
            'items_subtotal_minor',
            'tax_minor',
            'tax_configured',
            'packaging_fee_minor',
            'packaging_fee_configured',
            'platform_fee_minor',
            'platform_fee_configured',
            'discount_minor',
            'discount_configured',
            'other_adjustment_minor',
            'other_adjustment_configured',
            'payable_total_minor',
            'commercial_rule_version',
        ] as $column) {
            $order->{$column} = $quote->{$column};
        }

        $order->status = OrderStatus::AwaitingPayment;
        $order->placed_at = $now;
        $order->save();

        $this->copyLines($order, $cart);

        $quote->status = CheckoutQuoteStatus::Consumed;
        $quote->save();

        return $order;
    }

    /**
     * Snapshot the basket onto the order.
     *
     * Names and prices are copied rather than referenced. A year from now the
     * dish may be renamed, repriced or withdrawn, and this order still has to
     * render the receipt the customer agreed to.
     */
    private function copyLines(Order $order, Cart $cart): void
    {
        $cart->loadMissing('items.modifiers');

        $position = 0;

        foreach ($cart->items as $line) {
            $item = new OrderItem;

            $item->order_id = $order->id;
            $item->restaurant_id = $order->restaurant_id;
            $item->menu_item_id = $line->menu_item_id;
            $item->menu_item_variant_id = $line->menu_item_variant_id;
            $item->item_name_snapshot = $line->item_name_snapshot;
            $item->variant_name_snapshot = $line->variant_name_snapshot;
            $item->unit_price_minor = $line->unit_price_minor;
            $item->line_total_minor = $line->line_total_minor;
            $item->currency = $line->currency;
            $item->quantity = $line->quantity;
            $item->special_instructions = $line->special_instructions;
            $item->display_order = $position++;
            $item->save();

            $modifierPosition = 0;

            foreach ($line->modifiers as $modifier) {
                $copy = new OrderItemModifier;

                $copy->order_item_id = $item->id;
                $copy->menu_modifier_group_id = $modifier->menu_modifier_group_id;
                $copy->menu_modifier_option_id = $modifier->menu_modifier_option_id;
                $copy->group_name_snapshot = $modifier->group_name_snapshot;
                $copy->option_name_snapshot = $modifier->option_name_snapshot;
                $copy->price_delta_minor = $modifier->price_delta_minor;
                $copy->currency = $modifier->currency;
                $copy->display_order = $modifierPosition++;
                $copy->save();
            }
        }
    }
}
