<?php

declare(strict_types=1);

namespace App\Services\Cart;

use App\Support\Money;

/**
 * What a cart costs, broken down.
 *
 * A value object rather than an array because every field here is money and the
 * one thing that must never happen is two of them being added together in the
 * wrong units. Each is minor units of the same currency, carried as an integer
 * from the row to the wire without ever becoming a float.
 *
 * The breakdown is returned whole rather than as a single total, because a
 * customer who cannot see what the extra rupees are for assumes the worst, and
 * because "why is this more than the menu said" is the question that turns into
 * a support ticket.
 */
final readonly class CartTotals
{
    public function __construct(
        public Money $subtotal,
        public Money $tax,
        public Money $packagingFee,
        public Money $platformFee,
        public Money $total,
    ) {}

    /**
     * @return array<string, mixed>
     */
    public function toApiArray(): array
    {
        return [
            'subtotal' => $this->subtotal->toApiArray(),
            'tax' => $this->tax->toApiArray(),
            'packaging_fee' => $this->packagingFee->toApiArray(),
            'platform_fee' => $this->platformFee->toApiArray(),
            'total' => $this->total->toApiArray(),
        ];
    }
}
