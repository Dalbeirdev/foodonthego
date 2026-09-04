<?php

declare(strict_types=1);

namespace App\Http\Requests\Customer;

use Carbon\CarbonImmutable;
use Illuminate\Contracts\Validation\Validator;
use Illuminate\Foundation\Http\FormRequest;

/**
 * Shared validation for planning and changing a journey.
 *
 * Absent by design, and the absence is the security control: `customer_id`,
 * `id`, `uuid`, `status`, `cancelled_at`, `cancellation_reason`,
 * `origin_address_id`. A body carrying any of them validates fine and has no
 * effect, because {@see tripAttributes()} returns only what was declared here
 * and the service writes columns by name.
 *
 * `status` in particular is never accepted. Cancelling is its own endpoint,
 * because "set status to CANCELLED" and "cancel this journey" differ in exactly
 * the way that matters: the second one can refuse.
 */
abstract class TripRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    /** Whether an omitted field means "leave it" (PATCH) or "not supplied" (POST). */
    abstract protected function isPartial(): bool;

    /** @return array<string, mixed> */
    public function rules(): array
    {
        $presence = $this->isPartial() ? ['sometimes', 'required'] : ['required'];
        $maxDays = (int) config('foodonthego.trips.max_days_ahead');
        $horizon = CarbonImmutable::now()->addDays($maxDays)->toDateTimeString();

        return [
            'origin' => [...$presence, 'array'],
            'destination' => [...$presence, 'array'],

            // Declared only for an endpoint the request actually carries. Adding
            // them unconditionally would make `required_without:origin.address_id`
            // fire on a PATCH that never mentions the origin — asking for a city
            // for a place the customer is not changing.
            ...($this->has('origin') ? $this->endpointRules('origin') : []),
            ...($this->has('destination') ? $this->endpointRules('destination') : []),

            // The lower bound is applied in withValidator() with the configured
            // grace, so that "leaving now" is not refused by a second or two.
            'departure_at' => [...$presence, 'date', "before_or_equal:{$horizon}"],

            // Nullable and normally null. Nothing computes an arrival time yet;
            // a traveller who knows theirs may state it. Ordering against
            // departure is checked in the service, which knows both values even
            // when a PATCH sends only one of them.
            'expected_arrival_at' => ['sometimes', 'nullable', 'date'],

            'traveller_count' => [
                'sometimes', 'integer', 'min:1',
                'max:'.(int) config('foodonthego.trips.max_travellers'),
            ],

            'note' => ['sometimes', 'nullable', 'string', 'max:280'],
        ];
    }

    /**
     * One end of the journey: either a saved address, or a typed place.
     *
     * `address_id` is a *uuid* of the caller's own saved address, and it is the
     * service — through Module 04's ownership-scoped lookup — that decides
     * whether the caller may use it. Validating it as "exists in
     * customer_addresses" here would be the classic mistake: it would confirm
     * that another customer's address exists before anybody checked who owns it.
     *
     * @return array<string, mixed>
     */
    private function endpointRules(string $prefix): array
    {
        $typed = "required_without:{$prefix}.address_id";

        return [
            "{$prefix}.address_id" => ['sometimes', 'nullable', 'uuid'],

            "{$prefix}.label" => ['sometimes', 'nullable', 'string', 'max:60'],
            "{$prefix}.address_line" => ['sometimes', 'nullable', 'string', 'max:180'],
            "{$prefix}.city" => [$typed, 'nullable', 'string', 'min:1', 'max:90'],
            "{$prefix}.state" => ['sometimes', 'nullable', 'string', 'max:90'],
            "{$prefix}.country_code" => [$typed, 'nullable', 'string', 'size:2', 'alpha'],

            // Accepted so a future Places-backed client can supply real ones.
            // Never invented server-side, and null is the normal value.
            "{$prefix}.latitude" => ['sometimes', 'nullable', 'numeric', 'between:-90,90'],
            "{$prefix}.longitude" => ['sometimes', 'nullable', 'numeric', 'between:-180,180'],
            "{$prefix}.place_id" => ['sometimes', 'nullable', 'string', 'max:255'],
        ];
    }

    public function withValidator(Validator $validator): void
    {
        $validator->after(function (Validator $validator): void {
            $this->validateDepartureIsAhead($validator);
            $this->validateCoordinatePairs($validator);
        });
    }

    /**
     * A departure time must be ahead of now, give or take the configured grace.
     *
     * Expressed here rather than as `after:now` because `now` is evaluated when
     * the rule string is built, and the grace has to be subtracted from it — a
     * traveller tapping "leave now" sends a timestamp that is already a second
     * old by the time it arrives.
     */
    private function validateDepartureIsAhead(Validator $validator): void
    {
        if (! $this->has('departure_at') || $validator->errors()->has('departure_at')) {
            return;
        }

        $grace = (int) config('foodonthego.trips.departure_grace_minutes');
        $earliest = CarbonImmutable::now()->subMinutes($grace);

        try {
            $departure = CarbonImmutable::parse((string) $this->input('departure_at'));
        } catch (\Throwable) {
            return; // The `date` rule has already reported this.
        }

        if ($departure->lessThan($earliest)) {
            $validator->errors()->add('departure_at', 'Choose a departure time in the future.');
        }
    }

    /**
     * A latitude without a longitude is not half a location — it is no location.
     *
     * Storing one of the pair would leave a row that looks geocoded to Module 09
     * and is not, which is the same class of mistake as inventing both.
     */
    private function validateCoordinatePairs(Validator $validator): void
    {
        foreach (['origin', 'destination'] as $prefix) {
            $lat = $this->input("{$prefix}.latitude");
            $lng = $this->input("{$prefix}.longitude");

            if (($lat === null) !== ($lng === null)) {
                $validator->errors()->add(
                    "{$prefix}.longitude",
                    'Give both a latitude and a longitude, or neither.',
                );
            }
        }
    }

    /**
     * Only the keys the service is allowed to act on.
     *
     * @return array<string, mixed>
     */
    public function tripAttributes(): array
    {
        $validated = $this->validated();

        $attributes = [];

        foreach (['origin', 'destination'] as $endpoint) {
            if (array_key_exists($endpoint, $validated)) {
                $attributes[$endpoint] = $validated[$endpoint];
            }
        }

        foreach (['departure_at', 'expected_arrival_at', 'traveller_count', 'note'] as $field) {
            if (array_key_exists($field, $validated)) {
                $attributes[$field] = $validated[$field];
            }
        }

        return $attributes;
    }

    /** @return array<string, string> */
    public function messages(): array
    {
        return [
            'origin.required' => 'Choose where you are setting off from.',
            'destination.required' => 'Choose where you are going.',
            'origin.city.required_without' => 'Enter the city you are setting off from.',
            'destination.city.required_without' => 'Enter the city you are going to.',
            'origin.country_code.required_without' => 'Choose the country you are setting off from.',
            'destination.country_code.required_without' => 'Choose the country you are going to.',
            'departure_at.required' => 'Choose when you are setting off.',
            'departure_at.before_or_equal' => 'That is too far ahead to plan a journey.',
        ];
    }
}
