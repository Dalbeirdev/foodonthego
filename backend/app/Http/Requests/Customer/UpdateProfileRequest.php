<?php

declare(strict_types=1);

namespace App\Http\Requests\Customer;

use App\Services\Profile\CustomerProfileService;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * The only fields a customer may change about themselves.
 *
 * Note what is absent, and that the absence is the security control:
 * `phone_e164`, `phone_verified_at`, `role`, `status`, `email_verified_at`,
 * `uuid`, `id`, `created_at`. A request carrying any of them validates fine and
 * changes nothing, because `validated()` returns only the keys declared here and
 * {@see CustomerProfileService} reads three of them by name.
 *
 * `sometimes` throughout: this is a PATCH. Omitting a field means "leave it",
 * which is different from sending null, which for the two optional fields means
 * "clear it".
 */
final class UpdateProfileRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    /** @return array<string, mixed> */
    public function rules(): array
    {
        return [
            'first_name' => [
                'sometimes',
                'required',
                'string',
                // Trimmed before the length check, so "   " is blank rather than
                // three characters.
                'min:1',
                'max:80',
                // Rejects a name that is only digits or only punctuation while
                // accepting every real one: José, O'Brien, Aarav-Krishna,
                // प्रिया, 李. Anything with at least one letter passes.
                'regex:/\p{L}/u',
            ],
            'last_name' => ['sometimes', 'nullable', 'string', 'max:80'],
            'email' => ['sometimes', 'nullable', 'email:rfc', 'max:254', Rule::unique('users', 'email')->ignore($this->user()?->getKey())],
        ];
    }

    protected function prepareForValidation(): void
    {
        // Trimmed before validation rather than after, so `min:1` sees what the
        // database would store.
        $trimmed = [];
        foreach (['first_name', 'last_name', 'email'] as $field) {
            if ($this->has($field) && is_string($this->input($field))) {
                $trimmed[$field] = trim($this->input($field));
            }
        }

        if ($trimmed !== []) {
            $this->merge($trimmed);
        }
    }

    /** @return array<string, string> */
    public function messages(): array
    {
        return [
            'first_name.required' => 'Please enter your first name.',
            'first_name.regex' => 'Please enter your name as you write it.',
            'email.email' => 'Enter a valid email address, or leave it blank.',
            'email.unique' => 'That email address is already on another account.',
        ];
    }
}
