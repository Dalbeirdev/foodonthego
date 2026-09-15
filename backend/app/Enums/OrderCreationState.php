<?php

declare(strict_types=1);

namespace App\Enums;

/**
 * What to tell a customer who is asking where their order is.
 *
 * THERE IS NO FAILURE CASE, and that is the whole design. After a capture, no
 * honest answer tells the customer their payment did not work — the money is
 * gone from their account. A type with a "failed" case would eventually get one
 * used, and the screen behind it would offer a Pay button to somebody who has
 * already paid.
 *
 * These are the specification's ORDER_CREATION_PENDING and
 * ORDER_RECOVERY_REQUIRED codes. They are not ApiErrorCodes: every value in
 * that enum must map to a 4xx or 5xx, and being midway through writing an order
 * is neither.
 */
enum OrderCreationState: string
{
    /** The order exists. Show it. */
    case Placed = 'PLACED';

    /**
     * Money captured, order not written yet. 202.
     *
     * The client shows "payment confirmed, finishing your order" and offers no
     * way to pay again.
     */
    case Creating = 'ORDER_CREATION_PENDING';

    /**
     * Money captured, and an attempt to write the order has already failed. 202.
     *
     * Distinct from Creating so that operations can tell a slow path from a
     * broken one, but identical from the customer's side: the same message, the
     * same absence of a Pay button.
     */
    case Recovering = 'ORDER_RECOVERY_REQUIRED';

    /** Nothing has been taken. Offering payment is legitimate. */
    case AwaitingPayment = 'AWAITING_PAYMENT';

    /** Whether the customer's money is already gone. */
    public function isPaidFor(): bool
    {
        return $this === self::Placed
            || $this === self::Creating
            || $this === self::Recovering;
    }

    public function httpStatus(): int
    {
        return match ($this) {
            self::Creating, self::Recovering => 202,
            default => 200,
        };
    }
}
