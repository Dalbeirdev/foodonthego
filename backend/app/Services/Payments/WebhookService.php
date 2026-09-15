<?php

declare(strict_types=1);

namespace App\Services\Payments;

use App\Enums\PaymentEventOutcome;
use App\Enums\PaymentVerificationSource;
use App\Exceptions\ApiException;
use App\Models\Order;
use App\Models\Payment;
use App\Models\PaymentEvent;
use Carbon\CarbonImmutable;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\Log;
use Throwable;

/**
 * What the provider tells us directly, and what we do about it.
 *
 * A webhook is the most reliable thing this project hears about a payment. The
 * app can be killed the instant after a customer pays, the network can drop the
 * callback, the customer can put the phone in their pocket — and the money still
 * moved. If only the client callback settled orders, every one of those cases
 * would leave a paid order marked unpaid.
 *
 * Three properties matter, and the order they are established in is the design:
 *
 * 1. **Verify before anything else.** The endpoint is public. The signature is
 *    computed over the raw body, before any parsing, because re-encoding parsed
 *    JSON produces different bytes and a different HMAC.
 * 2. **Record before acting.** The insert into `payment_events` is the
 *    idempotency gate. A unique index does the work rather than a "have I seen
 *    this?" query, because two deliveries of the same event can be in flight
 *    simultaneously and a check-then-write has a gap between them.
 * 3. **Confirm with the provider anyway.** Even a verified webhook goes through
 *    {@see PaymentService::confirmAgainstProvider()}, so that the client
 *    callback, the webhook and reconciliation reach a paid order through exactly
 *    the same amount and binding checks. Three routes to PAID with three sets of
 *    conditions is how one of them ends up laxer than the others.
 */
final class WebhookService
{
    /** Events this project acts on. Anything else is recorded and ignored. */
    private const HANDLED = ['payment.captured', 'payment.authorized', 'payment.failed'];

    public function __construct(
        private readonly PaymentService $payments,
    ) {}

    /**
     * Whether this body really came from the provider.
     *
     * Takes the raw body deliberately. A caller that passes a re-encoded array
     * here will get a false answer and no explanation of why.
     */
    public function signatureIsValid(string $rawBody, string $signature): bool
    {
        return RazorpaySignature::verifyWebhook(
            $rawBody,
            $signature,
            (string) config('services.razorpay.webhook_secret'),
        );
    }

    /**
     * Handle one verified delivery.
     *
     * The caller must have verified the signature already; this method does not
     * re-check it and does not write anything for an unverified body.
     *
     * @return PaymentEventOutcome What was done, for the response and the log.
     */
    public function handleVerified(
        string $rawBody,
        string $eventId,
        ?CarbonImmutable $now = null,
    ): PaymentEventOutcome {
        $now ??= CarbonImmutable::now();

        /** @var array<string, mixed> $body */
        $body = json_decode($rawBody, true) ?: [];

        $type = is_string($body['event'] ?? null) ? $body['event'] : 'unknown';

        $entity = $body['payload']['payment']['entity'] ?? [];
        $providerPaymentId = is_string($entity['id'] ?? null) ? $entity['id'] : null;
        $providerOrderId = is_string($entity['order_id'] ?? null) ? $entity['order_id'] : null;

        [$payment, $order] = $this->resolve($providerPaymentId, $providerOrderId);

        $event = new PaymentEvent;
        $event->provider = 'razorpay';
        $event->provider_event_id = $eventId;
        $event->event_type = mb_substr($type, 0, 80);
        $event->payment_id = $payment?->id;
        $event->order_id = $order?->id;
        $event->payload_digest = hash('sha256', $rawBody);
        $event->received_at = $now;

        try {
            $event->save();
        } catch (QueryException) {
            // The unique index fired. Seen before — possibly a retry, possibly a
            // second delivery racing the first. Either way nothing runs twice.
            Log::info('payments.webhook_duplicate', ['event_id' => $eventId, 'type' => $type]);

            return PaymentEventOutcome::Duplicate;
        }

        $outcome = $this->apply($type, $payment, $order, $providerPaymentId, $eventId);

        $event->outcome = $outcome;
        $event->processed_at = CarbonImmutable::now();
        $event->save();

        return $outcome;
    }

    private function apply(
        string $type,
        ?Payment $payment,
        ?Order $order,
        ?string $providerPaymentId,
        string $eventId,
    ): PaymentEventOutcome {
        if (! in_array($type, self::HANDLED, true)) {
            return PaymentEventOutcome::Ignored;
        }

        if ($payment === null || $order === null || $providerPaymentId === null) {
            // A verified delivery about something this server has no record of.
            // Worth keeping: it usually means a payment was taken against a
            // provider order this deployment did not create, which somebody
            // should look at.
            Log::warning('payments.webhook_unknown_subject', ['event_id' => $eventId, 'type' => $type]);

            return PaymentEventOutcome::Unknown;
        }

        if ($type === 'payment.failed') {
            $this->payments->recordFailure($payment, 'The provider reported the payment as failed.');

            return PaymentEventOutcome::Applied;
        }

        if ($order->isPlaced()) {
            // Already settled, most likely by the client callback getting back
            // first. Nothing to do, and specifically nothing to write again.
            return PaymentEventOutcome::Ignored;
        }

        try {
            $this->payments->confirmAgainstProvider(
                $order,
                $payment,
                $providerPaymentId,
                PaymentVerificationSource::Webhook,
            );
        } catch (ApiException $e) {
            // A declined or mismatched payment is a normal outcome here and has
            // already been recorded against the attempt. The delivery itself was
            // handled; it simply did not settle anything.
            Log::warning('payments.webhook_not_settled', [
                'event_id' => $eventId,
                'code' => $e->errorCode->value,
            ]);

            return PaymentEventOutcome::Applied;
        } catch (Throwable $e) {
            Log::error('payments.webhook_failed', ['event_id' => $eventId, 'reason' => $e->getMessage()]);

            throw $e;
        }

        return PaymentEventOutcome::Applied;
    }

    /**
     * @return array{0: ?Payment, 1: ?Order}
     */
    private function resolve(?string $providerPaymentId, ?string $providerOrderId): array
    {
        $payment = null;

        if ($providerOrderId !== null) {
            $payment = Payment::query()->where('provider_order_id', $providerOrderId)->first();
        }

        if ($payment === null && $providerPaymentId !== null) {
            $payment = Payment::query()->where('provider_payment_id', $providerPaymentId)->first();
        }

        return [$payment, $payment?->order];
    }
}
