<?php

declare(strict_types=1);

namespace App\Services\Payments;

use App\Enums\PaymentStatus;

/**
 * What the provider says about one payment.
 *
 * `orderId` is carried deliberately. Verifying a signature proves a message was
 * not tampered with; it does not prove the payment it names belongs to the order
 * being settled. Comparing this field against the payment row we created is what
 * closes that gap, and it is why the interface returns the provider's idea of
 * the order rather than assuming the caller's.
 */
final readonly class GatewayPayment
{
    public function __construct(
        public string $id,
        public string $orderId,
        public int $amountMinor,
        public string $currency,
        public PaymentStatus $status,
        public ?string $failureReason = null,
    ) {}
}
