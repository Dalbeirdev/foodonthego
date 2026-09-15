<?php

declare(strict_types=1);

namespace Tests\Support;

use App\Enums\PaymentStatus;
use App\Services\Payments\GatewayOrder;
use App\Services\Payments\GatewayPayment;
use App\Services\Payments\PaymentGateway;
use App\Services\Payments\PaymentGatewayException;
use App\Services\Payments\RazorpaySignature;

/**
 * A payment provider that does exactly what a test tells it to.
 *
 * It lives under `tests/` rather than `app/` so that it cannot be bound by
 * accident in a real deployment. There is no configuration value that reaches
 * it; the only way to get one is to write one into the container from a test.
 *
 * **It does not verify signatures, and that is the point.** Signature checking
 * is {@see RazorpaySignature}, which is the same code in
 * tests as in production, and the tests compute real HMACs against it. Had that
 * arithmetic been part of this interface, this class would be deciding whether
 * signatures are valid, and every payment-security test in the project would be
 * asserting against a `return true`.
 *
 * Failures are opt-in: {@see failNextCreateOrder()} and {@see failFetch()} make
 * this thing behave like a provider having a bad day, because "the gateway threw"
 * is a path that needs testing and cannot be reached by a double that always
 * works.
 */
final class FakePaymentGateway implements PaymentGateway
{
    /** @var array<string, GatewayPayment> */
    private array $payments = [];

    /** @var list<array{amount: int, currency: string, receipt: string}> */
    public array $createdOrders = [];

    private int $sequence = 0;

    private bool $failCreateOrder = false;

    /** @var list<string> */
    private array $failFetchFor = [];

    public function name(): string
    {
        return 'fake';
    }

    public function createOrder(int $amountMinor, string $currency, string $receipt): GatewayOrder
    {
        if ($this->failCreateOrder) {
            $this->failCreateOrder = false;

            throw new PaymentGatewayException('Fake gateway was told to fail.');
        }

        $this->createdOrders[] = ['amount' => $amountMinor, 'currency' => $currency, 'receipt' => $receipt];

        return new GatewayOrder(
            id: sprintf('order_FAKE%06d', ++$this->sequence),
            amountMinor: $amountMinor,
            currency: $currency,
            status: 'created',
        );
    }

    public function fetchOrderPayments(string $providerOrderId): array
    {
        if (in_array($providerOrderId, $this->failFetchFor, true)) {
            throw new PaymentGatewayException('Fake gateway was told to fail on fetch.');
        }

        return array_values(array_filter(
            $this->payments,
            static fn (GatewayPayment $p): bool => $p->orderId === $providerOrderId,
        ));
    }

    public function fetchPayment(string $providerPaymentId): GatewayPayment
    {
        if (in_array($providerPaymentId, $this->failFetchFor, true)) {
            throw new PaymentGatewayException('Fake gateway was told to fail on fetch.');
        }

        return $this->payments[$providerPaymentId]
            ?? throw new PaymentGatewayException("Fake gateway knows no payment {$providerPaymentId}.");
    }

    /**
     * Tell the fake what the provider would say about a payment.
     *
     * Every field is settable, including ones a correct implementation would
     * never disagree on — the amount and the order id especially. A test that
     * cannot make the provider report a *different* amount cannot prove the
     * server checks it.
     */
    public function stubPayment(
        string $paymentId,
        string $orderId,
        int $amountMinor,
        PaymentStatus $status = PaymentStatus::Captured,
        string $currency = 'INR',
        ?string $failureReason = null,
    ): void {
        $this->payments[$paymentId] = new GatewayPayment(
            id: $paymentId,
            orderId: $orderId,
            amountMinor: $amountMinor,
            currency: $currency,
            status: $status,
            failureReason: $failureReason,
        );
    }

    public function failNextCreateOrder(): void
    {
        $this->failCreateOrder = true;
    }

    public function failFetch(string $providerPaymentId): void
    {
        $this->failFetchFor[] = $providerPaymentId;
    }
}
