<?php

declare(strict_types=1);

namespace App\Http\Requests\Customer;

use Illuminate\Foundation\Http\FormRequest;

/**
 * Cancelling a journey.
 *
 * The whole request is one optional sentence. Cancelling takes no fields because
 * it is not an edit — the endpoint decides what changes, and the customer only
 * decides whether it happens and, if they like, why.
 */
final class CancelTripRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    /** @return array<string, mixed> */
    public function rules(): array
    {
        return [
            'reason' => ['sometimes', 'nullable', 'string', 'max:120'],
        ];
    }

    public function reason(): ?string
    {
        $reason = $this->input('reason');

        return is_string($reason) ? $reason : null;
    }
}
