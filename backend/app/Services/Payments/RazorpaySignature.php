<?php

declare(strict_types=1);

namespace App\Services\Payments;

/**
 * The arithmetic that decides whether a message really came from the provider.
 *
 * This class is not behind {@see PaymentGateway} on purpose. If it were, the
 * test double would be the thing deciding whether a signature verifies, and
 * every test touching payment security would be asserting against a `return
 * true`. Here, the code that runs in tests is the code that runs in production,
 * and the tests compute genuine HMACs to exercise it.
 *
 * Two different messages are signed, with two different secrets, and confusing
 * them is a real mistake with a quiet failure mode:
 *
 * - The **checkout** signature covers `order_id|payment_id` and uses the API
 *   secret. It is what the app hands back after a customer pays.
 * - The **webhook** signature covers the raw request body byte for byte and uses
 *   the separate webhook secret.
 *
 * The webhook one must be computed over the *raw* body. Decoding to an array and
 * re-encoding produces different bytes — key order, spacing, unicode escaping —
 * and the HMAC will not match, so a correct implementation reads the body before
 * anything parses it.
 */
final class RazorpaySignature
{
    /**
     * The message a checkout signature covers.
     *
     * The provider's format, not a choice: order id, a pipe, payment id.
     */
    public static function checkoutPayload(string $providerOrderId, string $providerPaymentId): string
    {
        return $providerOrderId.'|'.$providerPaymentId;
    }

    /** Lowercase hex HMAC-SHA256, which is what the provider sends. */
    public static function compute(string $payload, string $secret): string
    {
        return hash_hmac('sha256', $payload, $secret);
    }

    /**
     * Whether a signature is the right one for this payload.
     *
     * `hash_equals` rather than `===`, so the comparison takes the same time
     * whether it fails on the first character or the last. A plain string
     * compare leaks, one byte at a time, how much of a guess was right.
     *
     * An empty signature is refused before comparing. It is not that the
     * comparison would pass — it would not — but a caller reaching here with an
     * empty string has usually forgotten to read a header, and failing on the
     * specific reason is more useful than failing on the general one.
     */
    public static function verify(string $payload, string $signature, string $secret): bool
    {
        if ($signature === '' || $secret === '') {
            return false;
        }

        return hash_equals(self::compute($payload, $secret), $signature);
    }

    /** Whether this checkout result was really signed for this order. */
    public static function verifyCheckout(
        string $providerOrderId,
        string $providerPaymentId,
        string $signature,
        string $secret,
    ): bool {
        return self::verify(
            self::checkoutPayload($providerOrderId, $providerPaymentId),
            $signature,
            $secret,
        );
    }

    /** Whether this webhook body was really sent by the provider. */
    public static function verifyWebhook(string $rawBody, string $signature, string $webhookSecret): bool
    {
        return self::verify($rawBody, $signature, $webhookSecret);
    }
}
