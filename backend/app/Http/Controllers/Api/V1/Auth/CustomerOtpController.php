<?php

declare(strict_types=1);

namespace App\Http\Controllers\Api\V1\Auth;

use App\Enums\ApiErrorCode;
use App\Exceptions\ApiException;
use App\Http\Requests\Auth\OtpRequestRequest;
use App\Http\Requests\Auth\OtpVerifyRequest;
use App\Http\Responses\ApiResponse;
use App\Models\User;
use App\Services\Auth\CustomerAuthService;
use App\Services\Auth\RegistrationTokenService;
use App\Services\Otp\OtpChallengeService;
use App\Services\Otp\OtpRateLimiter;
use App\Support\Phone\PhoneNumber;
use Illuminate\Http\JsonResponse;

final class CustomerOtpController
{
    public function __construct(
        private readonly OtpChallengeService $challenges,
        private readonly OtpRateLimiter $rateLimiter,
        private readonly RegistrationTokenService $registrationTokens,
        private readonly CustomerAuthService $customers,
    ) {}

    /**
     * Sends a one-time code.
     *
     * The response is **identical whether or not an account exists**. Returning
     * "new user" here would turn this endpoint into a free directory of who has a
     * FoodOnTheGo account — a caller could walk a range of numbers and learn our
     * customer list. Whether registration is needed is answered after the caller
     * has proved control of the number, in `verify`.
     */
    public function request(OtpRequestRequest $request): JsonResponse
    {
        $phone = $request->phoneNumber();

        // Checked before the rate limiter is charged, so a customer who taps
        // twice inside the cooldown is not also penalised as an abuser.
        $wait = $this->challenges->secondsUntilResendAllowed($phone);
        if ($wait > 0) {
            throw new ApiException(
                ApiErrorCode::OtpResendTooSoon,
                'Please wait a moment before requesting another code.',
                ['retry_after_seconds' => $wait],
            );
        }

        $this->rateLimiter->assertCanRequest($phone, $request->ip());

        $challenge = $this->challenges->issue($phone, $request->ip());

        return ApiResponse::ok([
            'phone_masked' => $phone->masked(),
            'expires_in_seconds' => (int) now()->diffInSeconds($challenge->expires_at, absolute: true),
            'resend_available_in_seconds' => (int) config('foodonthego.otp.resend_cooldown_seconds'),
            'otp_length' => (int) config('foodonthego.otp.length'),
        ]);
    }

    /**
     * Verifies a code and either signs the customer in or starts registration.
     */
    public function verify(OtpVerifyRequest $request): JsonResponse
    {
        $phone = $request->phoneNumber();

        $challenge = $this->challenges->verify($phone, $request->code());

        $customer = $this->customers->findCustomerByPhone($phone);

        if ($customer === null) {
            // New customer. No session yet — a token is only issued once there is
            // an account behind it.
            return ApiResponse::ok([
                'registration_required' => true,
                'registration_token' => $this->registrationTokens->issue($challenge, $phone),
                'registration_token_expires_in_seconds' => (int) config('foodonthego.otp.registration_token_ttl_seconds'),
                'phone_masked' => $phone->masked(),
            ]);
        }

        return $this->authenticated($customer, $phone);
    }

    /** Shared by verify (returning customer) and register (new customer). */
    private function authenticated(User $customer, PhoneNumber $phone): JsonResponse
    {
        // Throws for a suspended or disabled account. Verifying an OTP proves
        // control of a phone; it does not entitle a blocked account to a session.
        $token = $this->customers->issueSession($customer);

        $this->rateLimiter->clearFor($phone);

        return ApiResponse::ok([
            'registration_required' => false,
            'access_token' => $token->plainTextToken,
            'token_type' => 'Bearer',
            'expires_at' => $token->accessToken->expires_at?->toIso8601String(),
            'user' => $customer->toCustomerProfile(),
        ]);
    }
}
