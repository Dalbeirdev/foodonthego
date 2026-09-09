<?php

declare(strict_types=1);

namespace App\Services\Orders;

use App\Enums\CartStatus;
use App\Enums\CheckoutQuoteStatus;
use App\Enums\OrderStatus;
use App\Enums\PaymentStatus;
use App\Exceptions\Orders\OrderCreationRefused;
use App\Models\Order;
use App\Models\OutboxEvent;
use App\Models\Payment;
use Carbon\CarbonImmutable;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\Date;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

/**
 * One captured payment becomes at most one order. This is the only place it
 * happens.
 *
 * -------------------------------------------------------------------------
 * WHY ONE SERVICE AND NOT THREE HANDLERS
 * -------------------------------------------------------------------------
 *
 * A capture can reach this application three ways: the customer's app returns
 * with a signed callback, Razorpay posts a webhook, or a reconciliation sweep
 * notices a payment the provider considers captured and we do not. All three
 * are legitimate, all three can happen for the same payment, and two of them
 * can happen at the same moment.
 *
 * Written as three handlers they would drift — one would remember to consume
 * the checkout quote and one would not, and the difference would surface as a
 * customer who could pay twice for the same basket. So there is one entry
 * point, and the callers' only job is to say which payment.
 *
 * -------------------------------------------------------------------------
 * EXACTLY ONCE, WITHOUT PRETENDING TRANSPORT CAN DELIVER EXACTLY ONCE
 * -------------------------------------------------------------------------
 *
 * Nothing here tries to make delivery unique, because nothing can. Deliveries
 * are at-least-once and this operation is idempotent, which is the only
 * combination that survives a network.
 *
 * Three mechanisms, in order of who wins:
 *
 *   1. A row lock on the order, so two workers serialise rather than race.
 *   2. A status re-read INSIDE the lock, so the second worker sees the first
 *      one's work rather than the stale row it arrived holding.
 *   3. The unique index on orders.placed_from_payment_id, which is what
 *      actually guarantees the invariant. If the lock is ever bypassed — a
 *      replica, a future queue, a migration that drops it by accident — the
 *      database still refuses the second order, and the integrity violation is
 *      caught below and answered with the order that already exists.
 *
 * `if (!$exists)` appears nowhere as the guarantee. It appears as an
 * optimisation, and the comment above it says so.
 */
final class CreateOrderFromCapturedPayment
{
    public function __construct(
        private readonly OrderNumberGenerator $numbers,
        private readonly PickupCredentialService $credentials,
        private readonly OrderStateMachine $states,
    ) {}

    /**
     * Place the order for a captured payment, or return the one already placed.
     *
     * @throws OrderCreationRefused when the payment is not captured, or does not
     *                              agree with the order about money. Both are
     *                              conditions Module 15 owns resolving; this
     *                              service refuses rather than papering over
     *                              them, because an order written against a
     *                              payment that does not match it is worse than
     *                              no order at all.
     */
    public function place(Payment $payment, ?CarbonImmutable $now = null): Order
    {
        $now ??= Date::now()->toImmutable();

        try {
            return DB::transaction(fn (): Order => $this->write($payment, $now));
        } catch (QueryException $e) {
            // The database refused a second order for this payment. That is the
            // invariant working, not a failure: somebody else placed it between
            // our read and our write. Hand back theirs.
            $existing = Order::query()
                ->where('placed_from_payment_id', $payment->id)
                ->first();

            if ($existing !== null) {
                Log::info('orders.duplicate_creation_prevented', [
                    'payment_id' => $payment->id,
                    'order_id' => $existing->id,
                ]);

                return $existing;
            }

            throw $e;
        }
    }

    private function write(Payment $payment, CarbonImmutable $now): Order
    {
        // The order row, held for the duration. Everything below reads the
        // locked copy; the caller's instance may be stale and is refreshed at
        // the end rather than trusted at the start.
        $order = Order::query()
            ->lockForUpdate()
            ->findOrFail($payment->order_id);

        $payment = Payment::query()->lockForUpdate()->findOrFail($payment->id);

        // Already placed. Duplicate delivery is the ordinary case, not an
        // error, and the customer gets the same order they got the first time.
        if ($order->status === OrderStatus::Placed) {
            Log::info('orders.duplicate_creation_prevented', [
                'payment_id' => $payment->id,
                'order_id' => $order->id,
            ]);

            return $order;
        }

        $this->refuseUnlessCaptured($payment);
        $this->refuseUnlessAmountsAgree($order, $payment);

        $order->placed_from_payment_id = $payment->id;
        $order->order_number = $this->numbers->mint($now);

        // When the money actually arrived, taken from the payment rather than
        // from the clock. A reconciliation run finishing an order hours after
        // the capture must record the capture's time, not its own — otherwise
        // every delayed recovery quietly misreports when the customer paid.
        $order->paid_at = $payment->verified_at !== null
            ? CarbonImmutable::parse($payment->verified_at)
            : $now;

        $this->snapshotParties($order);
        $this->mintPickupCredentials($order, $now);

        // Status last among the order's own fields, so that a state machine
        // refusal cannot leave a half-populated order behind.
        $this->states->transition($order, OrderStatus::Placed, $now);
        $order->save();

        $this->closeTheBasket($order);

        // In the same transaction as the order. An OrderPlaced event that
        // survives a rolled-back order would tell a restaurant about food
        // nobody bought.
        OutboxEvent::queue(
            eventName: 'OrderPlaced',
            dedupeKey: (string) $order->uuid,
            payload: [
                'order_uuid' => (string) $order->uuid,
                'restaurant_id' => (int) $order->restaurant_id,
                'payment_uuid' => (string) $payment->uuid,
            ],
            now: $now,
        );

        Log::info('orders.placed', [
            'order_id' => $order->id,
            'payment_id' => $payment->id,
            'restaurant_id' => $order->restaurant_id,
            // Deliberately absent: the order number is fine to log, the pickup
            // code and token are not, and the safest way to keep them out is to
            // never build a context that could contain them.
            'order_number' => $order->order_number,
        ]);

        return $order;
    }

    private function refuseUnlessCaptured(Payment $payment): void
    {
        if ($payment->status !== PaymentStatus::Captured) {
            throw OrderCreationRefused::paymentNotCaptured($payment->status);
        }
    }

    /**
     * The money the provider took must be the money Module 14 said was owed.
     *
     * Compared against the ORDER's payable total, which was written from the
     * accepted quote — never against anything the client sent and never against
     * a figure recomputed from today's menu. A mismatch here means either a
     * tampered attempt or a genuine provider discrepancy, and both are Module
     * 15's to resolve. Placing the order anyway would convert an open question
     * about money into a delivered meal.
     */
    private function refuseUnlessAmountsAgree(Order $order, Payment $payment): void
    {
        if ((int) $payment->amount_minor !== (int) $order->payable_total_minor) {
            throw OrderCreationRefused::amountMismatch(
                (int) $order->payable_total_minor,
                (int) $payment->amount_minor,
            );
        }

        if (strtoupper((string) $payment->currency) !== strtoupper((string) $order->currency)) {
            throw OrderCreationRefused::currencyMismatch(
                (string) $order->currency,
                (string) $payment->currency,
            );
        }
    }

    /**
     * The minimum a counter needs to hand food to the right person.
     *
     * A name to call out and a number to ring. Not an email, not a date of
     * birth, not the other trips this customer has taken. The restaurant's own
     * details are copied for the same reason the dish names were: a rename must
     * not rewrite the confirmation somebody is holding.
     */
    private function snapshotParties(Order $order): void
    {
        $customer = $order->customer;
        $restaurant = $order->restaurant;

        $order->customer_name_snapshot = $customer?->name;
        // phone_e164, not phone.
        //
        // `users.phone` is a column from the original scaffold that Module 03's
        // authentication superseded and never populates — it is NULL for every
        // real customer. Reading it here wrote a blank snapshot, which is the
        // quiet kind of failure: nothing errors, and a restaurant simply has no
        // number to ring when somebody does not turn up for their food. Caught
        // by a test guard asserting the fixture was non-empty before checking
        // the value was absent from a QR payload.
        $order->customer_phone_snapshot = $customer?->phone_e164;
        $order->restaurant_name_snapshot = $restaurant?->name;
        $order->restaurant_address_snapshot = $restaurant?->formatted_address;
    }

    /**
     * Digests only. The plaintext is derived on demand for the owning customer
     * and is never written anywhere.
     */
    private function mintPickupCredentials(Order $order, CarbonImmutable $now): void
    {
        $digests = $this->credentials->digests($order);

        $order->pickup_code_hash = $digests->codeHash;
        $order->pickup_token_hash = $digests->tokenHash;

        $grace = (int) config('foodonthego.orders.pickup_credential_grace_hours', 24);

        // From the end of the pickup window, not from now: a credential that
        // expires while the customer is still driving toward the food is a
        // support call and a refund.
        $order->pickup_token_expires_at = ($order->pickup_end_at
            ? CarbonImmutable::parse($order->pickup_end_at)
            : $now)->addHours($grace);
    }

    /**
     * The basket and the quote are spent.
     *
     * Both are marked rather than deleted. The cart is the audit trail behind
     * the purchase, and the quote is the evidence of what was agreed — a
     * support question six months from now is answered by following the order
     * back through both.
     *
     * The quote is already CONSUMED by Module 14's placement path; asserting it
     * again here is deliberate, because this service must leave the world
     * correct whichever route reached it, including a recovery run that skipped
     * that path entirely.
     */
    private function closeTheBasket(Order $order): void
    {
        $cart = $order->cart;

        if ($cart !== null && $cart->status !== CartStatus::Converted) {
            $cart->status = CartStatus::Converted;
            $cart->save();
        }

        $quote = $order->checkoutQuote;

        if ($quote !== null && $quote->status !== CheckoutQuoteStatus::Consumed) {
            $quote->status = CheckoutQuoteStatus::Consumed;
            $quote->save();
        }
    }
}
