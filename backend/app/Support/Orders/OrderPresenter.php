<?php

declare(strict_types=1);

namespace App\Support\Orders;

use App\Enums\OrderStatus;
use App\Models\Order;
use App\Models\OrderItem;
use App\Models\Payment;
use App\Services\Orders\OrderStateMachine;
use App\Services\Orders\OrderTimelineService;
use Carbon\CarbonInterface;
use Illuminate\Support\Facades\Date;

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

            /*
             | Module 17. The status, said in words the customer can read.
             |
             | Sent with every order rather than mapped on the phone, so a new
             | lifecycle state is a backend deploy rather than an app-store
             | release -- and so an app that has never heard of a state shows a
             | sentence instead of a raw enum value.
             */
            'status_title' => OrderStatusCopy::title($order->status),
            'status_subtitle' => OrderStatusCopy::subtitle($order->status),

            /*
             | Increments on every status transition.
             |
             | The client uses it to discard a response that overtook a newer
             | one. It must never be used to guess a state the server has not
             | sent: it says which answer is fresher, not what comes next.
             */
            'order_version' => (int) $order->order_version,

            'status_updated_at' => self::local(self::statusChangedAt($order), $zone),

            /*
             | Whether anything can still happen to this order.
             |
             | Decided from the transition table rather than from a list the
             | client keeps, so a client stops polling a terminal order without
             | having to know which states are terminal.
             */
            'is_active' => in_array($order->status, OrderStateMachine::activeStatuses(), strict: true),
        ];
    }

    /**
     * When the order last moved, from the milestone that matches its state.
     *
     * Read off the order row rather than from the history table: the Orders tab
     * lists many orders and must not join a history table per row to say
     * "updated 4 minutes ago".
     */
    private static function statusChangedAt(Order $order): ?CarbonInterface
    {
        return match ($order->status) {
            OrderStatus::Placed => $order->placed_at,
            OrderStatus::Accepted => $order->accepted_at,
            OrderStatus::Rejected => $order->rejected_at,
            OrderStatus::Cooking => $order->cooking_started_at,
            OrderStatus::Ready => $order->ready_at,
            OrderStatus::PickedUp => $order->picked_up_at,
            OrderStatus::Cancelled => $order->cancelled_at,
            default => $order->updated_at,
        };
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
    /**
     * Everything the tracking screen needs, and nothing it does not.
     *
     * ONE ENDPOINT, ONE SCREEN. Module 17 enriches the existing order detail
     * response rather than adding a parallel /tracking route: the two would
     * return almost the same thing, and the first time they drifted a customer
     * would see one status on a list and a different one on a screen.
     *
     * NOT INCLUDED, deliberately: the pickup code and QR token. They stay on
     * their own endpoint behind their own request, because tracking is polled
     * and a credential that rode along would travel every few seconds through
     * every proxy in between. What is included is whether one is available --
     * a boolean is not a credential.
     *
     * @return array<string, mixed>
     */
    public static function tracking(Order $order, OrderTimelineService $timeline): array
    {
        $order->loadMissing(['items.modifiers', 'restaurant', 'statusHistory']);

        return [
            ...self::detail($order),
            'timeline' => $timeline->forCustomer($order, self::zone($order)),

            /*
             | The customer-safe half of why an order ended badly.
             |
             | Null is the ordinary case and is not a gap: most exceptions have
             | nothing safe to add beyond the status itself, and an empty string
             | here would push the client into rendering a blank explanation.
             */
            'customer_safe_reason' => $order->customer_safe_reason,

            'pickup_credential' => [
                /*
                 | Available from placement, not from READY.
                 |
                 | The credential is derived from the order and exists the
                 | moment the order does, so hiding it until READY would be a
                 | UI fiction rather than a security boundary -- and a customer
                 | who arrives early would be told they have no code when they
                 | do. The tracking screen says when to use it instead.
                 */
                'available' => $order->status->isPlacedOrder() && ! $order->status->isTerminal(),
                'expires_at' => self::local($order->pickup_token_expires_at, self::zone($order)),
            ],

            /*
             | The server's clock, sent so the client can say how stale it is.
             |
             | A phone's own clock may be wrong by hours, and "updated 4 minutes
             | ago" computed against a wrong clock is worse than no freshness
             | indicator at all.
             */
            'server_time' => self::local(Date::now(), self::zone($order)),
        ];
    }

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

    /**
     * The clock every instant in an order response is rendered on.
     *
     * PUBLIC because Module 17 added a second producer of instants -- the
     * timeline -- and a second copy of this rule would be a second clock. The
     * invariant that one response carries one timezone is asserted by
     * OrderAndPaymentApiTest, and it caught exactly that mistake when the
     * timeline first shipped in UTC.
     */
    public static function zone(Order $order): string
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
    public static function local(?CarbonInterface $instant, string $zone): ?string
    {
        if ($instant === null) {
            return null;
        }

        return $instant->toImmutable()->setTimezone($zone)->toIso8601String();
    }
}
