<?php

declare(strict_types=1);

namespace App\Console\Commands;

use App\Services\Orders\OrderRecoveryService;
use Illuminate\Console\Command;

/**
 * Orders that exist without money behind them.
 *
 * The mirror image of the recovery sweep, and the one nobody writes. A row here
 * means a restaurant will cook food that nobody has paid for — the failure that
 * costs the business rather than the customer, which is exactly why it tends to
 * go unmonitored until an accountant finds it.
 *
 * Reports only. It does not cancel anything: an order in this state needs a
 * human to decide whether the payment is genuinely missing or merely
 * unreconciled, and a command that guessed would eventually cancel somebody's
 * dinner over a provider's slow webhook.
 */
final class CheckOrderIntegrityCommand extends Command
{
    protected $signature = 'orders:check-integrity';

    protected $description = 'Report placed orders that have no captured payment behind them.';

    public function handle(OrderRecoveryService $recovery): int
    {
        $suspect = $recovery->placedWithoutCapturedPayment();

        if ($suspect->isEmpty()) {
            $this->info('Every placed order has a captured payment behind it.');

            return self::SUCCESS;
        }

        $this->error($suspect->count().' placed order(s) without a captured payment:');

        foreach ($suspect as $order) {
            $this->line(sprintf(
                '  order %d (%s) restaurant %d, placed %s, payment %s',
                $order->id,
                (string) $order->order_number,
                (int) $order->restaurant_id,
                (string) $order->placed_at,
                $order->placed_from_payment_id === null ? 'none' : (string) $order->placed_from_payment_id,
            ));
        }

        return self::FAILURE;
    }
}
