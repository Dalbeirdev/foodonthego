<?php

declare(strict_types=1);

namespace App\Enums;

/**
 * What has become of a customer's pickup intent.
 *
 * Deliberately NOT order statuses. No order exists in Module 13 and none can;
 * borrowing PENDING or CONFIRMED here would make a cart look like something it
 * is not, and would be the first step towards code that treats it as one.
 */
enum PickupSelectionStatus: string
{
    /** Nothing chosen yet. The ordinary state of a cart. */
    case None = 'NONE';

    /** Chosen, and still valid against the facts it was chosen under. */
    case Selected = 'SELECTED';

    /**
     * Chosen, but the world has moved: the cart, the route, the restaurant's
     * hours or its willingness to take orders has changed since. The window may
     * still be fine — but nobody has checked, and a plan nobody has checked is
     * not a plan to charge somebody for.
     */
    case Stale = 'STALE';

    /** Checked, and no longer feasible. */
    case Invalid = 'INVALID';

    /** Whether a customer may proceed towards checkout on this. */
    public function isUsable(): bool
    {
        return $this === self::Selected;
    }
}
