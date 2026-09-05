<?php

declare(strict_types=1);

namespace App\Enums;

/**
 * What a cart is for.
 *
 * Two cases, deliberately. The order lifecycle — placed, accepted, cooking,
 * collected — belongs to an order, not to a cart, and folding it in here would
 * mean every cart query having to know which half of the enum it cared about.
 */
enum CartStatus: string
{
    /** Being filled. At most one of these per customer per journey. */
    case Active = 'ACTIVE';

    /**
     * Finished with — converted to an order, or abandoned and swept up.
     *
     * Nothing in Module 11 writes this; it exists so the "one active cart"
     * index has an off state to move a cart into, and so Module 12 has
     * somewhere to put a cart it replaces rather than deleting a customer's
     * selections.
     */
    case Closed = 'CLOSED';

    public function isActive(): bool
    {
        return $this === self::Active;
    }
}
