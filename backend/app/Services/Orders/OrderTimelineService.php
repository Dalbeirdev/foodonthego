<?php

declare(strict_types=1);

namespace App\Services\Orders;

use App\Enums\OrderStatus;
use App\Enums\OrderTimelineStepState;
use App\Models\Order;
use App\Models\OrderStatusHistory;
use App\Support\Orders\OrderPresenter;
use App\Support\Orders\OrderStatusCopy;
use Illuminate\Support\Collection;

/**
 * The order's story, as the customer is allowed to read it.
 *
 * THE SERVER DECIDES WHICH STEPS ARE DONE. A client that worked out "COOKING is
 * current, so ACCEPTED must be complete" would be re-implementing the lifecycle
 * in Dart, and would be wrong the first time the lifecycle changed without an
 * app release. Every step arrives with its state already decided.
 *
 * BRANCHES ARE THE HARD PART, and the reason this is a service rather than a
 * loop in a presenter. A rejected order must not show Cooking and Ready sitting
 * patiently ahead of it: those things are not going to happen, and a timeline
 * that implies they might is worse than no timeline. So the happy path is
 * truncated at the point the order left it, and the exception is appended in
 * their place.
 *
 * NOTHING PRIVATE CROSSES THIS BOUNDARY. The history rows carry an actor, an
 * internal reason code and a correlation id; none of them appear in the output.
 * A customer learns that their order was accepted and when — not who accepted
 * it, and not why anything was refused beyond a note somebody chose to write
 * for them.
 */
final class OrderTimelineService
{
    /**
     * @return list<array<string, mixed>>
     */
    public function forCustomer(Order $order, string $zone): array
    {
        $history = $this->history($order);

        $reached = $history->keyBy(fn (OrderStatusHistory $entry): string => $entry->to_status->value);

        $current = $order->status;

        /*
         | Where the order left the happy path, if it did.
         |
         | REJECTED and CANCELLED are the two ways out. Both are terminal, and
         | both mean every remaining step is no longer expected.
         */
        $exception = in_array($current, [OrderStatus::Rejected, OrderStatus::Cancelled], strict: true)
            ? $current
            : null;

        $steps = [];

        foreach (OrderStateMachine::happyPath() as $status) {
            $entry = $reached->get($status->value);

            if ($status === $current) {
                $steps[] = $this->step($status, OrderTimelineStepState::Current, $entry, $zone);

                continue;
            }

            if ($entry !== null) {
                $steps[] = $this->step($status, OrderTimelineStepState::Completed, $entry, $zone);

                continue;
            }

            /*
             | Not reached. Whether it is still expected depends on whether the
             | order is still on the path.
             |
             | This is the assertion the branch handling rests on: once an order
             | has been rejected or cancelled, the remaining happy-path steps
             | are dropped rather than shown as upcoming. Showing them would
             | tell a customer their refused order is still queued to be cooked.
             */
            if ($exception !== null) {
                break;
            }

            $steps[] = $this->step($status, OrderTimelineStepState::Upcoming, null, $zone);
        }

        if ($exception !== null) {
            $steps[] = $this->step(
                $exception,
                OrderTimelineStepState::Exception,
                $reached->get($exception->value),
                $zone,
            );
        }

        return $steps;
    }

    /**
     * History, oldest first, with a deterministic tie-break.
     *
     * Loaded through the relation so the ordering is defined once. Two
     * transitions inside the same second are ordinary in a test harness and
     * possible in production; ordering by occurred_at alone would leave which
     * one a customer sees first up to the storage engine.
     */
    private function history(Order $order): Collection
    {
        return $order->relationLoaded('statusHistory')
            ? $order->statusHistory
            : $order->statusHistory()->get();
    }

    /**
     * @return array<string, mixed>
     */
    private function step(
        OrderStatus $status,
        OrderTimelineStepState $state,
        ?OrderStatusHistory $entry,
        string $zone,
    ): array {
        return [
            'status' => $status->value,
            'state' => $state->value,
            'title' => OrderStatusCopy::title($status),

            /*
             | Null for anything that has not happened.
             |
             | A step with a fabricated timestamp is the one failure a customer
             | cannot detect and cannot recover from: it tells them their food
             | was ready at a time it was not. An upcoming step carries no time
             | because there is no time to carry.
             */
            'occurred_at' => OrderPresenter::local($entry?->occurred_at, $zone),

            /*
             | The only free text a customer may see, and only when somebody
             | deliberately wrote it for them.
             */
            'note' => $entry?->customer_safe_note,
        ];
    }
}
