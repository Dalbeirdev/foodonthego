<?php

declare(strict_types=1);

namespace App\Services\Orders;

use App\Enums\OrderStatus;
use App\Exceptions\Orders\OrderTransitionNotAllowed;
use App\Models\Order;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\Date;

/**
 * The only thing permitted to change an order's status.
 *
 * Written now, while there are three transitions, rather than when there are
 * fifteen. A status column that any service may assign becomes a column nobody
 * can reason about: the question "can an order go from REFUNDED back to
 * COOKING?" stops having an answer you can read and starts having an answer you
 * have to grep for.
 *
 * WHAT THIS DELIBERATELY DOES NOT DO. There is no endpoint behind it and no
 * general `setStatus`. Module 16 needs exactly one transition — a payment
 * target becoming a placed order — and every other edge in the table below is
 * either Module 15's or refused outright. Later modules extend the table; they
 * do not get a bypass.
 */
final class OrderStateMachine
{
    /**
     * Every permitted edge, and nothing else.
     *
     * The empty arrays are the point. PLACED leads nowhere yet because nothing
     * in this module may accept, reject, cook or complete an order, and an
     * empty list is a refusal a reader can see rather than an omission they
     * have to infer.
     */
    private const ALLOWED = [
        // A payment target resolves one of three ways.
        OrderStatus::AwaitingPayment->value => [
            OrderStatus::Placed,        // Module 16 — the money was captured.
            OrderStatus::PaymentFailed, // Module 15 — the provider refused.
            OrderStatus::Cancelled,     // Module 15 — abandoned.
        ],

        // A failed attempt may be retried. Module 15 owns this edge.
        OrderStatus::PaymentFailed->value => [
            OrderStatus::AwaitingPayment,
            OrderStatus::Cancelled,
        ],

        // Module 18 adds Accepted and Rejected. Module 22 adds Refunded.
        OrderStatus::Placed->value => [],

        // Module 19.
        OrderStatus::Accepted->value => [],
        OrderStatus::Cooking->value => [],
        OrderStatus::Ready->value => [],

        // Terminal.
        OrderStatus::Rejected->value => [],
        OrderStatus::PickedUp->value => [],
        OrderStatus::Cancelled->value => [],
        OrderStatus::Refunded->value => [],
    ];

    public function permits(OrderStatus $from, OrderStatus $to): bool
    {
        return in_array($to, self::ALLOWED[$from->value] ?? [], strict: true);
    }

    /**
     * Move an order, or refuse and say why.
     *
     * Does not save. The caller is inside a transaction that has more to write
     * than this, and a service that quietly persisted half of it would make the
     * atomicity Module 16 depends on impossible to see at the call site.
     */
    public function transition(Order $order, OrderStatus $to, ?CarbonImmutable $now = null): void
    {
        $from = $order->status;

        if ($from === $to) {
            // Not an error. Duplicate delivery is the normal case here, and the
            // caller's idempotency check has already decided what to do about
            // it; re-asserting the same state is a no-op rather than a failure.
            return;
        }

        if (! $this->permits($from, $to)) {
            throw new OrderTransitionNotAllowed($from, $to);
        }

        $now ??= Date::now()->toImmutable();

        $order->status = $to;

        // The timestamp that belongs to the state being entered. placed_at is
        // what the Orders tab sorts on, so it is set here and nowhere else.
        match ($to) {
            OrderStatus::Placed => $order->placed_at = $now,
            OrderStatus::Cancelled => $order->cancelled_at = $now,
            default => null,
        };
    }
}
