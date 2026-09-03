<?php

declare(strict_types=1);

namespace App\Http\Requests\Auth;

/**
 * Verification takes the same phone plus a code. It extends the request form so
 * normalization cannot drift between requesting and verifying — a number that
 * normalizes one way on request and another on verify would never match.
 */
final class OtpVerifyRequest extends PhoneFormRequest
{
    /** @return array<string, mixed> */
    public function rules(): array
    {
        return array_merge(parent::rules(), [
            // Digits only, and exactly the configured length. Bounding it here
            // keeps a megabyte of "code" out of the hash function.
            'otp' => ['required', 'string', 'regex:/^[0-9]+$/', 'size:'.config('foodonthego.otp.length')],
        ]);
    }

    /** @return array<string, string> */
    public function messages(): array
    {
        return [
            'otp.size' => 'Enter the :size-digit code we sent you.',
            'otp.regex' => 'The code is digits only.',
        ];
    }

    public function code(): string
    {
        return (string) $this->string('otp');
    }
}
