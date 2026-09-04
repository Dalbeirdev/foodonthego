<?php

declare(strict_types=1);

namespace App\Http\Requests\Customer;

/**
 * Changing a planned journey. An absent field means "leave it".
 *
 * `expected_arrival_at` and `note` are the two fields where an explicit `null`
 * is meaningful — it clears them — which is why they are `sometimes|nullable`
 * rather than `sometimes|required` and why the service tests for key presence
 * rather than for a truthy value.
 */
final class UpdateTripRequest extends TripRequest
{
    protected function isPartial(): bool
    {
        return true;
    }
}
