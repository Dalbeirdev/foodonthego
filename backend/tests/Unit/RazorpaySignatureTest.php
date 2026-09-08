<?php

declare(strict_types=1);

namespace Tests\Unit;

use App\Services\Payments\PaymentGateway;
use App\Services\Payments\RazorpaySignature;
use PHPUnit\Framework\TestCase;

/**
 * The arithmetic that decides whether a payment message is genuine.
 *
 * These tests compute real HMACs. Nothing here is stubbed, and that is the
 * whole reason this code sits outside the gateway interface: had it been a
 * method on {@see PaymentGateway}, the test double would
 * be answering these questions and every assertion below would be checking a
 * `return true`.
 */
final class RazorpaySignatureTest extends TestCase
{
    private const SECRET = 'a-test-secret-not-a-real-one';

    private const ORDER = 'order_TESTabc123';

    private const PAYMENT = 'pay_TESTxyz789';

    private function validCheckoutSignature(): string
    {
        return hash_hmac(
            'sha256',
            self::ORDER.'|'.self::PAYMENT,
            self::SECRET,
        );
    }

    public function test_a_genuine_checkout_signature_verifies(): void
    {
        $this->assertTrue(RazorpaySignature::verifyCheckout(
            self::ORDER,
            self::PAYMENT,
            $this->validCheckoutSignature(),
            self::SECRET,
        ));
    }

    /**
     * The message is order|payment, and both halves are covered.
     *
     * Two tests rather than one, because a signature scheme that covered only
     * the payment id would pass a single combined test while allowing a genuine
     * payment to be replayed against a different order.
     */
    public function test_a_swapped_payment_id_does_not_verify(): void
    {
        $this->assertFalse(RazorpaySignature::verifyCheckout(
            self::ORDER,
            'pay_SOMEBODY_ELSES',
            $this->validCheckoutSignature(),
            self::SECRET,
        ));
    }

    public function test_a_swapped_order_id_does_not_verify(): void
    {
        $this->assertFalse(RazorpaySignature::verifyCheckout(
            'order_SOMEBODY_ELSES',
            self::PAYMENT,
            $this->validCheckoutSignature(),
            self::SECRET,
        ));
    }

    public function test_a_signature_made_with_another_secret_does_not_verify(): void
    {
        $forged = hash_hmac('sha256', self::ORDER.'|'.self::PAYMENT, 'the-wrong-secret');

        $this->assertFalse(RazorpaySignature::verifyCheckout(
            self::ORDER,
            self::PAYMENT,
            $forged,
            self::SECRET,
        ));
    }

    /**
     * An empty signature is refused, and so is an empty secret.
     *
     * The second is the one that matters. With no credentials configured the
     * secret is an empty string, and a comparison against `hash_hmac(..., '')`
     * is a perfectly computable value — so an attacker who knew the deployment
     * was unconfigured could sign with the empty secret and be believed.
     * Verification fails closed instead.
     */
    public function test_an_empty_signature_does_not_verify(): void
    {
        $this->assertFalse(RazorpaySignature::verifyCheckout(self::ORDER, self::PAYMENT, '', self::SECRET));
    }

    public function test_an_empty_secret_verifies_nothing_even_when_the_hmac_matches(): void
    {
        $computedWithEmptySecret = hash_hmac('sha256', self::ORDER.'|'.self::PAYMENT, '');

        $this->assertFalse(RazorpaySignature::verifyCheckout(
            self::ORDER,
            self::PAYMENT,
            $computedWithEmptySecret,
            '',
        ));
    }

    public function test_a_genuine_webhook_signature_verifies(): void
    {
        $body = '{"event":"payment.captured","payload":{"payment":{"entity":{"id":"pay_1"}}}}';

        $this->assertTrue(RazorpaySignature::verifyWebhook(
            $body,
            hash_hmac('sha256', $body, self::SECRET),
            self::SECRET,
        ));
    }

    /**
     * The webhook signature covers bytes, not meaning.
     *
     * This is the test that stops somebody "tidying up" the controller by
     * verifying against `json_encode($request->all())`. The two strings below
     * are the same JSON document and different bytes, and only one of them
     * hashes to the signature.
     */
    public function test_a_reencoded_body_does_not_verify_even_though_the_json_is_identical(): void
    {
        // A URL in the body, because PHP's json_encode escapes forward slashes
        // to \/ by default and Razorpay's does not. Picking a document that
        // happened to round-trip byte-identical would have made this test pass
        // while proving nothing — the first draft of it did exactly that.
        $raw = '{"event":"payment.captured","notes":{"ref":"https://example.test/receipt/9"}}';
        $signature = hash_hmac('sha256', $raw, self::SECRET);

        $reencoded = json_encode(json_decode($raw, true));

        $this->assertNotSame($raw, $reencoded);
        $this->assertSame(json_decode($raw, true), json_decode((string) $reencoded, true));

        $this->assertTrue(RazorpaySignature::verifyWebhook($raw, $signature, self::SECRET));
        $this->assertFalse(RazorpaySignature::verifyWebhook((string) $reencoded, $signature, self::SECRET));
    }
}
