<?php

declare(strict_types=1);

namespace App\Services\Orders;

use App\Enums\OrderStatus;
use App\Models\OrderStatusHistory;
use Carbon\CarbonImmutable;

/**
 * What a transition attempt did.
 *
 * `applied` is false when the order was already in the target state. That is
 * not a failure — a retried delivery asking for READY on an order that is
 * already READY has got what it wanted — but the caller usually needs to know
 * no event was emitted and no history row was written.
 */
final readonly class OrderTransitionResult
{
    public function __construct(
        public OrderStatus $from,
        public OrderStatus $to,
        public int $version,
        public CarbonImmutable $occurredAt,
        public bool $applied,
        public ?OrderStatusHistory $entry = null,
    ) {}
}
