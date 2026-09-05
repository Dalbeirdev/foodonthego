<?php

declare(strict_types=1);

namespace App\Services\Cart;

use App\Enums\ApiErrorCode;
use App\Enums\CartStatus;
use App\Exceptions\ApiException;
use App\Models\Cart;
use App\Models\CartItem;
use App\Models\CartItemModifier;
use App\Models\Restaurant;
use App\Models\Trip;
use App\Models\User;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * The cart, and the rules about which cart a customer is allowed to have.
 *
 * Three scoping rules, and none of them is a suggestion:
 *
 * **One active cart per customer per journey.** Enforced by a unique index on
 * a generated column, so two taps racing cannot produce two carts.
 *
 * **One restaurant per cart.** A pickup order is collected at a counter. Adding
 * a second restaurant's dish is a conflict, answered with a code the client can
 * explain — never a silent merge, and never a silent emptying. Destroying a
 * customer's selections to make an API call succeed is a decision for them, on
 * a screen that Module 12 owns.
 *
 * **One journey per cart.** A cart discovered on the Delhi–Jaipur road does not
 * quietly follow the customer onto a different trip.
 *
 * Writing a line is one transaction. A cart item without its modifiers would be
 * a dish the customer never configured, at a price nobody agreed.
 */
final class CartService
{
    /**
     * The customer's active cart for this journey, or null.
     */
    public function activeCartFor(User $customer, Trip $trip): ?Cart
    {
        return Cart::query()
            ->where('customer_id', $customer->id)
            ->where('trip_id', $trip->id)
            ->where('status', CartStatus::Active)
            ->with(['items.modifiers'])
            ->first();
    }

    /**
     * Any active cart this customer has, on any journey.
     *
     * Used to answer "you already have a cart, elsewhere" rather than to act on
     * it. Module 11 never moves or empties one.
     */
    public function anyActiveCart(User $customer): ?Cart
    {
        return Cart::query()
            ->where('customer_id', $customer->id)
            ->where('status', CartStatus::Active)
            ->orderByDesc('id')
            ->first();
    }

    /**
     * Adds one configured dish, and answers with the cart it went into.
     *
     * @throws ApiException
     */
    public function add(
        User $customer,
        Trip $trip,
        Restaurant $restaurant,
        ResolvedCustomization $resolved,
        PricedCustomization $priced,
    ): CartAddition {
        return DB::transaction(function () use ($customer, $trip, $restaurant, $resolved, $priced): CartAddition {
            $cart = $this->cartFor($customer, $trip, $restaurant, $priced->unitPrice->currency);

            $existing = CartItem::query()
                ->where('cart_id', $cart->id)
                ->where('configuration_hash', $resolved->fingerprint)
                // Locked for the length of the transaction, so two taps that
                // arrive together cannot both read "no existing line" and both
                // insert one. The unique index is the backstop; this is what
                // stops it having to fire.
                ->lockForUpdate()
                ->first();

            $item = $existing === null
                ? $this->createLine($cart, $resolved, $priced)
                : $this->increaseLine($existing, $resolved, $priced);

            $cart->touchActivity();

            return new CartAddition(
                // Reloaded with the restaurant, so the response's name and
                // subtotal do not each cost their own query.
                cart: $cart->fresh(['items.modifiers', 'restaurant']) ?? $cart,
                item: $item,
                priced: $priced,
                merged: $existing !== null,
            );
        });
    }

    /**
     * The cart this dish belongs in, created if the customer has none yet.
     *
     * @throws ApiException
     */
    private function cartFor(
        User $customer,
        Trip $trip,
        Restaurant $restaurant,
        string $currency,
    ): Cart {
        $existing = Cart::query()
            ->where('customer_id', $customer->id)
            ->where('status', CartStatus::Active)
            ->lockForUpdate()
            ->get();

        foreach ($existing as $cart) {
            if ((int) $cart->trip_id !== (int) $trip->id) {
                // A cart on another journey. Refused rather than reused: the
                // stop was chosen for a particular road, and quietly moving it
                // to a different one changes what the customer decided.
                throw new ApiException(
                    ApiErrorCode::CartTripConflict,
                    'You have items in a cart for a different journey.',
                    ['cart_id' => $cart->uuid, 'trip_id' => $cart->trip?->uuid],
                );
            }

            if ((int) $cart->restaurant_id !== (int) $restaurant->id) {
                throw new ApiException(
                    ApiErrorCode::CartRestaurantConflict,
                    'Your cart has items from a different restaurant.',
                    [
                        'cart_id' => $cart->uuid,
                        'restaurant_id' => $cart->restaurant?->uuid,
                        'restaurant_name' => $cart->restaurant?->name,
                    ],
                );
            }

            if ($cart->currency !== $currency) {
                // Impossible through the UI, and cheap to refuse. Adding two
                // currencies produces a number with no meaning.
                throw new ApiException(
                    ApiErrorCode::CartRestaurantConflict,
                    'That item is priced in a different currency to your cart.',
                );
            }

            return $cart;
        }

        return $this->create($customer, $trip, $restaurant, $currency);
    }

    private function create(
        User $customer,
        Trip $trip,
        Restaurant $restaurant,
        string $currency,
    ): Cart {
        $ttl = (int) config('foodonthego.cart.ttl_seconds');

        $cart = new Cart;

        try {
            $cart->forceFill([
                'uuid' => (string) Str::uuid(),
                'customer_id' => $customer->id,
                'trip_id' => $trip->id,
                'restaurant_id' => $restaurant->id,
                'status' => CartStatus::Active,
                'currency' => $currency,
                'last_activity_at' => now(),
                'expires_at' => now()->addSeconds($ttl),
            ])->save();
        } catch (QueryException $e) {
            // The unique index fired: another request created this customer's
            // cart for this journey between the read above and this write. The
            // other request's cart is the right one to use.
            $raced = $this->activeCartFor($customer, $trip);

            if ($raced === null) {
                throw $e;
            }

            return $raced;
        }

        return $cart;
    }

    /**
     * @throws ApiException
     */
    private function createLine(
        Cart $cart,
        ResolvedCustomization $resolved,
        PricedCustomization $priced,
    ): CartItem {
        $maxLines = (int) config('foodonthego.cart.max_lines');

        if (CartItem::query()->where('cart_id', $cart->id)->count() >= $maxLines) {
            throw new ApiException(
                ApiErrorCode::CartLineLimitReached,
                'Your cart is full. Remove something before adding more.',
                ['max_lines' => $maxLines],
            );
        }

        $item = new CartItem;

        $item->forceFill([
            'uuid' => (string) Str::uuid(),
            'cart_id' => $cart->id,
            'restaurant_id' => $cart->restaurant_id,
            'menu_item_id' => $resolved->item->id,
            'menu_item_variant_id' => $resolved->variant?->id,

            // Snapshots. A restaurant that renames a dish tomorrow must not
            // rewrite what the customer chose today.
            'item_name_snapshot' => $resolved->item->name,
            'variant_name_snapshot' => $resolved->variant?->name,

            'unit_price_minor' => $priced->unitPrice->minor,
            'line_total_minor' => $priced->lineTotal->minor,
            'currency' => $priced->unitPrice->currency,
            'quantity' => $resolved->quantity,
            'special_instructions' => $resolved->specialInstructions,
            'configuration_hash' => $resolved->fingerprint,
        ])->save();

        $order = 0;

        /** @var list<CartItemModifier> $written */
        $written = [];

        foreach ($resolved->modifiers as $pair) {
            $modifier = new CartItemModifier;

            $modifier->forceFill([
                'cart_item_id' => $item->id,
                'menu_modifier_group_id' => $pair['group']->id,
                'menu_modifier_option_id' => $pair['option']->id,
                'group_name_snapshot' => $pair['group']->name,
                'option_name_snapshot' => $pair['option']->name,
                'price_delta_minor' => (int) $pair['option']->price_delta_minor,
                'currency' => $priced->unitPrice->currency,
                'display_order' => $order++,
            ])->save();

            $written[] = $modifier;
        }

        // Attached rather than re-read. These are the rows just written, in the
        // order just written; going back to the database for them would be two
        // queries to learn something already in hand.
        $item->setRelation('modifiers', new Collection($written));

        return $item;
    }

    /**
     * The same configuration, added again.
     *
     * Merged rather than duplicated: two identical lines in a cart is a
     * presentation bug the customer has to mentally add up. The unit price is
     * refreshed to the one just calculated, because that is the figure the
     * customer has this moment agreed to.
     *
     * @throws ApiException
     */
    private function increaseLine(
        CartItem $item,
        ResolvedCustomization $resolved,
        PricedCustomization $priced,
    ): CartItem {
        $quantity = (int) $item->quantity + $resolved->quantity;
        $max = (int) config('foodonthego.cart.max_quantity_per_line');

        if ($quantity > $max) {
            throw new ApiException(
                ApiErrorCode::QuantityLimitExceeded,
                "You can have up to {$max} of one item. Your cart already has ".$item->quantity.'.',
                ['max_quantity' => $max, 'in_cart' => (int) $item->quantity],
            );
        }

        $item->forceFill([
            'quantity' => $quantity,
            'unit_price_minor' => $priced->unitPrice->minor,
            'line_total_minor' => $priced->unitPrice->minor * $quantity,
        ])->save();

        return $item->fresh(['modifiers']) ?? $item;
    }
}
