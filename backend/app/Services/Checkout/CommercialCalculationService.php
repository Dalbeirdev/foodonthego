<?php

declare(strict_types=1);

namespace App\Services\Checkout;

use App\Models\Cart;
use App\Services\Cart\CartTotals;
use App\Services\Cart\CartTotalsService;
use App\Support\Money;

/**
 * What the customer will pay, and which of it anybody actually chose.
 *
 * **This class re-implements no arithmetic.** Module 12's
 * {@see CartTotalsService} remains the only thing in this project that turns a
 * cart into a total, and this consumes it. A second implementation would be a
 * second answer, and the day they disagree the customer is charged by whichever
 * one happens to run first.
 *
 * What Module 14 adds is not maths. It is **provenance**: for each component,
 * whether a human set it or whether it is simply absent. The totals service
 * cannot answer that — it returns a figure, and nought is a perfectly good
 * figure — so the question is asked here, against the same sources it read.
 *
 * ## Nothing here is invented
 *
 * There is no tax rule, packaging rule, platform fee or discount written into
 * this class. Every component is read from configuration or from a restaurant's
 * own row, and a component nobody has set does not appear at all.
 *
 * Discounts and coupons have **no mechanism in this project**. The component
 * exists so that adding one later is a change here rather than a change to the
 * shape of every response, and a test asserts it stays absent for as long as
 * nothing can set it.
 */
final class CommercialCalculationService
{
    public function __construct(private readonly CartTotalsService $totals) {}

    public function breakdownFor(Cart $cart): CommercialBreakdown
    {
        return $this->breakdownForSubtotal($cart, $cart->subtotalMinor());
    }

    /**
     * The same components over a subtotal the caller worked out.
     *
     * Checkout prices what the cart holds *now*, which is the cart's own
     * subtotal; the parameter exists so a caller pricing a revalidated basket
     * uses the cart's rules rather than a second copy of them.
     */
    public function breakdownForSubtotal(Cart $cart, int $subtotalMinor): CommercialBreakdown
    {
        $totals = $this->totals->totalsForSubtotal($cart, $subtotalMinor);
        $currency = $cart->currency;

        $charges = [
            new CommercialComponent(
                code: 'TAX',
                amount: $totals->tax,
                configured: $this->taxIsConfigured($cart),
                basis: $this->taxBasis($cart),
            ),
            new CommercialComponent(
                code: 'PACKAGING_FEE',
                amount: $totals->packagingFee,
                configured: $cart->restaurant?->packaging_fee_minor !== null,
                basis: 'restaurant',
            ),
            new CommercialComponent(
                code: 'PLATFORM_FEE',
                amount: $totals->platformFee,
                configured: $this->platformFeeIsConfigured(),
                basis: 'platform',
            ),
        ];

        $discounts = [
            // Always unconfigured, and that is not a placeholder. No coupon,
            // promotion or discount mechanism exists in this project; there is
            // nothing that could set this, and a test asserts as much so that
            // the day one is built, the assertion is what fails.
            new CommercialComponent(
                code: 'DISCOUNT',
                amount: Money::fromMinor(0, $currency),
                configured: false,
                basis: null,
            ),
        ];

        return new CommercialBreakdown(
            itemsSubtotal: $totals->subtotal,
            charges: $charges,
            discounts: $discounts,
            // From the totals service, not re-added here. Summing the
            // components again would be the second implementation this class
            // exists to avoid.
            payableTotal: $totals->total,
        );
    }

    /** The totals themselves, where a caller needs the Module 12 shape too. */
    public function totalsFor(Cart $cart): CartTotals
    {
        return $this->totals->totalsFor($cart);
    }

    /**
     * Whether anybody has set a tax rule that reaches this cart.
     *
     * A restaurant's own rate counts **even when it is nought**: an operator who
     * has explicitly recorded "no tax here" has made a decision, and the screen
     * should show it. A null rate falls through to the platform's, which counts
     * only when it is non-zero — a platform default of nought is the absence of
     * a rule, not a rule.
     */
    private function taxIsConfigured(Cart $cart): bool
    {
        if ($cart->restaurant?->tax_rate_bps !== null) {
            return true;
        }

        return (int) config('foodonthego.cart.tax_rate_bps') > 0;
    }

    private function taxBasis(Cart $cart): string
    {
        return $cart->restaurant?->tax_rate_bps !== null ? 'restaurant' : 'platform';
    }

    /**
     * A platform fee of nought is not a fee.
     *
     * Unlike the restaurant's tax rate there is no null here to read: the config
     * cast makes it an integer either way, so an unset fee and a fee set to
     * nothing are indistinguishable. Treated as absent, which is the reading
     * that cannot put a phantom charge on a screen.
     */
    private function platformFeeIsConfigured(): bool
    {
        return (int) config('foodonthego.cart.platform_fee_minor') > 0;
    }
}
