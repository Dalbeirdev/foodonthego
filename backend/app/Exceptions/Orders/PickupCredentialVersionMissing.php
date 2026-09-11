<?php

declare(strict_types=1);

namespace App\Exceptions\Orders;

use RuntimeException;

/**
 * A credential was about to be derived from an order whose version is not set.
 *
 * Almost always means the order was created and never reloaded, so the model
 * holds NULL where the column holds its default of 1. Deriving anyway would
 * produce a credential that does not match the digest stored for the same
 * order — a pickup code that fails at the counter with nothing in any log to
 * say why. Refusing is the cheap failure; the alternative is a customer
 * standing at a restaurant with a code that does not work.
 */
final class PickupCredentialVersionMissing extends RuntimeException
{
    public function __construct(mixed $orderKey)
    {
        parent::__construct(
            'Order '.var_export($orderKey, true).' has no pickup credential version; '
            .'refusing to derive a credential that would not match its stored digest. '
            .'The order was probably created and not reloaded.',
        );
    }
}
