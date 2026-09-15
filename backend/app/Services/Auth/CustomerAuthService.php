<?php

declare(strict_types=1);

namespace App\Services\Auth;

use App\Enums\AccountStatus;
use App\Enums\Role;
use App\Exceptions\ApiException;
use App\Models\User;
use App\Support\Phone\PhoneNumber;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;
use Laravel\Sanctum\NewAccessToken;

/**
 * Turns a verified phone number into an authenticated customer session.
 */
final class CustomerAuthService
{
    /** Sanctum ability granted to a customer token. Restaurant and admin APIs require others. */
    public const CUSTOMER_ABILITY = 'customer';

    public function findCustomerByPhone(PhoneNumber $phone): ?User
    {
        return User::query()
            ->where('phone_e164', $phone->e164)
            ->where('role', Role::Customer->value)
            ->first();
    }

    /**
     * Registers a customer for an already-verified phone number.
     *
     * The phone argument comes from the registration token, never from the
     * request body — see {@see RegistrationTokenService}.
     *
     * Two customers hitting this simultaneously for the same number is a real
     * race: both `findCustomerByPhone` calls can return null before either
     * inserts. The unique index on `phone_e164` is what actually prevents a
     * duplicate; the caught QueryException turns that collision into the correct
     * outcome — the existing account — rather than a 500.
     */
    public function register(
        PhoneNumber $phone,
        string $firstName,
        ?string $lastName,
        ?string $email,
    ): User {
        try {
            return DB::transaction(function () use ($phone, $firstName, $lastName, $email): User {
                return User::create([
                    'uuid' => (string) Str::uuid(),
                    'first_name' => $firstName,
                    'last_name' => $lastName,
                    'name' => trim($firstName.' '.($lastName ?? '')),
                    'email' => $email,
                    'phone' => $phone->e164,
                    'phone_e164' => $phone->e164,
                    // Set here and nowhere else: the account exists because an OTP
                    // for this number was verified moments ago.
                    'phone_verified_at' => now(),
                    // Deliberately NOT set. Verifying a phone says nothing about
                    // whether the person owns the email address they typed.
                    'email_verified_at' => null,
                    'role' => Role::Customer->value,
                    'status' => AccountStatus::Active->value,
                    'password' => null,
                    'is_active' => true,
                ]);
            });
        } catch (QueryException $exception) {
            if (! $this->isUniqueViolation($exception)) {
                throw $exception;
            }

            $existing = $this->findCustomerByPhone($phone);
            if ($existing !== null) {
                Log::info('auth.registration.raced', ['phone' => $phone->forLogging()]);

                return $existing;
            }

            throw $exception;
        }
    }

    /**
     * Issues a session for a customer, after checking they are allowed one.
     *
     * @throws ApiException when the account cannot authenticate.
     */
    public function issueSession(User $user): NewAccessToken
    {
        $status = $user->status;

        if (! $status->canAuthenticate()) {
            Log::warning('auth.login.blocked', [
                'user_uuid' => $user->uuid,
                'status' => $status->value,
            ]);

            throw new ApiException(
                $status->blockedErrorCode(),
                $status === AccountStatus::Suspended
                    ? 'Your account is currently unavailable. Please contact support.'
                    : 'This account is no longer active. Please contact support.',
            );
        }

        $token = $user->createToken(
            name: 'customer-mobile',
            abilities: [self::CUSTOMER_ABILITY],
            expiresAt: now()->addSeconds((int) config('foodonthego.auth.token_ttl_seconds')),
        );

        $user->forceFill(['last_login_at' => now()])->save();

        Log::info('auth.login.succeeded', [
            'user_uuid' => $user->uuid,
            'token_id' => $token->accessToken->getKey(),
        ]);

        return $token;
    }

    /** MySQL reports a unique-constraint collision as SQLSTATE 23000 / errno 1062. */
    private function isUniqueViolation(QueryException $exception): bool
    {
        return $exception->getCode() === '23000'
            || ($exception->errorInfo[1] ?? null) === 1062;
    }
}
