<?php

declare(strict_types=1);

namespace App\Services\Checkout;

use App\Enums\CheckoutQuoteStatus;
use App\Models\Cart;
use App\Models\CheckoutQuote;
use App\Models\Trip;
use App\Models\User;
use App\Services\Pickup\PreCheckoutValidationService;
use App\Support\Checkout\CheckoutFingerprint;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\DB;

/**
 * Turning a validated cart into a short-lived, authoritative offer.
 *
 * Everything that could make a checkout wrong is re-checked here through
 * Module 13's {@see PreCheckoutValidationService} — the cart's prices and
 * availability, the restaurant, the journey, the pickup selection — rather than
 * through a second set of rules that would drift from it.
 *
 * **No amount comes from a request.** This service is never handed a subtotal, a
 * tax figure, a discount or a total; there is no parameter for one. Every
 * number it writes it worked out from rows, through
 * {@see CommercialCalculationService}, which in turn defers to Module 12's
 * single money path.
 *
 * ## What it does not do
 *
 * It creates no order and no payment. It reserves no stock: a long-lived
 * reservation has real consequences for other customers and is not something to
 * introduce as a side effect of somebody opening a screen. And it calls no
 * payment provider — Module 15 owns that boundary entirely.
 */
final class CheckoutPreparationService
{
    public function __construct(
        private readonly PreCheckoutValidationService $preCheckout,
        private readonly CommercialCalculationService $commercial,
    ) {}

    /**
     * Prepares, or refreshes, this cart's checkout.
     *
     * Refreshing rather than accumulating: reopening the screen, or a retry
     * after a lost response, supersedes the previous quote instead of adding to
     * a pile of them. A customer has one checkout in flight because they have
     * one cart.
     */
    public function prepare(User $customer, Trip $trip, Cart $cart, ?CarbonImmutable $now = null): CheckoutPreparation
    {
        $now ??= CarbonImmutable::now();

        $validation = $this->preCheckout->validate($trip, $cart, $now);
        $breakdown = $this->commercial->breakdownFor($cart);

        if (! $validation->readyForCheckout()) {
            // Nothing is written for a cart that cannot be paid for. A quote is
            // an offer, and offering a price for a basket with a sold-out dish
            // in it is an offer nobody can accept.
            return new CheckoutPreparation(
                quote: null,
                status: CheckoutQuoteStatus::Stale,
                validation: $validation,
                breakdown: $breakdown,
            );
        }

        $quote = $this->write($customer, $trip, $cart, $breakdown, $now);

        return new CheckoutPreparation(
            quote: $quote,
            status: CheckoutQuoteStatus::Active,
            validation: $validation,
            breakdown: $breakdown,
        );
    }

    /**
     * Re-checks an existing quote without minting a new one.
     *
     * The payment-readiness question. Everything `prepare` checked, plus the
     * quote itself: that it is this customer's, on this cart, unexpired,
     * unconsumed, and still quoted against facts that have not moved.
     */
    public function validateQuote(
        User $customer,
        Trip $trip,
        Cart $cart,
        CheckoutQuote $quote,
        ?CarbonImmutable $now = null,
    ): CheckoutPreparation {
        $now ??= CarbonImmutable::now();

        $validation = $this->preCheckout->validate($trip, $cart, $now);
        $breakdown = $this->commercial->breakdownFor($cart);

        $status = $quote->effectiveStatus($cart, $now);

        return new CheckoutPreparation(
            quote: $quote,
            status: $status,
            validation: $validation,
            breakdown: $breakdown,
        );
    }

    /**
     * Writes the offer down.
     *
     * In a transaction with the supersede, so a customer cannot end up holding
     * two ACTIVE quotes because two taps arrived together. The previous one is
     * marked consumed-by-supersession rather than deleted: what was offered is
     * worth keeping even after it stops being offered.
     */
    private function write(
        User $customer,
        Trip $trip,
        Cart $cart,
        CommercialBreakdown $breakdown,
        CarbonImmutable $now,
    ): CheckoutQuote {
        $ttl = max(1, (int) config('foodonthego.checkout.quote_ttl_minutes'));

        return DB::transaction(function () use ($customer, $trip, $cart, $breakdown, $now, $ttl): CheckoutQuote {
            CheckoutQuote::query()
                ->where('cart_id', $cart->id)
                ->where('status', CheckoutQuoteStatus::Active->value)
                ->lockForUpdate()
                ->update(['status' => CheckoutQuoteStatus::Expired->value, 'updated_at' => $now]);

            $charge = static function (array $components, string $code): ?CommercialComponent {
                foreach ($components as $component) {
                    if ($component->code === $code) {
                        return $component;
                    }
                }

                return null;
            };

            $tax = $charge($breakdown->charges, 'TAX');
            $packaging = $charge($breakdown->charges, 'PACKAGING_FEE');
            $platform = $charge($breakdown->charges, 'PLATFORM_FEE');
            $discount = $charge($breakdown->discounts, 'DISCOUNT');

            $quote = new CheckoutQuote;

            // forceFill against names stated here, never a request array. The
            // customer cannot set an amount, a status, a fingerprint or an
            // expiry, and there is no field in either checkout request that
            // would reach one of these if they tried.
            $quote->forceFill([
                'customer_id' => $customer->id,
                'cart_id' => $cart->id,
                'trip_id' => $trip->id,
                'restaurant_id' => $cart->restaurant_id,
                'cart_version' => (int) $cart->version,

                'pickup_start_at' => $cart->requested_pickup_start_at?->setTimezone('UTC'),
                'pickup_end_at' => $cart->requested_pickup_end_at?->setTimezone('UTC'),
                'pickup_timezone' => $cart->pickup_timezone,

                'currency' => $cart->currency,
                'items_subtotal_minor' => $breakdown->itemsSubtotal->minor,

                'tax_minor' => $tax?->amount->minor ?? 0,
                'tax_configured' => $tax?->configured ?? false,
                'packaging_fee_minor' => $packaging?->amount->minor ?? 0,
                'packaging_fee_configured' => $packaging?->configured ?? false,
                'platform_fee_minor' => $platform?->amount->minor ?? 0,
                'platform_fee_configured' => $platform?->configured ?? false,
                'discount_minor' => $discount?->amount->minor ?? 0,
                'discount_configured' => $discount?->configured ?? false,
                'other_adjustment_minor' => 0,
                'other_adjustment_configured' => false,

                'payable_total_minor' => $breakdown->payableTotal->minor,

                'status' => CheckoutQuoteStatus::Active->value,
                'fingerprint' => CheckoutFingerprint::of($cart),
                'commercial_rule_version' => (int) config('foodonthego.checkout.commercial_rule_version'),
                'expires_at' => $now->addMinutes($ttl),
            ])->save();

            return $quote;
        });
    }
}
