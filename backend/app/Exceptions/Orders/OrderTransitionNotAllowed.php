<?php

declare(strict_types=1);

namespace App\Exceptions\Orders;

use App\Enums\OrderStatus;
use DomainException;

/**
 * Somebody asked for a status change the lifecycle does not have an edge for.
 *
 * Names both ends. A message that says only "invalid transition" sends the
 * reader back to the table to work out which of the two was wrong.
 */
final class OrderTransitionNotAllowed extends DomainException
{
    public function __construct(
        public readonly OrderStatus $from,
        public readonly OrderStatus $to,
    ) {
        parent::__construct("An order may not move from {$from->value} to {$to->value}.");
    }
}
