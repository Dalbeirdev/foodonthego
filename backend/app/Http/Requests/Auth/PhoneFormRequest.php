<?php

declare(strict_types=1);

namespace App\Http\Requests\Auth;

use App\Enums\ApiErrorCode;
use App\Exceptions\ApiException;
use App\Support\Phone\PhoneNormalizer;
use App\Support\Phone\PhoneNumber;
use Illuminate\Foundation\Http\FormRequest;

/**
 * Shared by every request that carries a phone number.
 *
 * The point of sharing it is that normalization cannot drift between requesting a
 * code and verifying one. If those two endpoints normalized differently, a number
 * would be stored one way and looked up another, and verification would fail for
 * reasons nobody could reproduce.
 */
abstract class PhoneFormRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    /** @return array<string, mixed> */
    public function rules(): array
    {
        return [
            'phone' => ['required', 'string', 'max:24'],
            'country_code' => ['sometimes', 'string', 'max:4'],
        ];
    }

    /**
     * The authoritative normalization.
     *
     * Flutter normalizes too, for a better keyboard and instant feedback, but the
     * client is not trusted: the number that becomes an account identity is the
     * one this method produces.
     */
    public function phoneNumber(): PhoneNumber
    {
        $phone = PhoneNormalizer::normalize(
            (string) $this->string('phone'),
            $this->has('country_code') ? (string) $this->string('country_code') : null,
        );

        if ($phone === null) {
            throw new ApiException(
                ApiErrorCode::InvalidPhone,
                'Enter a valid mobile number.',
            );
        }

        if (! PhoneNormalizer::isSupportedCountry($phone->countryCode)) {
            throw new ApiException(
                ApiErrorCode::UnsupportedPhoneRegion,
                'FoodOnTheGo is not available in that country yet.',
            );
        }

        return $phone;
    }
}
