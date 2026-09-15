<?php

declare(strict_types=1);

namespace Tests\Unit;

use App\Models\Cart;
use App\Models\CartItem;
use App\Models\Restaurant;
use App\Services\Cart\CartTotalsService;
use Illuminate\Database\Eloquent\Collection;
use Tests\TestCase;

/**
 * The arithmetic of an order summary, on its own.
 *
 * Feature tests prove the figures reach the wire. These prove the figures are
 * right, at the boundaries where money goes wrong: rounding half a paisa, a
 * rate of nought that is not the same as no rate, and the difference between
 * dividing once and dividing twenty times.
 *
 * No database. The models are built in memory and their relations set by hand,
 * so what is under test is the calculation and nothing else.
 */
final class CartTotalsTest extends TestCase
{
    private function service(): CartTotalsService
    {
        return new CartTotalsService;
    }

    /**
     * A cart holding lines of the given totals, at a restaurant with the given
     * charges.
     *
     * @param  list<int>  $lineTotals
     */
    private function cart(array $lineTotals, ?int $taxRateBps = null, int $packagingMinor = 0): Cart
    {
        $restaurant = new Restaurant;
        $restaurant->forceFill([
            'tax_rate_bps' => $taxRateBps,
            'packaging_fee_minor' => $packagingMinor,
        ]);

        $cart = new Cart;
        $cart->forceFill(['currency' => 'INR']);

        $items = new Collection(array_map(static function (int $minor): CartItem {
            $item = new CartItem;
            $item->forceFill(['line_total_minor' => $minor, 'currency' => 'INR']);

            return $item;
        }, $lineTotals));

        $cart->setRelation('items', $items);
        $cart->setRelation('restaurant', $restaurant);

        return $cart;
    }

    public function test_the_parts_always_add_up_to_the_total(): void
    {
        config(['foodonthego.cart.platform_fee_minor' => 1_500]);

        $totals = $this->service()->totalsFor(
            $this->cart([24_900, 32_900, 4_900], taxRateBps: 500, packagingMinor: 2_000),
        );

        $this->assertSame(62_700, $totals->subtotal->minor);
        $this->assertSame(3_135, $totals->tax->minor);
        $this->assertSame(2_000, $totals->packagingFee->minor);
        $this->assertSame(1_500, $totals->platformFee->minor);

        $this->assertSame(
            $totals->subtotal->minor + $totals->tax->minor
                + $totals->packagingFee->minor + $totals->platformFee->minor,
            $totals->total->minor,
        );
    }

    public function test_tax_is_rounded_half_up_to_the_paisa(): void
    {
        // 5% of 10 = 0.5 of a paisa. Half up is 1, not 0.
        $this->assertSame(1, $this->service()->totalsFor(
            $this->cart([10], taxRateBps: 500),
        )->tax->minor);

        // Just under a half rounds down.
        $this->assertSame(0, $this->service()->totalsFor(
            $this->cart([9], taxRateBps: 500),
        )->tax->minor);
    }

    public function test_tax_is_taken_on_the_subtotal_once_rather_than_line_by_line(): void
    {
        // Twenty lines of 33 paise at 5%: each line is 1.65 paise, which rounds
        // to 2 individually — twenty times two is 40. Once on the subtotal of
        // 660 it is 33.
        //
        // Seven paise the customer cannot account for, on a cart worth six
        // rupees. The drift scales with the number of lines, and their own
        // arithmetic will never reproduce the figure on the screen.
        $lines = array_fill(0, 20, 33);

        $totals = $this->service()->totalsFor($this->cart($lines, taxRateBps: 500));

        $this->assertSame(660, $totals->subtotal->minor);
        $this->assertSame(33, $totals->tax->minor);
        $this->assertNotSame(40, $totals->tax->minor);
    }

    public function test_a_restaurant_taxed_at_zero_does_not_fall_back_to_the_platform(): void
    {
        config(['foodonthego.cart.tax_rate_bps' => 1_800]);

        $this->assertSame(0, $this->service()->totalsFor(
            $this->cart([50_000], taxRateBps: 0),
        )->tax->minor);
    }

    public function test_an_unconfigured_restaurant_uses_the_platform_rate(): void
    {
        config(['foodonthego.cart.tax_rate_bps' => 1_800]);

        $this->assertSame(9_000, $this->service()->totalsFor(
            $this->cart([50_000], taxRateBps: null),
        )->tax->minor);
    }

    public function test_an_empty_cart_is_free(): void
    {
        config(['foodonthego.cart.platform_fee_minor' => 1_500]);

        $totals = $this->service()->totalsFor(
            $this->cart([], taxRateBps: 500, packagingMinor: 2_000),
        );

        // Not 3 500. A packaging fee on a cart with nothing to package is
        // technically what the formula says and obviously wrong to the person
        // reading the screen.
        $this->assertSame(0, $totals->subtotal->minor);
        $this->assertSame(0, $totals->tax->minor);
        $this->assertSame(0, $totals->packagingFee->minor);
        $this->assertSame(0, $totals->platformFee->minor);
        $this->assertSame(0, $totals->total->minor);
    }

    public function test_everything_carries_the_carts_currency(): void
    {
        $totals = $this->service()->totalsFor($this->cart([24_900], taxRateBps: 500));

        foreach ([$totals->subtotal, $totals->tax, $totals->packagingFee, $totals->platformFee, $totals->total] as $money) {
            // An amount without its currency is not a price. Adding a rupee
            // figure to a dollar one produces a number with no meaning, and
            // this is what stops the breakdown ever containing two.
            $this->assertSame('INR', $money->currency);
        }
    }

    public function test_the_rounding_rule_is_a_decision_and_not_a_property_of_ieee_754(): void
    {
        // 7.25% of 200 paise is 14.5 exactly, and half up is 15.
        //
        // A float gets 14. Not because rounding is hard, but because
        // 200 * 0.0725 evaluates to 14.499999999999998 in binary — it lands
        // *below* the halfway point it is mathematically equal to, and rounds
        // the other way. The customer is short-changed a paisa by the encoding
        // rather than by anybody's rule.
        //
        // This is the negative control for the whole integer-money argument,
        // and it is a real divergence rather than an illustrative one: run
        // `(int) round(200 * (725 / 10000.0))` and it answers 14.
        $this->assertSame(14, (int) round(200 * (725 / 10_000.0)), 'the float path still disagrees');

        $this->assertSame(15, $this->service()->totalsFor(
            $this->cart([200], taxRateBps: 725),
        )->tax->minor);
    }

    public function test_the_arithmetic_stays_exact_at_large_amounts(): void
    {
        // 18% of 999 999.99 is 179 999.9982, which rounds to 180 000.00. No
        // accumulated drift, because nothing accumulates: one multiplication
        // and one division, both in integers.
        $totals = $this->service()->totalsFor(
            $this->cart([99_999_999], taxRateBps: 1_800),
        );

        $this->assertSame(18_000_000, $totals->tax->minor);
        $this->assertSame(117_999_999, $totals->total->minor);
    }
}
