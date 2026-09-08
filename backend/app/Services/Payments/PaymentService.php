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
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

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
                receipt: $order->order_number,
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
     * Mark the money received, exactly once.
     *
     * The whole transition is inside one transaction with the order row locked,
     * and it re-reads the order's status after taking the lock. Two deliveries —
     * a client callback and a webhook about the same payment, arriving together —
     * would otherwise both see AWAITING_PAYMENT and both write `paid_at`.
     */
    public function settle(
        Order $order,
        Payment $payment,
        string $providerPaymentId,
        PaymentVerificationSource $source,
        ?CarbonImmutable $now = null,
    ): Payment {
        $now ??= CarbonImmutable::now();

        return DB::transaction(function () use ($order, $payment, $providerPaymentId, $source, $now): Payment {
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
            }

            if ($locked->status !== OrderStatus::Paid) {
                $locked->status = OrderStatus::Paid;
                $locked->paid_at = $now;
                $locked->save();

                Log::info('payments.order_paid', [
                    'order_id' => $locked->id,
                    'source' => $source->value,
                ]);
            }

            $order->setRawAttributes($locked->getAttributes(), true);

            return $payment;
        });
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
        if ($order->status === OrderStatus::Paid) {
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
