<?php

declare(strict_types=1);

namespace App\Exceptions\Orders;

use DomainException;

/**
 * The transition was legal; this actor was not allowed to make it.
 *
 * SAYS NOTHING ABOUT THE ORDER. A restaurant operator probing other tenants'
 * order ids learns only that they were refused, not whether the id was real,
 * which restaurant it belonged to, or what state it was in.
 */
final class OrderTransitionNotPermittedForActor extends DomainException
{
    public function __construct()
    {
        parent::__construct('This actor may not change that order.');
    }
}
