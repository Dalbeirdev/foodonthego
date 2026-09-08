<?php

declare(strict_types=1);

namespace App\Enums;

/**
 * Where an order stands with respect to money, and nothing else.
 *
 * There is no PREPARING, READY or COLLECTED here. No fulfilment workflow has
 * been specified for this project, and adding plausible-looking states would
 * create a vocabulary that screens, reports and restaurant tooling begin
 * depending on before anybody has decided it is the right one. When that
 * workflow is specified it gets its own column, because "has the customer paid"
 * and "has the kitchen finished" are independent questions and a single status
 * string cannot answer both without lying about one of them.
 */
enum OrderStatus: string
{
    /** Written, and awaiting a payment that has not yet been proven. */
    case AwaitingPayment = 'AWAITING_PAYMENT';

    /**
     * The server has satisfied itself that the money is there.
     *
     * Reached once. Every path that sets it checks the current status first, so
     * a re-verified payment, a duplicated webhook and a reconciliation run that
     * agrees with reality all leave `paid_at` where it was.
     */
    case Paid = 'PAID';

    /** An attempt was made and the provider refused it. Not terminal. */
    case PaymentFailed = 'PAYMENT_FAILED';

    /** Terminal. Nothing may move an order out of this. */
    case Cancelled = 'CANCELLED';

    /** Whether a fresh payment attempt may be started against this order. */
    public function acceptsPayment(): bool
    {
        return $this === self::AwaitingPayment || $this === self::PaymentFailed;
    }

    public function isTerminal(): bool
    {
        return $this === self::Cancelled;
    }
}
