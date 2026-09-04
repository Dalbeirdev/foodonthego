<?php

declare(strict_types=1);

namespace App\Http\Requests\Customer;

/**
 * Planning a journey. Every required field must be present.
 */
final class StoreTripRequest extends TripRequest
{
    protected function isPartial(): bool
    {
        return false;
    }
}
