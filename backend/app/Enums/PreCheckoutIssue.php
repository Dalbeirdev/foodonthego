<?php

declare(strict_types=1);

namespace App\Enums;

/**
 * What stands between this cart and a checkout.
 *
 * Deliberately **not** {@see ApiErrorCode}, for the same reason
 * {@see CartRevalidationFinding} is not: a pre-checkout response is a 200. The
 * request succeeded, and what it says is that the customer has something to do
 * first. Reusing the error vocabulary would put codes a client handles in a
 * catch block into a body it is meant to render, and the day somebody wires the
 * two together the customer sees a crash screen instead of "choose a pickup
 * time".
 *
 * Every case carries whether it blocks. Most do; a price that has gone down
 * does not, because nobody needs a dialogue to be charged less — but they
 * should still be told, which is why it is on the list at all.
 */
enum PreCheckoutIssue: string
{
    // --- the cart --------------------------------------------------------

    case CartEmpty = 'CART_EMPTY';

    /** A line that cannot be bought: sold out, withdrawn, or its options are gone. */
    case LineUnavailable = 'LINE_UNAVAILABLE';

    /**
     * A line costs more than when it was added.
     *
     * Blocking, and this is the case the specification names: pre-checkout must
     * never say yes over an unreviewed price rise. The customer's way past it is
     * to look at the new figure and add the dish again — a deliberate act, which
     * is the point. Nothing here quietly accepts a higher price on their behalf.
     */
    case PriceIncreased = 'PRICE_INCREASED';

    /** A line costs less. Reported, never blocking. */
    case PriceDecreased = 'PRICE_DECREASED';

    // --- the restaurant --------------------------------------------------

    case RestaurantNotAcceptingOrders = 'RESTAURANT_NOT_ACCEPTING_ORDERS';

    /** Suspended, withdrawn, or no longer one a customer may be shown. */
    case RestaurantUnavailable = 'RESTAURANT_UNAVAILABLE';

    /** No longer on the road this journey takes. */
    case RestaurantOffRoute = 'RESTAURANT_OFF_ROUTE';

    // --- the journey -----------------------------------------------------

    /** No route yet, or one calculated too long ago to plan against. */
    case RouteStale = 'ROUTE_STALE';

    // --- the pickup time -------------------------------------------------

    case NoPickupTimeSelected = 'NO_PICKUP_TIME_SELECTED';

    /**
     * Chosen, but under facts that have since moved.
     *
     * The window may well still be fine. Nobody has checked it against what is
     * true now, and a plan nobody has checked is not one to take to a payment.
     */
    case PickupTimeStale = 'PICKUP_TIME_STALE';

    /** Chosen, checked, and no longer feasible — it has passed, or the kitchen cannot make it. */
    case PickupTimeInvalid = 'PICKUP_TIME_INVALID';

    /** Nothing the kitchen could offer at all. */
    case NoFeasiblePickupWindow = 'NO_FEASIBLE_PICKUP_WINDOW';

    public function blocksCheckout(): bool
    {
        return $this !== self::PriceDecreased;
    }
}
