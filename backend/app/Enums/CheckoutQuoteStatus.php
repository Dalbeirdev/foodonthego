<?php

declare(strict_types=1);

namespace App\Enums;

/**
 * What has become of a checkout quote.
 *
 * **Deliberately not order statuses.** No order exists in Module 14 and none
 * can; borrowing PENDING or CONFIRMED would make a quote look like something it
 * is not, and would be the first step towards code treating it as one.
 *
 * Two of these are written down and two are worked out. `ACTIVE` and `CONSUMED`
 * are facts about what the server did. `STALE` and `EXPIRED` are conclusions
 * about a quote held up against the world, and they are derived on every read —
 * a column reading ACTIVE after the cart changed is not wrong because a job
 * failed to run, it is wrong because a column cannot know.
 */
enum CheckoutQuoteStatus: string
{
    /** Written down: this is the quote the server most recently produced. */
    case Active = 'ACTIVE';

    /** Derived: the facts it was quoted against have moved. */
    case Stale = 'STALE';

    /** Derived: its time ran out. */
    case Expired = 'EXPIRED';

    /**
     * Written down: Module 15 has taken this quote to a payment.
     *
     * Nothing in Module 14 sets it. The case exists so that the module which
     * does has a state to move into that is not an order status either.
     */
    case Consumed = 'CONSUMED';

    /** Whether a customer may proceed to payment on this. */
    public function isUsable(): bool
    {
        return $this === self::Active;
    }
}
