<?php

declare(strict_types=1);

namespace App\Http\Requests\Customer;

/**
 * Updating an address: a PATCH, so an omitted field means "leave it".
 *
 * Sending a required field as blank is still rejected — "leave it alone" and
 * "erase it" are different requests, and only one of them is allowed.
 */
final class UpdateAddressRequest extends AddressRequest
{
    protected function isPartial(): bool
    {
        return true;
    }
}
