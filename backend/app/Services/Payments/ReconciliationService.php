<?php

declare(strict_types=1);

namespace App\Services\Payments;

use App\Enums\OrderStatus;
use App\Enums\PaymentStatus;
use App\Enums\PaymentVerificationSource;
use App\Exceptions\ApiException;
use App\Models\Order;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\Log;

/**
 * Going and asking, for the orders nobody told us about.
 *
 * Two things have to fail for an order to need this: the client callback and the
 * webhook. That happens — a customer's phone dies the instant after paying, and
 * the webhook delivery lands during a deploy — and the result is the worst state
 * this project can be in: a customer charged, and an order that says unpaid.
 *
 * Neither of the other two paths can find these. The callback needs an app that
 * came back, and the webhook needs a delivery that arrived. Reconciliation
 * starts from what this server *does* know — the provider order it created — and
 * asks what happened against it.
 *
 * It settles through exactly the same checks as everything else. Reconciliation
 * is the path with no user waiting on it and no signature to check, which makes
 * it precisely the one where a shortcut would never be noticed.
 */
final class ReconciliationService
{
    public function __construct(
        private readonly PaymentGateway $gateway,
        private readonly PaymentService $payments,
    ) {}

    /**
     * Examine unpaid orders old enough that both other paths have had their
     * chance, and settle any that the provider says were paid.
     *
     * @param  int  $olderThanMinutes  A grace period, so this never races a
     *                                 webhook that is merely in flight.
     * @return array{examined: int, settled: int, failed: int, unreachable: int}
     */
    public function run(int $olderThanMinutes = 15, int $limit = 200, ?CarbonImmutable $now = null): array
    {
        $now ??= CarbonImmutable::now();
        $cutoff = $now->subMinutes($olderThanMinutes);

        $orders = Order::query()
            ->whereIn('status', [OrderStatus::AwaitingPayment->value, OrderStatus::PaymentFailed->value])
            ->where('placed_at', '<=', $cutoff)
            ->whereHas('payments')
            ->with('payments')
            ->orderBy('id')
            ->limit($limit)
            ->get();

        $examined = 0;
        $settled = 0;
        $failed = 0;
        $unreachable = 0;

        foreach ($orders as $order) {
            $examined++;

            foreach ($order->payments as $payment) {
                if ($payment->status === PaymentStatus::Captured) {
                    continue;
                }

                try {
                    $remote = $this->gateway->fetchOrderPayments($payment->provider_order_id);
                } catch (PaymentGatewayException $e) {
                    $unreachable++;

                    Log::warning('payments.reconcile_unreachable', [
                        'order_id' => $order->id,
                        'reason' => $e->getMessage(),
                    ]);

                    continue;
                }

                foreach ($remote as $candidate) {
                    if (! $candidate->status->settlesOrder()) {
                        continue;
                    }

                    try {
                        $this->payments->confirmAgainstProvider(
                            $order,
                            $payment,
                            $candidate->id,
                            PaymentVerificationSource::Reconciliation,
                        );

                        $settled++;

                        Log::info('payments.reconciled', [
                            'order_id' => $order->id,
                            'payment_id' => $payment->id,
                        ]);
                    } catch (ApiException $e) {
                        // A captured payment that does not match this order's
                        // amount is not something to settle quietly. It is
                        // recorded against the attempt and surfaced in the
                        // count, because somebody needs to look at it.
                        $failed++;

                        Log::error('payments.reconcile_mismatch', [
                            'order_id' => $order->id,
                            'code' => $e->errorCode->value,
                        ]);
                    }

                    break 2;
                }
            }
        }

        return [
            'examined' => $examined,
            'settled' => $settled,
            'failed' => $failed,
            'unreachable' => $unreachable,
        ];
    }
}
