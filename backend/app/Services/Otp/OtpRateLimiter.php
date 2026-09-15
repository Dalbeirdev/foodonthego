<?php

declare(strict_types=1);

namespace App\Services\Otp;

use App\Enums\ApiErrorCode;
use App\Exceptions\ApiException;
use App\Support\Phone\PhoneNumber;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\RateLimiter;

/**
 * Two independent limits on OTP requests, because they stop different things.
 *
 *  - **Per phone number** stops somebody using our SMS budget to harass one
 *    person, and stops a customer running up a bill by tapping repeatedly.
 *  - **Per IP** stops one client walking a range of numbers — which the per-phone
 *    limit alone would happily allow, since each number is only asked for once.
 *
 * Counters live in Redis (via the cache), which is the correct place for them:
 * losing one on a flush is merely generous. Attempt limits, where losing a counter
 * would be dangerous, live in MySQL on the challenge row instead.
 *
 * The phone key is hashed, so a Redis dump does not enumerate customers.
 */
final class OtpRateLimiter
{
    public function assertCanRequest(PhoneNumber $phone, ?string $ip): void
    {
        $window = (int) config('foodonthego.otp.request_window_seconds');

        $phoneKey = 'otp:phone:'.hash('sha256', $phone->e164);
        $phoneLimit = (int) config('foodonthego.otp.max_requests_per_phone');

        if (RateLimiter::tooManyAttempts($phoneKey, $phoneLimit)) {
            $this->reject($phoneKey, $phone, 'phone');
        }

        if ($ip !== null) {
            $ipKey = 'otp:ip:'.hash('sha256', $ip);
            $ipLimit = (int) config('foodonthego.otp.max_requests_per_ip');

            if (RateLimiter::tooManyAttempts($ipKey, $ipLimit)) {
                $this->reject($ipKey, $phone, 'ip');
            }

            RateLimiter::hit($ipKey, $window);
        }

        RateLimiter::hit($phoneKey, $window);
    }

    /** Clears the per-phone counter after a successful sign-in. */
    public function clearFor(PhoneNumber $phone): void
    {
        RateLimiter::clear('otp:phone:'.hash('sha256', $phone->e164));
    }

    private function reject(string $key, PhoneNumber $phone, string $dimension): never
    {
        $retryAfter = RateLimiter::availableIn($key);

        Log::warning('auth.otp.rate_limited', [
            'phone' => $phone->forLogging(),
            'dimension' => $dimension,
            'retry_after_seconds' => $retryAfter,
        ]);

        throw new ApiException(
            ApiErrorCode::OtpRateLimited,
            'Too many verification requests. Please wait a little before trying again.',
            // The retry window is given because a client needs it to show a
            // sensible countdown. The threshold itself is not: telling a caller
            // "5 per hour" hands them the shape of the limit to work around.
            ['retry_after_seconds' => $retryAfter],
        );
    }
}
