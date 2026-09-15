<?php

declare(strict_types=1);

namespace App\Services\Payments;

/**
 * The boundary between this product and whoever moves the money.
 *
 * Two operations, because those are the two questions this project asks of a
 * provider: make me an order to be paid, and tell me what became of a payment.
 *
 * **Signature verification is deliberately not here.** It is arithmetic over a
 * shared secret, not a network call, and putting it behind this interface would
 * mean the test double decides whether a signature is valid — which is to say
 * the security property most worth testing would be stubbed to `true` in every
 * test that touches it. It lives in {@see RazorpaySignature}, is the same code
 * in tests as in production, and the tests compute real HMACs against it.
 *
 * Implementations throw {@see PaymentGatewayException} when they *failed*. A
 * declined payment is not a failure of this interface; it is a
 * {@see GatewayPayment} whose status says so.
 */
interface PaymentGateway
{
    public function name(): string;

    /**
     * Create the provider-side order that a checkout will be opened against.
     *
     * The amount is passed in minor units and is the server's figure. No caller
     * may pass an amount that came from a client.
     *
     * @param  string  $receipt  Our own reference, echoed back by the provider.
     *
     * @throws PaymentGatewayException
     */
    public function createOrder(int $amountMinor, string $currency, string $receipt): GatewayOrder;

    /**
     * Every payment the provider has against one of our provider orders.
     *
     * Reconciliation needs this and {@see fetchPayment()} cannot serve it. The
     * case worth reconciling is the one where the client callback never arrived
     * *and* the webhook never arrived — and in that case this server has no
     * payment identifier to ask about. It knows only the order it created, so
     * that is what it must be able to ask about.
     *
     * @return list<GatewayPayment>
     *
     * @throws PaymentGatewayException
     */
    public function fetchOrderPayments(string $providerOrderId): array;

    /**
     * Ask the provider what became of a payment.
     *
     * Used by verification, by the webhook handler and by reconciliation. It is
     * the only thing in this project entitled to say a payment succeeded.
     *
     * @throws PaymentGatewayException
     */
    public function fetchPayment(string $providerPaymentId): GatewayPayment;
}
