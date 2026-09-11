<?php

declare(strict_types=1);

namespace App\Console\Commands;

use App\Services\Payments\ReconciliationService;
use Illuminate\Console\Command;

/**
 * Settle orders the provider says were paid but this server never heard about.
 *
 * Scheduled every fifteen minutes in `routes/console.php` — see the block there
 * for why that number and not another. It was left unscheduled through Modules
 * 15 and 16 because a cadence looked like a deployment decision; it turned out
 * to be derivable from this command's own fifteen-minute grace period, which is
 * the interval below. KI-025.
 */
final class ReconcilePaymentsCommand extends Command
{
    protected $signature = 'payments:reconcile
        {--minutes=15 : Only examine orders placed at least this long ago}
        {--limit=200 : Most orders to examine in one run}';

    protected $description = 'Ask the payment provider about unpaid orders and settle any that were in fact paid';

    public function handle(ReconciliationService $reconciliation): int
    {
        $result = $reconciliation->run(
            olderThanMinutes: (int) $this->option('minutes'),
            limit: (int) $this->option('limit'),
        );

        $this->table(
            ['examined', 'settled', 'mismatched', 'unreachable'],
            [[$result['examined'], $result['settled'], $result['failed'], $result['unreachable']]],
        );

        // A mismatch is somebody's money in the wrong place. Non-zero exit so a
        // scheduler notices rather than a line scrolling past in a log.
        return $result['failed'] > 0 ? self::FAILURE : self::SUCCESS;
    }
}
