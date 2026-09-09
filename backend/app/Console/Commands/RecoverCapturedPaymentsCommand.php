<?php

declare(strict_types=1);

namespace App\Console\Commands;

use App\Services\Orders\CreateOrderFromCapturedPayment;
use App\Services\Orders\OrderRecoveryService;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Log;
use Throwable;

/**
 * Money taken, order never written. Finish it.
 *
 * THE SAFETY NET THE SPECIFICATION CALLS MANDATORY, and the one thing standing
 * between a process that died at the wrong moment and a customer who paid for
 * nothing. Every route that places an order can be interrupted between
 * capturing the money and writing the row — a deploy, an OOM kill, a database
 * failover — and without this the only recovery is the customer happening to
 * reopen the app.
 *
 * Idempotent, because it calls the same creation service everything else does.
 * Running it twice, or running it while a webhook is doing the same work,
 * cannot produce two orders.
 */
final class RecoverCapturedPaymentsCommand extends Command
{
    protected $signature = 'orders:recover-captured
        {--grace=120 : Seconds to leave a capture alone before treating it as stranded}
        {--dry-run : Report what would be placed without placing it}';

    protected $description = 'Place orders for captured payments that never produced one.';

    public function handle(
        OrderRecoveryService $recovery,
        CreateOrderFromCapturedPayment $creation,
    ): int {
        $stranded = $recovery->capturedWithoutOrder((int) $this->option('grace'));

        if ($stranded->isEmpty()) {
            $this->info('No captured payment is missing an order.');

            return self::SUCCESS;
        }

        /*
         | Loud even when it fixes itself.
         |
         | A sweep that quietly repairs things is a sweep nobody notices has
         | started running every hour. Each of these rows is a customer who was
         | charged and, for some window, had nothing to show for it — worth
         | knowing about even though the outcome is correct.
         */
        $this->warn($stranded->count().' captured payment(s) without an order.');

        $failures = 0;

        foreach ($stranded as $payment) {
            if ($this->option('dry-run')) {
                $this->line("  would place order for payment {$payment->id}");

                continue;
            }

            try {
                $order = $creation->place($payment);
                $this->line("  payment {$payment->id} -> order {$order->id}");
            } catch (Throwable $e) {
                $failures++;

                // The message, not the exception. A stack trace here would be
                // the same one already logged by the service; what an operator
                // needs from this line is which payment is stuck and why.
                $this->error("  payment {$payment->id} could not be placed: {$e->getMessage()}");

                Log::error('orders.recovery_sweep_failed', [
                    'payment_id' => $payment->id,
                    'reason' => $e->getMessage(),
                ]);
            }
        }

        // Non-zero so a scheduler or a human notices. A sweep that always exits
        // 0 is a sweep whose failures are invisible.
        return $failures === 0 ? self::SUCCESS : self::FAILURE;
    }
}
