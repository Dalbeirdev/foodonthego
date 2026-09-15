<?php

declare(strict_types=1);

namespace App\Exceptions\Orders;

use RuntimeException;

/**
 * Every candidate order number collided.
 *
 * At 2^50 suffixes per day this means something is wrong with the randomness
 * source, not that the platform got unlucky — so it is a loud failure rather
 * than a silent widening of the retry loop.
 */
final class OrderNumberGenerationFailed extends RuntimeException
{
    public function __construct(int $attempts)
    {
        parent::__construct("Could not mint a unique order number in {$attempts} attempts.");
    }
}
