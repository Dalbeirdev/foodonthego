<?php

declare(strict_types=1);

namespace App\Services\Payments;

use App\Enums\ApiErrorCode;
use App\Enums\OrderStatus;
use App\Enums\PaymentStatus;
use App\Enums\PaymentVerificationSource;
use App\Exceptions\ApiException;
use App\Models\Order;
use App\Models\Payment;
use App\Services\Orders\CreateOrderFromCapturedPayment;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Throwable;

/**
 * Everything that decides whether an order has been paid for.
 *
 * The rule the whole class exists to enforce: **a client's word is evidence to
 * check, never a fact to accept.** The app returns a signature after a customer
 * pays, and that signature is worth exactly one thing — proof the message was
 * not tampered with in transit. It is not proof the payment succeeded, not proof
 * of the amount, and not proof that the payment belongs to this order. Each of
 * those is established separately, against the provider, before an order moves.
 *
 * Three checks run in order, and each one closes a hole the previous does not:
 *
 * 1. **Signature.** Was this message really signed with our secret?
 * 2. **Binding.** Does the provider agree this payment belongs to the provider
 *    order we created for *this* order? A valid signature over somebody else's
 *    payment is still valid.
 * 3. **Amount and currency.** Does what was actually paid match what is owed?
 *    A genuine ₹1 payment, correctly signed and correctly bound, must not settle
 *    a ₹838 order.
 */
final class PaymentService
{
    public function __construct(
        private readonly PaymentGateway $gateway,
        private readonly CreateOrderFromCapturedPayment $orderCreation,
    ) {}

    /**
     * The provider order this checkout will be opened against.
     *
     * Idempotent by design. A customer who backgrounds the app and returns, or
     * taps twice, gets the payment attempt that already exists rather than a
     * second provider order — several open provider orders for one of ours is
     * how a double charge becomes possible in the first place.
     *
     * The reuse is conditional on the amount still matching. If the order's total
     * somehow differs from the attempt's, the old attempt is not reused, because
     * paying it would settle the wrong figure.
     *
     * @throws ApiException
     */
    public function createIntent(Order $order): Payment
    {
        $this->refuseUnlessPayable($order);

        $open = $order->payments()
            ->where('status', PaymentStatus::Created->value)
            ->where('amount_minor', $order->payable_total_minor)
            ->where('currency', $order->currency)
            ->orderByDesc('id')
            ->first();

        if ($open !== null) {
            return $open;
        }

        try {
            $gatewayOrder = $this->gateway->createOrder(
                amountMinor: $order->payable_total_minor,
                currency: $order->currency,
                // The uuid, not the order number.
                //
                // Since Module 16 the number is minted at placement, so a
                // payment target has none — this call happens strictly before
                // there is anything for a customer to read out. The uuid is
                // the identity that exists at this point and is also what the
                // provider's dashboard needs to point back at, which is what a
                // receipt is for.
                receipt: (string) $order->uuid,
            );
        } catch (PaymentGatewayException $e) {
            Log::error('payments.intent_failed', [
                'order_id' => $order->id,
                'reason' => $e->getMessage(),
            ]);

            throw new ApiException(
                ApiErrorCode::PaymentGatewayUnavailable,
                'Payments are temporarily unavailable. Please try again shortly.',
            );
        }

        $payment = new Payment;
        $payment->order_id = $order->id;
        $payment->provider = $this->gateway->name();
        $payment->provider_order_id = $gatewayOrder->id;
        $payment->amount_minor = $order->payable_total_minor;
        $payment->currency = $order->currency;
        $payment->status = PaymentStatus::Created;
        $payment->save();

        return $payment;
    }

    /**
     * What the app came back with, checked rather than believed.
     *
     * @throws ApiException
     */
    public function verifyClientCallback(
        Order $order,
        string $providerOrderId,
        string $providerPaymentId,
        string $signature,
    ): Payment {
        $payment = $order->payments()
            ->where('provider_order_id', $providerOrderId)
            ->first();

        if ($payment === null) {
            // Scoped to this order in the query, so a provider order id
            // belonging to somebody else's order is indistinguishable here from
            // one that does not exist.
            throw new ApiException(
                ApiErrorCode::PaymentNotFound,
                'That payment does not belong to this order.',
            );
        }

        $secret = (string) config('services.razorpay.key_secret');

        if (! RazorpaySignature::verifyCheckout($providerOrderId, $providerPaymentId, $signature, $secret)) {
            Log::warning('payments.signature_rejected', [
                'order_id' => $order->id,
                'payment_id' => $payment->id,
            ]);

            throw new ApiException(
                ApiErrorCode::PaymentSignatureInvalid,
                'That payment could not be verified.',
            );
        }

        return $this->confirmAgainstProvider($order, $payment, $providerPaymentId, PaymentVerificationSource::ClientCallback);
    }

    /**
     * Go and ask the provider, then act on what it says.
     *
     * Shared by the client callback, the webhook handler and reconciliation, so
     * that all three reach a paid order through exactly the same checks. Three
     * paths to PAID with three different sets of conditions is how one of them
     * ends up laxer than the others.
     *
     * @throws ApiException
     */
    public function confirmAgainstProvider(
        Order $order,
        Payment $payment,
        string $providerPaymentId,
        PaymentVerificationSource $source,
    ): Payment {
        try {
            $remote = $this->gateway->fetchPayment($providerPaymentId);
        } catch (PaymentGatewayException $e) {
            Log::error('payments.fetch_failed', [
                'order_id' => $order->id,
                'reason' => $e->getMessage(),
            ]);

            throw new ApiException(
                ApiErrorCode::PaymentGatewayUnavailable,
                'We could not confirm that payment. Please try again shortly.',
            );
        }

        // Binding. A correctly signed result naming a payment against a different
        // provider order settles nothing here.
        if (! hash_equals($payment->provider_order_id, $remote->orderId)) {
            Log::warning('payments.order_binding_mismatch', [
                'order_id' => $order->id,
                'payment_id' => $payment->id,
            ]);

            throw new ApiException(
                ApiErrorCode::PaymentSignatureInvalid,
                'That payment could not be verified.',
            );
        }

        // Amount and currency, against the order rather than against the attempt.
        // The attempt's amount is a copy; the order's is what is owed.
        if ($remote->amountMinor !== $order->payable_total_minor
            || strcasecmp($remote->currency, $order->currency) !== 0) {
            Log::warning('payments.amount_mismatch', [
                'order_id' => $order->id,
                'payment_id' => $payment->id,
                'expected_minor' => $order->payable_total_minor,
                'received_minor' => $remote->amountMinor,
            ]);

            $this->recordFailure($payment, 'Amount did not match the order total.');

            throw new ApiException(
                ApiErrorCode::PaymentAmountMismatch,
                'That payment does not match the amount due on this order.',
            );
        }

        if ($remote->status === PaymentStatus::Failed) {
            $this->recordFailure($payment, $remote->failureReason ?? 'The payment was declined.');

            throw new ApiException(
                ApiErrorCode::PaymentDeclined,
                'That payment was declined. Please try another method.',
            );
        }

        if (! $remote->status->settlesOrder()) {
            // Authorized but not captured. Nothing has gone wrong; the money is
            // simply not ours yet, and the webhook or reconciliation will finish
            // it. Recorded, not settled.
            $payment->provider_payment_id = $remote->id;
            $payment->status = $remote->status;
            $payment->save();

            return $payment;
        }

        return $this->settle($order, $payment, $remote->id, $source);
    }

    /**
     * Mark the money received, exactly once, and then place the order.
     *
     * TWO STEPS, TWO TRANSACTIONS, IN THIS ORDER — and the order matters.
     *
     * The capture is recorded first and on its own. Whatever happens next, the
     * fact that the customer's money was taken is durable: a crash between the
     * two leaves a captured payment with no order, which the recovery sweep
     * finds and finishes. The opposite ordering would risk an order for money
     * nobody has, which is not recoverable by any sweep.
     *
     * Placement then runs through CreateOrderFromCapturedPayment — the single
     * idempotent path every capture converges on, whether it arrived as a
     * client callback, a webhook, or a reconciliation run. It is deliberately
     * NOT inside the transaction above: it takes its own locks, and nesting
     * would hold the payment row for the whole of order creation for no benefit.
     *
     * Placement failing does not un-capture the payment. It cannot: the money
     * is gone and pretending otherwise would be a lie the customer pays for.
     * The exception is logged and swallowed here so that a webhook still gets
     * its 200 — Razorpay retrying a delivery we already recorded helps nobody —
     * and the order is created by the recovery path instead.
     */
    public function settle(
        Order $order,
        Payment $payment,
        string $providerPaymentId,
        PaymentVerificationSource $source,
        ?CarbonImmutable $now = null,
    ): Payment {
        $now ??= CarbonImmutable::now();

        $payment = DB::transaction(function () use ($order, $payment, $providerPaymentId, $source, $now): Payment {
            /** @var Order $locked */
            $locked = Order::query()->lockForUpdate()->findOrFail($order->id);

            $payment->refresh();

            if ($payment->status !== PaymentStatus::Captured) {
                $payment->provider_payment_id = $providerPaymentId;
                $payment->status = PaymentStatus::Captured;
                $payment->verified_at = $now;
                $payment->verification_source = $source;
                $payment->failure_reason = null;
                $payment->save();

                Log::info('payments.captured', [
                    'order_id' => $locked->id,
                    'payment_id' => $payment->id,
                    'source' => $source->value,
                ]);
            }

            return $payment;
        });

        $this->placeOrderFor($order, $payment, $now);

        return $payment;
    }

    /**
     * Turn a captured payment into a placed order, and survive not being able to.
     *
     * @see CreateOrderFromCapturedPayment for why this is one service and not
     *      one handler per delivery route.
     */
    private function placeOrderFor(Order $order, Payment $payment, CarbonImmutable $now): void
    {
        try {
            $placed = $this->orderCreation->place($payment, $now);

            // Refresh the caller's instance from the placed order, so a
            // controller that responds with $order shows the number and status
            // the customer is about to be told about.
            $order->setRawAttributes($placed->getAttributes(), true);
        } catch (Throwable $e) {
            // Loud, and specifically not fatal. A captured payment whose order
            // could not be written is the single most important thing to alert
            // on in this module, and the recovery sweep is what fixes it.
            Log::error('orders.creation_requires_recovery', [
                'order_id' => $order->id,
                'payment_id' => $payment->id,
                'reason' => $e->getMessage(),
            ]);
        }
    }

    /**
     * Record that an attempt failed, without closing the order.
     *
     * A declined card leaves the order payable. Moving it to a terminal state
     * would mean a customer whose first card was refused could never pay for the
     * basket they already built.
     */
    public function recordFailure(Payment $payment, string $reason): void
    {
        $payment->status = PaymentStatus::Failed;
        $payment->failure_reason = mb_substr($reason, 0, 200);
        $payment->save();

        $order = $payment->order;

        if ($order !== null && $order->status === OrderStatus::AwaitingPayment) {
            $order->status = OrderStatus::PaymentFailed;
            $order->save();
        }
    }

    /**
     * @throws ApiException
     */
    private function refuseUnlessPayable(Order $order): void
    {
        if ($order->status === OrderStatus::Placed) {
            throw new ApiException(
                ApiErrorCode::OrderAlreadyPaid,
                'This order has already been paid for.',
            );
        }

        if (! $order->status->acceptsPayment()) {
            throw new ApiException(
                ApiErrorCode::OrderNotPayable,
                'This order can no longer be paid for.',
            );
        }
    }
}
