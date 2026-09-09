<?php

declare(strict_types=1);

namespace App\Console\Commands;

use App\Enums\OrderStatus;
use App\Exceptions\Orders\OrderTransitionNotAllowed;
use App\Models\Order;
use App\Services\Orders\OrderTransitionActor;
use App\Services\Orders\OrderTransitionService;
use Illuminate\Console\Command;

/**
 * Move a controlled order through its lifecycle, for QA only.
 *
 * WHY THIS EXISTS. The restaurant dashboard that will legitimately accept,
 * cook and finish orders is several modules away, and Module 17's customer
 * tracking cannot be verified against an order that can never leave PLACED.
 * The choice was between this and a customer-facing endpoint that moves an
 * order, and a customer-facing endpoint would be a critical security defect
 * however carefully it was worded.
 *
 * WHY IT IS NOT A BACKDOOR.
 *
 *   - It is a console command. There is no route, no controller and no HTTP
 *     surface; reaching it requires shell access to the server, at which point
 *     an attacker has the database anyway.
 *   - It refuses to run outside local and testing environments, and the check
 *     is the first thing it does.
 *   - Its transitions are recorded with source TEST_HARNESS, so a production
 *     database can be queried for rows that should not exist rather than
 *     trusted not to have them.
 *   - It validates through OrderTransitionService like every other caller. It
 *     is a way to *drive* the lifecycle, not a way around it — an illegal
 *     transition asked for here is refused exactly as it would be anywhere.
 */
final class TransitionOrderForDevelopmentCommand extends Command
{
    protected $signature = 'dev:order-transition
        {order : The order uuid}
        {status : The target status, e.g. ACCEPTED}
        {--note= : A customer-safe note to attach}';

    protected $description = 'Development only. Move a controlled order to another status.';

    public function handle(OrderTransitionService $transitions): int
    {
        if (! app()->environment(['local', 'testing'])) {
            $this->error('dev:order-transition is not available in this environment.');

            return self::FAILURE;
        }

        $order = Order::query()->where('uuid', (string) $this->argument('order'))->first();

        if ($order === null) {
            $this->error('No order with that uuid.');

            return self::FAILURE;
        }

        $target = OrderStatus::tryFrom(strtoupper((string) $this->argument('status')));

        if ($target === null) {
            $this->error('Not a status this platform has.');

            return self::FAILURE;
        }

        try {
            $result = $transitions->transition(
                order: $order,
                to: $target,
                actor: OrderTransitionActor::testHarness(),
                reasonCode: 'DEV_HARNESS',
                customerSafeNote: $this->option('note') === null ? null : (string) $this->option('note'),
            );
        } catch (OrderTransitionNotAllowed $refusal) {
            // Refused, and that is the command working. A harness that could
            // force an illegal transition would let QA produce states the
            // product cannot reach, and then those states would get designed for.
            $this->error($refusal->getMessage());

            return self::FAILURE;
        }

        $this->info($result->applied
            ? "{$result->from->value} -> {$result->to->value} (version {$result->version})"
            : "Already {$result->to->value}. Nothing written.");

        return self::SUCCESS;
    }
}
