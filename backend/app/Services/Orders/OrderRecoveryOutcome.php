<?php

declare(strict_types=1);

namespace App\Services\Orders;

use App\Models\Order;

/**
 * Where a customer's purchase actually stands.
 *
 * Three states, and none of them is "failed". That is the point: after a
 * capture there is no honest answer that tells the customer their payment did
 * not work, so the type does not have a case for it.
 */
final readonly class OrderRecoveryOutcome
{
    private function __construct(
        public Order $order,
        public bool $isPlaced,
        public bool $isRecovering,
    ) {}

    /** The order exists. Show it. */
    public static function placed(Order $order): self
    {
        return new self($order, true, false);
    }

    /**
     * Money taken, order not written yet.
     *
     * The client shows "payment confirmed, finishing your order" and never a
     * way to pay again.
     */
    public static function recovering(Order $order): self
    {
        return new self($order, false, true);
    }

    /** Nothing has been taken. Paying is still a legitimate thing to offer. */
    public static function awaitingPayment(Order $order): self
    {
        return new self($order, false, false);
    }
}
