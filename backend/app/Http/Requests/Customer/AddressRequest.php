<?php

declare(strict_types=1);

namespace App\Http\Requests\Customer;

use App\Enums\AddressType;
use App\Support\Address\PostalCode;
use Illuminate\Contracts\Validation\Validator;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Shared validation for creating and updating a saved address.
 *
 * Absent by design, and the absence is the security control: `customer_id`,
 * `id`, `uuid`, `created_by`, `default_for_customer`. Ownership comes from the
 * authenticated actor and nowhere else, so a body containing `customer_id`
 * validates fine and has no effect.
 *
 * `is_default` **is** accepted, because asking for an address to be the default
 * is a legitimate thing a customer does. It is not a fillable column — the
 * service sets it, holding the lock that keeps exactly one.
 */
abstract class AddressRequest extends FormRequest
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
        $optional = $this->isPartial() ? ['sometimes', 'nullable'] : ['nullable'];

        return [
            'type' => [...$presence, Rule::enum(AddressType::class)],

            // Optional even on create: HOME and WORK are labelled from the type.
            // Required for OTHER, enforced in withValidator() below where the
            // type is known.
            'label' => [...$optional, 'string', 'max:60'],

            'address_line_1' => [...$presence, 'string', 'min:3', 'max:180'],
            'address_line_2' => [...$optional, 'string', 'max:180'],
            'landmark' => [...$optional, 'string', 'max:120'],
            'city' => [...$presence, 'string', 'min:1', 'max:90'],
            'state' => [...$presence, 'string', 'min:1', 'max:90'],

            // Conditionally required per country — see withValidator().
            'postal_code' => [...$optional, 'string', 'max:16'],

            'country_code' => [...$presence, 'string', 'size:2', 'alpha'],

            // Reserved for the mapping module. Accepted so a future Places-backed
            // client can supply them; never invented server-side.
            'latitude' => [...$optional, 'numeric', 'between:-90,90'],
            'longitude' => [...$optional, 'numeric', 'between:-180,180'],
            'place_id' => [...$optional, 'string', 'max:255'],

            'is_default' => ['sometimes', 'boolean'],
        ];
    }

    protected function prepareForValidation(): void
    {
        $trimmed = [];
        foreach ([
            'label', 'address_line_1', 'address_line_2', 'landmark',
            'city', 'state', 'postal_code', 'country_code', 'place_id',
        ] as $field) {
            if ($this->has($field) && is_string($this->input($field))) {
                $trimmed[$field] = trim($this->input($field));
            }
        }

        if (is_string($this->input('country_code'))) {
            $trimmed['country_code'] = strtoupper(trim($this->input('country_code')));
        }

        if ($trimmed !== []) {
            $this->merge($trimmed);
        }
    }

    /**
     * The two rules that need another field's value to decide.
     */
    public function withValidator(Validator $validator): void
    {
        $validator->after(function (Validator $validator): void {
            $type = $this->input('type');
            $label = trim((string) $this->input('label', ''));

            // A custom category with no name is just "Other" — the customer has
            // to say what the place is, or the list is unreadable.
            if ($type === AddressType::Other->value && $label === '') {
                $validator->errors()->add(
                    'label',
                    'Give this address a name, like "Parents\' House".',
                );
            }

            $country = strtoupper((string) $this->input('country_code', ''));
            if ($country === '' || ! $this->has('postal_code')) {
                return;
            }

            $postal = $this->input('postal_code');

            if (! PostalCode::isValid($country, is_string($postal) ? $postal : null)) {
                $example = PostalCode::exampleFor($country);

                $validator->errors()->add(
                    'postal_code',
                    $example !== null
                        ? "Enter a valid postal code for that country, like {$example}."
                        : 'Enter a valid postal code for that country.',
                );
            }
        });
    }

    /**
     * Only the columns the service is allowed to write.
     *
     * `is_default` is read separately by the controller, so it cannot arrive here
     * and be mass-assigned onto the model.
     *
     * @return array<string, mixed>
     */
    public function addressAttributes(): array
    {
        return collect($this->validated())
            ->except(['is_default'])
            ->all();
    }

    /** Null when the request said nothing about the default. */
    public function defaultPreference(): ?bool
    {
        return $this->has('is_default') ? $this->boolean('is_default') : null;
    }

    /** @return array<string, string> */
    public function messages(): array
    {
        return [
            'type.Illuminate\\Validation\\Rules\\Enum' => 'Choose Home, Work or Other.',
            'address_line_1.required' => 'Enter the flat, building or street.',
            'city.required' => 'Enter the city.',
            'state.required' => 'Enter the state.',
            'country_code.size' => 'Country must be a two-letter code, like IN.',
        ];
    }
}
