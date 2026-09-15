<?php

declare(strict_types=1);

namespace App\Http\Requests\Customer;

use App\Enums\LocationSourceType;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Creating a trip.
 *
 * Absent by design, and the absence is the security control: `customer_id`,
 * `id`, `uuid`, `status`, `route_status`, `cancelled_at`, and every routing field
 * a caller might hope to seed — `distance`, `duration`, `polyline`, `eta`. A body
 * carrying any of them validates fine and has no effect, because
 * {@see tripAttributes()} returns only what is declared here and the service
 * writes columns by name.
 *
 * `saved_address_id` is validated as a *uuid* and deliberately **not** with
 * `exists:customer_addresses,uuid`. An existence rule would confirm that another
 * customer's address is real before anybody had checked who owns it; the service
 * resolves it through Module 04's ownership-scoped lookup instead.
 */
final class StoreTripRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    /** @return array<string, mixed> */
    public function rules(): array
    {
        return [
            'origin' => ['required', 'array'],
            'destination' => ['required', 'array'],

            ...$this->endpointRules('origin'),
            ...$this->endpointRules('destination'),
        ];
    }

    /**
     * One end of the trip.
     *
     * Coordinates are `required` and range-bounded here, and checked again in the
     * service. Two layers because they answer different questions: this one keeps
     * a malformed request from reaching business logic, and the service's keeps a
     * caller that arrives some other way from writing a trip Module 06 cannot
     * route.
     *
     * @return array<string, mixed>
     */
    private function endpointRules(string $prefix): array
    {
        $isSaved = "{$prefix}.source_type,".LocationSourceType::SavedAddress->value;

        return [
            "{$prefix}.source_type" => ['required', Rule::enum(LocationSourceType::class)],

            // Required only for a saved-address endpoint; forbidden to matter
            // for the others, which carry their own place data.
            "{$prefix}.saved_address_id" => ['nullable', 'uuid', "required_if:{$isSaved}"],

            "{$prefix}.place_id" => ['nullable', 'string', 'max:255'],

            "{$prefix}.display_name" => ['nullable', 'string', 'max:180'],
            "{$prefix}.formatted_address" => ['nullable', 'string', 'max:400'],

            // A saved address supplies its own position from the database, so the
            // client is not asked for one; every other source must carry a pair.
            "{$prefix}.latitude" => ["required_unless:{$isSaved}", 'nullable', 'numeric', 'between:-90,90'],
            "{$prefix}.longitude" => ["required_unless:{$isSaved}", 'nullable', 'numeric', 'between:-180,180'],

            "{$prefix}.city" => ['nullable', 'string', 'max:120'],
            "{$prefix}.region" => ['nullable', 'string', 'max:120'],
            "{$prefix}.country_code" => ['nullable', 'string', 'size:2', 'alpha'],
            "{$prefix}.postal_code" => ['nullable', 'string', 'max:16'],
        ];
    }

    /**
     * Only the keys the service is allowed to act on.
     *
     * @return array<string, mixed>
     */
    public function tripAttributes(): array
    {
        $validated = $this->validated();

        return [
            'origin' => (array) ($validated['origin'] ?? []),
            'destination' => (array) ($validated['destination'] ?? []),
        ];
    }

    /** @return array<string, string> */
    public function messages(): array
    {
        return [
            'origin.required' => 'Choose where you are setting off from.',
            'destination.required' => 'Choose where you are going.',
            'origin.latitude.required_unless' => 'That starting point has no location we can use.',
            'origin.longitude.required_unless' => 'That starting point has no location we can use.',
            'destination.latitude.required_unless' => 'That destination has no location we can use.',
            'destination.longitude.required_unless' => 'That destination has no location we can use.',
            'origin.saved_address_id.required_if' => 'Choose a saved address.',
            'destination.saved_address_id.required_if' => 'Choose a saved address.',
        ];
    }
}
