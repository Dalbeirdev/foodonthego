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
 * general `setStatus`. Module 17 added the fulfilment edges, and it did so by
 * extending the table below rather than by giving anybody a bypass — which is
 * the whole reason the table was written while it had three rows in it.
 *
 * NO CUSTOMER PATH REACHES THIS CLASS. The customer API is read-only over
 * orders; the only writers are the placement service, the payment services, and
 * OrderTransitionService, which every restaurant and admin path must go
 * through.
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

        /*
         | The order exists and the restaurant has not answered yet.
         |
         | CANCELLED is reachable from here and from ACCEPTED, and no further,
         | because cancellation policy has not been agreed. Permitting it from
         | COOKING or READY would be inventing the rule that a customer may
         | walk away from food already made — a commercial decision nobody has
         | taken. When it is taken, it is one line here and a test beside it.
         */
        OrderStatus::Placed->value => [
            OrderStatus::Accepted,
            OrderStatus::Rejected,
            OrderStatus::Cancelled,
        ],

        OrderStatus::Accepted->value => [
            OrderStatus::Cooking,
            OrderStatus::Cancelled,
        ],

        /*
         | Once the kitchen has started, forward only.
         |
         | COOKING → CANCELLED is absent deliberately. See above: the food
         | exists by this point and somebody has to decide who pays for it.
         */
        OrderStatus::Cooking->value => [
            OrderStatus::Ready,
        ],

        /*
         | READY → PICKED_UP is the only edge, and Module 21 owns it.
         |
         | Nothing in Module 17 may mark an order collected: doing so requires
         | a verified pickup credential, and nothing verifies one yet.
         */
        OrderStatus::Ready->value => [
            OrderStatus::PickedUp,
        ],

        /*
         | Terminal. Every one of these is an empty list, and the emptiness is
         | the protection: there is no privileged flag, no force parameter and
         | no admin override in this class. A deliberate recovery workflow would
         | be a new, separately authorised service — not an argument here that
         | somebody could pass by accident.
         */
        OrderStatus::Rejected->value => [],
        OrderStatus::PickedUp->value => [],
        OrderStatus::Cancelled->value => [],

        /*
         | Unreachable, and Module 17 keeps it that way.
         |
         | REFUNDED IS PAYMENT STATE, NOT ORDER STATE. A rejected order whose
         | money came back is `order.status = REJECTED` with a refunded
         | payment, which is two facts on two records; folding it into one
         | status forces a single string to answer two questions and loses one
         | of the answers. The case stays declared so this table can refuse it
         | by name. No refund workflow exists, so nothing refunds anything yet.
         */
        OrderStatus::Refunded->value => [],
    ];

    /**
     * The states an order can still move out of.
     *
     * Defined here rather than in the enum because "active" is a property of
     * the transition table — a state is active exactly when something can still
     * happen to it — and keeping the two definitions in one place stops them
     * drifting apart the next time an edge is added.
     *
     * @return list<OrderStatus>
     */
    public static function activeStatuses(): array
    {
        return [
            OrderStatus::Placed,
            OrderStatus::Accepted,
            OrderStatus::Cooking,
            OrderStatus::Ready,
        ];
    }

    /**
     * The happy path, in order, for rendering a timeline.
     *
     * NOT DERIVED FROM THE TABLE ABOVE, because the table is a graph and a
     * timeline is a line. Every branch out of the happy path — rejection,
     * cancellation — is an exception the presenter handles explicitly rather
     * than a step it tries to lay out.
     *
     * @return list<OrderStatus>
     */
    public static function happyPath(): array
    {
        return [
            OrderStatus::Placed,
            OrderStatus::Accepted,
            OrderStatus::Cooking,
            OrderStatus::Ready,
            OrderStatus::PickedUp,
        ];
    }

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
        $this->stamp($order, $to, $now);
    }

    /**
     * The timestamp that belongs to the state being entered.
     *
     * WRITTEN ONCE. A transition into a state the order has already been in is
     * refused by the table above, so each of these fires at most once per
     * order and a milestone cannot be quietly overwritten by a replayed event.
     */
    private function stamp(Order $order, OrderStatus $to, CarbonImmutable $now): void
    {
        match ($to) {
            OrderStatus::Placed => $order->placed_at = $now,
            OrderStatus::Accepted => $order->accepted_at = $now,
            OrderStatus::Rejected => $order->rejected_at = $now,
            OrderStatus::Cooking => $order->cooking_started_at = $now,
            OrderStatus::Ready => $order->ready_at = $now,
            OrderStatus::PickedUp => $order->picked_up_at = $now,
            OrderStatus::Cancelled => $order->cancelled_at = $now,
            default => null,
        };
    }
}
