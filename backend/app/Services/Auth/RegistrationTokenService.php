<?php

declare(strict_types=1);

namespace App\Services\Auth;

use App\Enums\ApiErrorCode;
use App\Exceptions\ApiException;
use App\Models\OtpChallenge;
use App\Support\Phone\PhoneNumber;
use Illuminate\Contracts\Encryption\DecryptException;
use Illuminate\Support\Facades\Crypt;

/**
 * The bridge between "this phone was verified" and "create this account".
 *
 * The attack it prevents: verify a number you control, then post a registration
 * naming somebody else's number and take their account. So the phone is **never**
 * read from the registration request — it is carried inside this token, which is
 * encrypted-and-signed by the application key, bound to the consumed challenge,
 * and short-lived.
 *
 * Laravel's `Crypt` is AES-256-GCM with a MAC. A caller cannot forge one, cannot
 * alter the phone inside one, and cannot read what it contains.
 */
final class RegistrationTokenService
{
    public function issue(OtpChallenge $challenge, PhoneNumber $phone): string
    {
        return Crypt::encryptString(json_encode([
            'challenge_uuid' => $challenge->uuid,
            'phone_e164' => $phone->e164,
            'issued_at' => now()->timestamp,
        ], JSON_THROW_ON_ERROR));
    }

    /**
     * Decrypts, validates and returns the verified phone.
     *
     * @throws ApiException when the token is forged, altered, stale, or its
     *                      challenge has been reused.
     */
    public function verifiedPhoneFor(string $token): PhoneNumber
    {
        try {
            $payload = json_decode(Crypt::decryptString($token), true, 512, JSON_THROW_ON_ERROR);
        } catch (DecryptException|\JsonException) {
            throw new ApiException(
                ApiErrorCode::RegistrationTokenInvalid,
                'That registration session is not valid. Please verify your number again.',
            );
        }

        if (! is_array($payload)
            || ! isset($payload['challenge_uuid'], $payload['phone_e164'], $payload['issued_at'])) {
            throw new ApiException(
                ApiErrorCode::RegistrationTokenInvalid,
                'That registration session is not valid. Please verify your number again.',
            );
        }

        $ttl = (int) config('foodonthego.otp.registration_token_ttl_seconds');
        if (now()->timestamp - (int) $payload['issued_at'] > $ttl) {
            throw new ApiException(
                ApiErrorCode::RegistrationTokenExpired,
                'That registration session has expired. Please verify your number again.',
            );
        }

        /** @var OtpChallenge|null $challenge */
        $challenge = OtpChallenge::query()->where('uuid', $payload['challenge_uuid'])->first();

        // The challenge must exist and must have been consumed by a successful
        // verification. A token whose challenge was never consumed did not come
        // from this flow.
        if ($challenge === null || $challenge->consumed_at === null) {
            throw new ApiException(
                ApiErrorCode::RegistrationTokenInvalid,
                'That registration session is not valid. Please verify your number again.',
            );
        }

        // And the phone inside the token must still match the challenge it names,
        // so a token cannot be replayed against a different verification.
        if ($challenge->phone_e164 !== $payload['phone_e164']) {
            throw new ApiException(
                ApiErrorCode::RegistrationTokenInvalid,
                'That registration session is not valid. Please verify your number again.',
            );
        }

        return PhoneNumber::fromE164((string) $payload['phone_e164']);
    }
}
