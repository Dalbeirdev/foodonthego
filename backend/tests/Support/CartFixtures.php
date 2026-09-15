<?php

declare(strict_types=1);

namespace Tests\Support;

use App\Models\Cart;
use App\Models\CartItem;
use App\Models\MenuItem;
use App\Models\MenuItemVariant;
use App\Models\Restaurant;
use App\Models\Trip;
use App\Models\User;
use App\Services\Cart\CartService;
use Illuminate\Support\Str;

/**
 * Carts built straight onto the table.
 *
 * Deliberately NOT through {@see CartService}. A test of
 * pickup planning that had to drive the whole pricing pipeline to get a cart
 * would fail when pricing broke, and a red test that points at the wrong
 * service is worse than no test — somebody spends an afternoon in the planner
 * looking for a bug that is in the repricer.
 *
 * Every API-level test still goes through the real endpoints. This is for the
 * services underneath them.
 */
final class CartFixtures
{
    public static function activeCart(User $customer, Trip $trip, Restaurant $restaurant): Cart
    {
        $cart = new Cart;

        $cart->forceFill([
            'uuid' => (string) Str::uuid(),
            'customer_id' => $customer->id,
            'trip_id' => $trip->id,
            'restaurant_id' => $restaurant->id,
            'status' => 'ACTIVE',
            'currency' => 'INR',
            'version' => 1,
            'pickup_selection_status' => 'NONE',
            'last_activity_at' => now(),
            'expires_at' => now()->addSeconds((int) config('foodonthego.cart.ttl_seconds')),
        ])->save();

        return $cart;
    }

    /**
     * One line. The prices are arbitrary and never asserted here — pickup
     * planning is about time, and a test that also pinned money would be two
     * tests wearing one name.
     */
    public static function line(
        Cart $cart,
        MenuItem $item,
        int $quantity = 1,
        ?MenuItemVariant $variant = null,
    ): CartItem {
        $line = new CartItem;

        $line->forceFill([
            'uuid' => (string) Str::uuid(),
            'cart_id' => $cart->id,
            'restaurant_id' => $cart->restaurant_id,
            'menu_item_id' => $item->id,
            'menu_item_variant_id' => $variant?->id,
            'item_name_snapshot' => $item->name,
            'variant_name_snapshot' => $variant?->name,
            'unit_price_minor' => $variant?->price_minor ?? $item->base_price_minor,
            'line_total_minor' => ($variant?->price_minor ?? $item->base_price_minor) * $quantity,
            'currency' => 'INR',
            'quantity' => $quantity,
            'special_instructions' => null,
            // Unique per line, which is all the tests below need of it. The
            // real canonical hash is the service's job and is tested there.
            'configuration_hash' => hash('sha256', (string) Str::uuid()),
        ])->save();

        return $line;
    }
}
