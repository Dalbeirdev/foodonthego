<?php

declare(strict_types=1);

namespace App\Services\Orders;

use App\Enums\OrderStatus;
use App\Enums\OrderTransitionSource;
use App\Exceptions\Orders\OrderTransitionNotAllowed;
use App\Exceptions\Orders\OrderTransitionNotPermittedForActor;
use App\Models\Order;
use App\Models\OrderStatusHistory;
use App\Models\OutboxEvent;
use Carbon\CarbonImmutable;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\Date;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

/**
 * The only way an order's status changes after it has been placed.
 *
 * Module 16 built one writer for one transition. This is the general one, and
 * the reason it exists before any restaurant UI does is that the alternative —
 * writing it alongside the first screen that needs it — means the screen's
 * deadline decides how much of the locking, the auditing and the tenant
 * checking gets done.
 *
 * THE CUSTOMER APP CANNOT REACH THIS CLASS. There is no customer route that
 * calls it and no customer-facing service that wraps it. A phone displays order
 * state; it does not participate in deciding it. Any endpoint that let a
 * customer POST their order to READY would be a critical defect, and the tests
 * assert that no such route exists rather than trusting that nobody adds one.
 *
 * WHAT ONE CALL DOES, in this order and inside one transaction:
 *
 *   1. lock the order row
 *   2. re-read its status under the lock
 *   3. return early if it is already in the target state
 *   4. refuse if the transition table has no such edge
 *   5. refuse if the actor may not act on this order's restaurant
 *   6. apply the status and its milestone timestamp
 *   7. bump the order version
 *   8. append an immutable history row
 *   9. queue a domain event on Module 16's outbox
 *  10. commit
 *
 * Steps 1–3 are what make a duplicate delivery cheap and correct. Step 8's
 * unique index is what makes it correct when steps 1–3 are wrong.
 */
final class OrderTransitionService
{
    public function __construct(private readonly OrderStateMachine $states) {}

    /**
     * Move an order, or refuse and say why.
     *
     * @param  string|null  $reasonCode  Internal. May name anything operations finds useful.
     * @param  string|null  $customerSafeNote  The ONLY thing a customer may read. The caller
     *                                         is the thing that knows what is safe to say;
     *                                         deriving customer copy from an internal code at
     *                                         render time is how staffing notes reach a phone.
     *
     * @throws OrderTransitionNotAllowed
     * @throws OrderTransitionNotPermittedForActor
     */
    public function transition(
        Order $order,
        OrderStatus $to,
        OrderTransitionActor $actor,
        ?string $reasonCode = null,
        ?string $customerSafeNote = null,
        ?string $correlationId = null,
        ?CarbonImmutable $now = null,
    ): OrderTransitionResult {
        $now ??= Date::now()->toImmutable();

        return DB::transaction(function () use (
            $order, $to, $actor, $reasonCode, $customerSafeNote, $correlationId, $now
        ): OrderTransitionResult {
            /*
             | Re-read under a row lock rather than trusting the model handed in.
             |
             | The caller's $order may have been loaded seconds ago, and in
             | those seconds another worker may have moved it. Validating
             | against a stale status is how two concurrent actors both decide
             | their transition is legal and both write.
             */
            $locked = Order::query()->lockForUpdate()->findOrFail($order->getKey());

            $from = $locked->status;

            if ($from === $to) {
                /*
                 | Already there. Not an error, and deliberately not a write.
                 |
                 | Duplicate delivery is the normal case for anything driven by
                 | a queue or a retrying client. Appending a second ACCEPTED row
                 | would put two "Restaurant accepted your order" entries on a
                 | customer's timeline, and emitting a second event would
                 | notify them twice.
                 */
                return new OrderTransitionResult(
                    from: $from,
                    to: $to,
                    version: (int) $locked->order_version,
                    occurredAt: $now,
                    applied: false,
                );
            }

            if (! $this->states->permits($from, $to)) {
                Log::info('orders.transition_refused', [
                    'order_id' => $locked->id,
                    'from' => $from->value,
                    'to' => $to->value,
                    'source' => $actor->source->value,
                ]);

                throw new OrderTransitionNotAllowed($from, $to);
            }

            $this->refuseUnlessActorMayAct($locked, $actor);

            $this->states->transition($locked, $to, $now);

            /*
             | The version a client uses to discard a stale response.
             |
             | Bumped here, under the same lock as the status, so the two can
             | never disagree: a response carrying version N carries the status
             | that version N is.
             */
            $locked->order_version = (int) $locked->order_version + 1;

            if ($customerSafeNote !== null) {
                $locked->customer_safe_reason = $customerSafeNote;
            }

            $locked->save();

            $entry = $this->append(
                $locked, $from, $to, $actor, $reasonCode, $customerSafeNote, $correlationId, $now,
            );

            $this->queueEvent($locked, $to, $now);

            /*
             | Identifiers and categories only.
             |
             | No customer name, no staff identity, no reason text -- an
             | internal reason code is written for operations, and the
             | customer-safe note is not logged at all because it is the one
             | field an operator could paste into a ticket.
             */
            Log::info('orders.transitioned', [
                'order_id' => $locked->id,
                'restaurant_id' => $locked->restaurant_id,
                'from' => $from->value,
                'to' => $to->value,
                'version' => $locked->order_version,
                'source' => $actor->source->value,
                'reason_code' => $reasonCode,
                'correlation_id' => $correlationId,
            ]);

            // Keep the caller's instance in step with what was written, so a
            // caller that reads $order afterwards is not looking at the past.
            $order->setRawAttributes($locked->getAttributes(), sync: true);

            return new OrderTransitionResult(
                from: $from,
                to: $to,
                version: (int) $locked->order_version,
                occurredAt: $now,
                applied: true,
                entry: $entry,
            );
        });
    }

    /**
     * A restaurant operator may only move their own restaurant's orders.
     *
     * WRITTEN BEFORE THE UI THAT NEEDS IT. Module 14T established that a
     * tenant boundary which is only checked at the call site is a boundary
     * somebody forgets when they add the second call site. This check lives
     * where every transition passes through, so the first restaurant screen
     * inherits it rather than having to remember it.
     *
     * SYSTEM, PAYMENT and ADMIN are not tenant-scoped: they are the platform
     * acting on its own orders, and ADMIN carries an identity so the trail
     * names who it was.
     *
     * @throws OrderTransitionNotPermittedForActor
     */
    private function refuseUnlessActorMayAct(Order $order, OrderTransitionActor $actor): void
    {
        if ($actor->source !== OrderTransitionSource::Restaurant) {
            return;
        }

        if ($actor->restaurantId !== (int) $order->restaurant_id) {
            Log::warning('orders.cross_tenant_transition_refused', [
                'order_id' => $order->id,
                'order_restaurant_id' => $order->restaurant_id,
                'actor_restaurant_id' => $actor->restaurantId,
            ]);

            throw new OrderTransitionNotPermittedForActor;
        }
    }

    /**
     * Append the audit row, or discover that somebody else already did.
     *
     * The unique index on (order_id, to_status) is the real duplicate
     * protection. The early return above is the fast path; this is what holds
     * when two workers get past it at once, and catching it here rather than
     * letting it escape means a lost race reads as "already recorded" instead
     * of a 500.
     */
    private function append(
        Order $order,
        OrderStatus $from,
        OrderStatus $to,
        OrderTransitionActor $actor,
        ?string $reasonCode,
        ?string $customerSafeNote,
        ?string $correlationId,
        CarbonImmutable $now,
    ): ?OrderStatusHistory {
        $entry = new OrderStatusHistory;
        $entry->order_id = $order->id;
        $entry->from_status = $from;
        $entry->to_status = $to;
        $entry->source_type = $actor->source;
        $entry->actor_type = $actor->actorType;
        $entry->actor_id = $actor->actorId;
        $entry->reason_code = $reasonCode;
        $entry->customer_safe_note = $customerSafeNote;
        $entry->correlation_id = $correlationId;
        $entry->occurred_at = $now;

        try {
            $entry->save();
        } catch (QueryException $exception) {
            $existing = OrderStatusHistory::query()
                ->where('order_id', $order->id)
                ->where('to_status', $to)
                ->first();

            if ($existing === null) {
                throw $exception;
            }

            Log::info('orders.duplicate_status_history_prevented', [
                'order_id' => $order->id,
                'to' => $to->value,
            ]);

            return $existing;
        }

        return $entry;
    }

    /**
     * One domain event per transition, on the outbox Module 16 already built.
     *
     * NOT A SECOND DELIVERY ARCHITECTURE. Module 19's realtime layer and Module
     * 20's notifications will consume these; giving them a different queue to
     * read would mean two things to keep working and two ways for an event to
     * be lost.
     *
     * The dedupe key is the order uuid plus the state, so the outbox's own
     * unique index refuses a duplicate even if this method is somehow reached
     * twice. Payload is identifiers only — a consumer that needs the order
     * asks for it over an authenticated API, where the ownership checks are.
     */
    private function queueEvent(Order $order, OrderStatus $to, CarbonImmutable $now): void
    {
        $name = match ($to) {
            OrderStatus::Accepted => 'OrderAccepted',
            OrderStatus::Rejected => 'OrderRejected',
            OrderStatus::Cooking => 'OrderCookingStarted',
            OrderStatus::Ready => 'OrderReady',
            OrderStatus::PickedUp => 'OrderPickedUp',
            OrderStatus::Cancelled => 'OrderCancelled',
            default => null,
        };

        if ($name === null) {
            return;
        }

        OutboxEvent::queue(
            eventName: $name,
            dedupeKey: $order->uuid.':'.$to->value,
            payload: [
                'order_uuid' => (string) $order->uuid,
                'restaurant_id' => (int) $order->restaurant_id,
                'status' => $to->value,
                'order_version' => (int) $order->order_version,
            ],
            now: $now,
        );
    }
}
