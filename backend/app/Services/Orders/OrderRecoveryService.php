<?php

declare(strict_types=1);

namespace App\Services\Orders;

use App\Enums\OrderStatus;
use App\Enums\PaymentStatus;
use App\Models\Order;
use App\Models\Payment;
use Carbon\CarbonImmutable;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\Date;
use Illuminate\Support\Facades\Log;
use Throwable;

/**
 * What to do about a customer whose money is gone and whose order is not there.
 *
 * This is the state Module 16 must never handle badly. The customer has paid.
 * From where they are standing the purchase is done, and any screen that says
 * otherwise — "payment failed", "try again", a Pay button — invites them to pay
 * a second time for food they have already bought. There is no recovery from
 * that which does not involve a refund and an apology.
 *
 * So every path here converges on the same two answers: the order exists, or it
 * is being finished. Never "it failed".
 */
final class OrderRecoveryService
{
    public function __construct(
        private readonly CreateOrderFromCapturedPayment $creation,
    ) {}

    /**
     * Resolve one order for a customer who has come back looking for it.
     *
     * Idempotent by construction: it either finds the order or asks the same
     * creation service every other route uses, so a customer refreshing the
     * confirmation screen twenty times cannot produce twenty orders.
     */
    public function resolve(Order $order): OrderRecoveryOutcome
    {
        if ($order->status === OrderStatus::Placed) {
            return OrderRecoveryOutcome::placed($order);
        }

        $captured = $order->payments()
            ->where('status', PaymentStatus::Captured->value)
            ->orderBy('id')
            ->first();

        if ($captured === null) {
            // Nothing has been taken. This is an ordinary unpaid order, and the
            // customer may legitimately be shown a way to pay for it.
            return OrderRecoveryOutcome::awaitingPayment($order);
        }

        try {
            return OrderRecoveryOutcome::placed($this->creation->place($captured));
        } catch (Throwable $e) {
            /*
             | The money is captured and the order still cannot be written.
             |
             | Loud, because this is the alert that matters most in this module,
             | and deliberately not fatal to the caller: the customer gets
             | "we are finishing your order", the sweep tries again, and nobody
             | is asked to pay twice on the strength of a transient failure.
             */
            Log::error('orders.recovery_required', [
                'order_id' => $order->id,
                'payment_id' => $captured->id,
                'reason' => $e->getMessage(),
            ]);

            return OrderRecoveryOutcome::recovering($order);
        }
    }

    /**
     * Captured payments with no order, older than a grace period.
     *
     * THE OPERATIONAL SAFETY NET THE SPECIFICATION CALLS MANDATORY. Every route
     * that places an order can die between capturing the money and writing the
     * row — a deploy, an OOM kill, a database failover. Without this sweep the
     * only thing standing between that and a customer who paid for nothing is
     * whether they happen to reopen the app.
     *
     * The grace period exists so the sweep does not fight with a placement that
     * is merely in progress. Racing it would be harmless — creation is
     * idempotent — but it would fill the log with duplicate-prevented lines and
     * hide the real failures among them.
     *
     * @return Collection<int, Payment>
     */
    public function capturedWithoutOrder(int $graceSeconds = 120, ?CarbonImmutable $now = null): Collection
    {
        $now ??= Date::now()->toImmutable();

        return Payment::query()
            ->where('status', PaymentStatus::Captured->value)
            ->where('verified_at', '<=', $now->subSeconds($graceSeconds))
            ->whereNotExists(function ($query): void {
                $query->selectRaw('1')
                    ->from('orders')
                    ->whereColumn('orders.placed_from_payment_id', 'payments.id');
            })
            ->orderBy('id')
            ->limit(200)
            ->get();
    }

    /**
     * Placed orders whose payment is not captured.
     *
     * The mirror-image integrity check, and the one nobody remembers to write.
     * A row here means an order was placed against money that is not there —
     * food a restaurant will make and nobody has paid for. It should be empty
     * at all times; the check exists so that if it is ever not, somebody finds
     * out from a report rather than from an accountant.
     *
     * @return Collection<int, Order>
     */
    public function placedWithoutCapturedPayment(): Collection
    {
        return Order::query()
            ->whereNotNull('placed_at')
            ->where(function ($query): void {
                $query->whereNull('placed_from_payment_id')
                    ->orWhereNotExists(function ($inner): void {
                        $inner->selectRaw('1')
                            ->from('payments')
                            ->whereColumn('payments.id', 'orders.placed_from_payment_id')
                            ->where('payments.status', PaymentStatus::Captured->value);
                    });
            })
            ->orderBy('id')
            ->limit(200)
            ->get();
    }
}
