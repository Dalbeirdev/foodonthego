<?php

declare(strict_types=1);

namespace App\Exceptions\Orders;

use RuntimeException;

/**
 * No credential pepper is configured.
 *
 * Refusing is the only safe answer. Deriving under an empty key would produce
 * credentials anybody who reads this source can compute, and an order whose
 * pickup code is public is worse than an order that failed to place.
 */
final class PickupCredentialUnavailable extends RuntimeException
{
    public function __construct()
    {
        parent::__construct('No pickup credential pepper is configured.');
    }
}
