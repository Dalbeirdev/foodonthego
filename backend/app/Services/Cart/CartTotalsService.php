<?php

declare(strict_types=1);

namespace App\Services\Cart;

use App\Models\Cart;
use App\Support\Money;

/**
 * What the customer owes, worked out on the server.
 *
 * The one place in the project that turns a cart into a total. Not in a
 * controller and not in a resource: a figure a customer is asked to pay should
 * be produced by something that can be tested on its own and read in one sitting.
 *
 * **No rate here is invented.** The tax rate and both fees are configuration and
 * data, and every one of them defaults to nothing — see the `cart` block in
 * config/foodonthego.php for why a plausible default would be worse than a
 * visible zero.
 */
final class CartTotalsService
{
    public function totalsFor(Cart $cart): CartTotals
    {
        return $this->totalsForSubtotal($cart, $cart->subtotalMinor());
    }

    /**
     * The same charges, over a subtotal the caller worked out.
     *
     * Revalidation needs to answer "what would this cost if you accepted every
     * price change", and the honest way to answer it is with the cart's own
     * tax and fee rules over a different subtotal — not with a second copy of
     * those rules that happens to agree today.
     *
     * The cart is still the authority on the currency and on whose charges
     * apply. Only the figure being charged on is the caller's.
     */
    public function totalsForSubtotal(Cart $cart, int $subtotal): CartTotals
    {
        $currency = $cart->currency;

        $tax = $this->taxOn($subtotal, $this->rateBpsFor($cart));

        $packaging = (int) ($cart->restaurant?->packaging_fee_minor ?? 0);
        $platform = (int) config('foodonthego.cart.platform_fee_minor');

        // A cart with nothing in it costs nothing. Charging a packaging fee on
        // an empty cart is the kind of arithmetic that is technically what the
        // formula says and obviously wrong to the person reading the screen.
        if ($subtotal === 0) {
            $tax = 0;
            $packaging = 0;
            $platform = 0;
        }

        return new CartTotals(
            subtotal: Money::fromMinor($subtotal, $currency),
            tax: Money::fromMinor($tax, $currency),
            packagingFee: Money::fromMinor($packaging, $currency),
            platformFee: Money::fromMinor($platform, $currency),
            total: Money::fromMinor($subtotal + $tax + $packaging + $platform, $currency),
        );
    }

    /**
     * The restaurant's rate, or the platform's if it has none.
     *
     * Null and zero are different answers. Null is "nobody has configured this
     * restaurant", and falls back. Zero is "this restaurant is deliberately not
     * taxed", and does not. Collapsing the two would make an unconfigured
     * restaurant indistinguishable from a tax-exempt one, and the difference
     * matters to whoever has to explain a bill.
     */
    private function rateBpsFor(Cart $cart): int
    {
        $own = $cart->restaurant?->tax_rate_bps;

        if ($own !== null) {
            return (int) $own;
        }

        return (int) config('foodonthego.cart.tax_rate_bps');
    }

    /**
     * Tax on the whole subtotal, once, rounded half up to the minor unit.
     *
     * On the subtotal rather than per line, deliberately. Rounding each line
     * separately drifts: twenty lines each rounded up by half a paisa is ten
     * paise the customer cannot account for, and their own arithmetic will not
     * reproduce the figure on the screen. One rounding, at the end, is the one
     * a customer can check.
     *
     * Integer arithmetic throughout. `intdiv` on the way out rather than a cast
     * from a float, because a float would make the rounding rule a property of
     * IEEE 754 rather than a decision anybody made.
     */
    private function taxOn(int $subtotalMinor, int $rateBps): int
    {
        if ($rateBps <= 0 || $subtotalMinor <= 0) {
            return 0;
        }

        // + 5000 then divide by 10000 is "round half up", in integers.
        return intdiv($subtotalMinor * $rateBps + 5_000, 10_000);
    }
}
