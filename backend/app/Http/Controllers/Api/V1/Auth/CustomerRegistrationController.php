<?php

declare(strict_types=1);

namespace App\Http\Controllers\Api\V1\Auth;

use App\Http\Requests\Auth\CustomerRegisterRequest;
use App\Http\Responses\ApiResponse;
use App\Models\User;
use App\Services\Auth\CustomerAuthService;
use App\Services\Auth\RegistrationTokenService;
use App\Services\Otp\OtpRateLimiter;
use App\Support\Phone\PhoneNumber;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\Log;

final class CustomerRegistrationController
{
    public function __construct(
        private readonly RegistrationTokenService $registrationTokens,
        private readonly CustomerAuthService $customers,
        private readonly OtpRateLimiter $rateLimiter,
    ) {}

    public function __invoke(CustomerRegisterRequest $request): JsonResponse
    {
        // The phone comes from the token — never from the request body.
        $phone = $this->registrationTokens->verifiedPhoneFor(
            (string) $request->string('registration_token'),
        );

        // Idempotent by design: a retried request (a lost response on a patchy
        // connection, or a double tap that beat the client guard) returns the
        // existing account rather than failing or creating a second one.
        $existing = $this->customers->findCustomerByPhone($phone);

        $customer = $existing ?? $this->customers->register(
            phone: $phone,
            firstName: trim((string) $request->string('first_name')),
            lastName: $request->filled('last_name') ? trim((string) $request->string('last_name')) : null,
            email: $request->filled('email') ? strtolower(trim((string) $request->string('email'))) : null,
        );

        if ($existing === null) {
            Log::info('auth.registration.completed', [
                'user_uuid' => $customer->uuid,
                'phone' => $phone->forLogging(),
            ]);
        }

        return $this->session($customer, $phone);
    }

    private function session(User $customer, PhoneNumber $phone): JsonResponse
    {
        $token = $this->customers->issueSession($customer);
        $this->rateLimiter->clearFor($phone);

        return ApiResponse::created([
            'access_token' => $token->plainTextToken,
            'token_type' => 'Bearer',
            'expires_at' => $token->accessToken->expires_at?->toIso8601String(),
            'user' => $customer->toCustomerProfile(),
        ]);
    }
}
