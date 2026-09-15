<?php

declare(strict_types=1);

namespace App\Http\Requests\Customer;

/** Creating an address: every required field must be present. */
final class StoreAddressRequest extends AddressRequest
{
    protected function isPartial(): bool
    {
        return false;
    }
}
