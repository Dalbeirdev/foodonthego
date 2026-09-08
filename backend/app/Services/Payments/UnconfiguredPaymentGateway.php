<?php

declare(strict_types=1);

namespace App\Services\Payments;

use Illuminate\Support\Facades\Log;

/**
 * The default when no payment provider is configured.
 *
 * It fails, loudly and every time. The same shape as Module 03's
 * `UnconfiguredOtpProvider` and Module 05R's `UnconfiguredPlaceProvider`, for
 * the same reason: a missing integration must be a broken deployment, not a
 * quiet one.
 *
 * It matters more here than anywhere else in the project. A payment gateway that
 * degraded gracefully — returned a plausible order, or reported success — would
 * produce orders marked paid with no money behind them, and the discovery would
 * be a reconciliation shortfall rather than a failed deploy. There is no
 * sensible fallback behaviour for taking money, so there is none.
 *
 * **This is what is bound today.** No Razorpay credentials exist in this project,
 * none were invented, and so every call through this interface in a real
 * deployment refuses. Tests bind a deterministic double instead.
 */
final class UnconfiguredPaymentGateway implements PaymentGateway
{
    public function name(): string
    {
        return 'unconfigured';
    }

    public function createOrder(int $amountMinor, string $currency, string $receipt): GatewayOrder
    {
        $this->refuse('create-order');
    }

    public function fetchOrderPayments(string $providerOrderId): array
    {
        $this->refuse('fetch-order-payments');
    }

    public function fetchPayment(string $providerPaymentId): GatewayPayment
    {
        $this->refuse('fetch-payment');
    }

    private function refuse(string $operation): never
    {
        Log::error('payments.gateway_unconfigured', ['operation' => $operation]);

        throw new PaymentGatewayException(
            'No payment gateway is configured. Set RAZORPAY_KEY_ID and RAZORPAY_KEY_SECRET.',
        );
    }
}
