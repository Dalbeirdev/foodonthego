<?php

declare(strict_types=1);

namespace App\Support\Orders;

use App\Models\Order;
use App\Models\OrderItem;
use App\Models\Payment;
use Carbon\CarbonInterface;

/**
 * One order, rendered for an API response.
 *
 * **One response, one clock.** Every instant in the body goes through
 * {@see local()}, so the whole thing reads on a single zone. Module 14 learned
 * this the expensive way: a body with five instants in UTC beside two at
 * `+05:30` renders a pickup window hours in the customer's past, on the screen
 * where they agree to pay. `test_every_instant_in_one_order_response_is_on_one_clock`
 * walks the whole body and fails on a second offset, which is what stops a
 * future `toIso8601String()` from creeping back in.
 *
 * The clock is the one **stored on the order**, not the restaurant's current
 * one. Those are the same in every ordinary case, and where they differ the
 * stored one is right: a restaurant that changes timezone has not retroactively
 * changed when a customer was told to collect their food.
 */
final class OrderPresenter
{
    /**
     * The order without its payment detail.
     *
     * @return array<string, mixed>
     */
    public static function summary(Order $order): array
    {
        $zone = self::zone($order);

        return [
            'id' => $order->uuid,
            'order_number' => $order->order_number,
            'status' => $order->status->value,
            'currency' => $order->currency,

            'restaurant' => [
                'id' => $order->restaurant?->uuid,
                'name' => $order->restaurant?->name,
            ],

            'pickup' => [
                'start_at' => self::local($order->pickup_start_at, $zone),
                'end_at' => self::local($order->pickup_end_at, $zone),
                'timezone' => $zone,
            ],

            'commercial' => self::commercial($order),

            'placed_at' => self::local($order->placed_at, $zone),
            'paid_at' => self::local($order->paid_at, $zone),
            'cancelled_at' => self::local($order->cancelled_at, $zone),
        ];
    }

    /**
     * The order with its lines and the state of its payment.
     *
     * @return array<string, mixed>
     */
    public static function detail(Order $order): array
    {
        $order->loadMissing(['items.modifiers', 'restaurant']);

        return [
            ...self::summary($order),
            'items' => $order->items->map(self::item(...))->all(),
            'payment' => self::payment($order),
        ];
    }

    /**
     * What the app needs to open a provider checkout.
     *
     * The public key id is included because the client SDK requires it and it is
     * public by definition. **The key secret is not here, is not in any response
     * in this project, and must never be** — it is the thing that makes a
     * signature mean something.
     *
     * The amount is echoed for display only. The client does not send it back and
     * the server would not read it if it did.
     *
     * @return array<string, mixed>
     */
    public static function intent(Order $order, Payment $payment): array
    {
        return [
            'order' => self::summary($order),
            'payment' => [
                'id' => $payment->uuid,
                'provider' => $payment->provider,
                'provider_order_id' => $payment->provider_order_id,
                'status' => $payment->status->value,
                'amount' => [
                    'amount_minor' => $payment->amount_minor,
                    'currency' => $payment->currency,
                ],
                'public_key_id' => (string) config('services.razorpay.key_id'),
            ],
        ];
    }

    /** @return array<string, mixed>|null */
    private static function payment(Order $order): ?array
    {
        $payment = $order->settledPayment()
            ?? $order->payments()->orderByDesc('id')->first();

        if ($payment === null) {
            return null;
        }

        return [
            'id' => $payment->uuid,
            'status' => $payment->status->value,
            'provider' => $payment->provider,
            'provider_order_id' => $payment->provider_order_id,
            // Deliberately not the failure reason. A provider's decline text is
            // written for a merchant dashboard, and relaying it verbatim to a
            // customer tells them things about a card that are not ours to say.
            'verified_at' => self::local($payment->verified_at, self::zone($order)),
            'verification_source' => $payment->verification_source?->value,
        ];
    }

    /** @return array<string, mixed> */
    private static function item(OrderItem $item): array
    {
        return [
            'id' => $item->uuid,
            'name' => $item->item_name_snapshot,
            'variant' => $item->variant_name_snapshot,
            'quantity' => $item->quantity,
            'unit_price' => ['amount_minor' => $item->unit_price_minor, 'currency' => $item->currency],
            'line_total' => ['amount_minor' => $item->line_total_minor, 'currency' => $item->currency],
            'special_instructions' => $item->special_instructions,
            'modifiers' => $item->modifiers->map(static fn ($m): array => [
                'group' => $m->group_name_snapshot,
                'option' => $m->option_name_snapshot,
                'price_delta' => ['amount_minor' => $m->price_delta_minor, 'currency' => $m->currency],
            ])->all(),
        ];
    }

    /**
     * The money, in the shape a checkout screen already renders.
     *
     * A charge appears only if it was configured. "Not configured" and
     * "configured as nought" are different facts, and an order showing
     * "Tax 0.00" for the first tells a customer a decision was made when none
     * was — the same rule the quote follows, carried onto the order so the
     * receipt and the checkout screen cannot disagree.
     *
     * @return array<string, mixed>
     */
    private static function commercial(Order $order): array
    {
        $charges = [];

        foreach ([
            ['tax', $order->tax_configured, $order->tax_minor],
            ['packaging_fee', $order->packaging_fee_configured, $order->packaging_fee_minor],
            ['platform_fee', $order->platform_fee_configured, $order->platform_fee_minor],
        ] as [$code, $configured, $minor]) {
            if ($configured) {
                $charges[] = [
                    'code' => $code,
                    'amount' => ['amount_minor' => $minor, 'currency' => $order->currency],
                ];
            }
        }

        $discounts = [];

        if ($order->discount_configured) {
            $discounts[] = [
                'code' => 'discount',
                'amount' => ['amount_minor' => $order->discount_minor, 'currency' => $order->currency],
            ];
        }

        return [
            'items_subtotal' => ['amount_minor' => $order->items_subtotal_minor, 'currency' => $order->currency],
            'charges' => $charges,
            'discounts' => $discounts,
            'payable_total' => ['amount_minor' => $order->payable_total_minor, 'currency' => $order->currency],
            'has_configured_adjustments' => $charges !== [] || $discounts !== [],
        ];
    }

    private static function zone(Order $order): string
    {
        $zone = $order->pickup_timezone;

        if (is_string($zone) && $zone !== '') {
            return $zone;
        }

        return $order->restaurant?->timezone ?? 'UTC';
    }

    /**
     * One instant, on this order's clock.
     *
     * `setTimezone` converts; it does not relabel. The instant is unchanged and
     * only the offset it is written with differs — which is the whole point, and
     * the distinction Module 13 got wrong once by formatting rather than
     * converting.
     */
    private static function local(?CarbonInterface $instant, string $zone): ?string
    {
        if ($instant === null) {
            return null;
        }

        return $instant->toImmutable()->setTimezone($zone)->toIso8601String();
    }
}
