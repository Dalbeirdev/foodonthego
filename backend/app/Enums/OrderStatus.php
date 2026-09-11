<?php

declare(strict_types=1);

namespace App\Enums;

/**
 * Where an order stands in its own lifecycle — never where its money stands.
 *
 * PAYMENT STATE LIVES ON THE PAYMENT. An order that is PLACED with a CAPTURED
 * payment is the ordinary case, and the two facts are read from two records.
 * Folding them into one string forces every future question — "paid but not yet
 * accepted?", "cooking but refunded?" — to be answered by a status that can
 * only be one thing at a time, and the usual repair is a second boolean nobody
 * trusts. Module 15's `PAID` order status is gone for exactly that reason.
 *
 * MOST OF THIS ENUM IS NOT REACHABLE YET, on purpose. The fulfilment states are
 * declared so that OrderStateMachine has the whole vocabulary to refuse from and
 * so that a later module extends a transition table rather than inventing a
 * second set of names. Declaring a state is not implementing it: every
 * transition into the fulfilment states is currently rejected, and the tests
 * assert that rejection.
 */
enum OrderStatus: string
{
    /**
     * NOT AN ORDER. A payment target.
     *
     * A row in this state has no order number, no pickup credentials and no
     * placed_at, never appears in the customer's Orders tab, and is never shown
     * to anybody as a purchase. It exists so a payment has something to point
     * at while it is being attempted. Module 16's rule — an order exists only
     * downstream of a captured payment — is about what PLACED means, and this
     * state is the reason that rule can be kept without a second table.
     */
    case AwaitingPayment = 'AWAITING_PAYMENT';

    /**
     * The order. Reached only from a verified captured payment.
     *
     * CreateOrderFromCapturedPayment is the sole writer, and the unique index
     * on orders.placed_from_payment_id is what makes "reached once" a fact about
     * the database rather than a promise about the code.
     */
    case Placed = 'PLACED';

    /** An attempt was made and the provider refused it. Not terminal. */
    case PaymentFailed = 'PAYMENT_FAILED';

    /** Terminal. Nothing may move an order out of this. */
    case Cancelled = 'CANCELLED';

    // ---------------------------------------------------------------- future
    //
    // Declared, unreachable, and asserted unreachable. Each names the module
    // that will earn the right to enter it.

    /** Module 18 — the restaurant has taken the order on. */
    case Accepted = 'ACCEPTED';

    /** Module 18 — the restaurant has refused it. */
    case Rejected = 'REJECTED';

    /** Module 19 — preparation has started. */
    case Cooking = 'COOKING';

    /** Module 19 — waiting at the counter. */
    case Ready = 'READY';

    /** Module 21 — collected, against a verified pickup credential. */
    case PickedUp = 'PICKED_UP';

    /** Module 22 — money returned. */
    case Refunded = 'REFUNDED';

    /** Whether a fresh payment attempt may be started against this order. */
    public function acceptsPayment(): bool
    {
        return $this === self::AwaitingPayment || $this === self::PaymentFailed;
    }

    public function isTerminal(): bool
    {
        return $this === self::Cancelled
            || $this === self::Rejected
            || $this === self::PickedUp
            || $this === self::Refunded;
    }

    /**
     * Whether this is a real order rather than a payment target.
     *
     * The Orders tab, the restaurant queue and every customer-facing listing
     * filter on this. A payment target must never appear anywhere a customer
     * would read it as something they bought.
     */
    public function isPlacedOrder(): bool
    {
        return $this !== self::AwaitingPayment && $this !== self::PaymentFailed;
    }
}
