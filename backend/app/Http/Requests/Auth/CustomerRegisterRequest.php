<?php

declare(strict_types=1);

namespace App\Http\Requests\Auth;

use Illuminate\Foundation\Http\FormRequest;

final class CustomerRegisterRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    /**
     * Note what is absent: `phone`.
     *
     * The number comes from the registration token, so a caller cannot verify one
     * number and register another. Accepting a phone here at all would be the
     * vulnerability.
     *
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        return [
            'registration_token' => ['required', 'string', 'max:2048'],
            'first_name' => ['required', 'string', 'min:1', 'max:80'],
            // Optional: plenty of people have one name.
            'last_name' => ['nullable', 'string', 'max:80'],
            // Optional, and never treated as verified — an OTP proves the phone.
            'email' => ['nullable', 'email:rfc', 'max:254'],
        ];
    }

    /** @return array<string, string> */
    public function messages(): array
    {
        return [
            'first_name.required' => 'Please tell us your first name.',
            'email.email' => 'Enter a valid email address, or leave it blank.',
        ];
    }
}
