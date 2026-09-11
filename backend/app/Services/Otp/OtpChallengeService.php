<?php

declare(strict_types=1);

namespace App\Services\Otp;

use App\Enums\ApiErrorCode;
use App\Exceptions\ApiException;
use App\Models\OtpChallenge;
use App\Support\Phone\PhoneNumber;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

/**
 * Issues and verifies one-time codes.
 *
 * The security properties this class is responsible for, each of which has a test:
 *
 *  - Codes are generated with a CSPRNG, never `rand()` or `mt_rand()`.
 *  - Codes are stored as a **peppered hash**, never in plaintext.
 *  - Comparison is constant time, so response timing does not leak a prefix.
 *  - A code expires, can be used exactly once, and dies after a fixed number of
 *    wrong guesses.
 *  - Issuing a new code invalidates the previous one, so a resend does not leave
 *    two live codes widening the guessing surface.
 *  - The code never reaches a log line, a response body or an exception message.
 */
final class OtpChallengeService
{
    public function __construct(
        private readonly OtpDeliveryProvider $provider,
    ) {}

    /**
     * Creates a challenge and asks the provider to deliver it.
     *
     * The database write and the send are ordered deliberately: the challenge is
     * committed first so a provider timeout cannot leave a delivered code with no
     * record of it, and the challenge is invalidated if the send definitely fails.
     */
    public function issue(PhoneNumber $phone, ?string $requestIp = null): OtpChallenge
    {
        $length = (int) config('foodonthego.otp.length');
        $code = $this->generateCode($length);

        $challenge = DB::transaction(function () use ($phone, $requestIp, $code): OtpChallenge {
            // Supersede anything still live for this number. Two valid codes at
            // once doubles an attacker's chances for no user benefit.
            $this->invalidateLiveChallenges($phone, 'superseded');

            return OtpChallenge::create([
                'uuid' => (string) Str::uuid(),
                'phone_e164' => $phone->e164,
                'otp_hash' => $this->hash($code),
                'expires_at' => now()->addSeconds((int) config('foodonthego.otp.ttl_seconds')),
                'attempts' => 0,
                'max_attempts' => (int) config('foodonthego.otp.max_attempts'),
                'resend_count' => 0,
                'last_sent_at' => now(),
                'request_ip' => $requestIp,
            ]);
        });

        try {
            $receipt = $this->provider->send($phone, $code);
        } catch (OtpDeliveryFailed $failure) {
            // The code was never delivered, so the challenge must not stay live —
            // otherwise a customer who never received anything still burns
            // attempts against a code that exists.
            $challenge->forceFill([
                'invalidated_at' => now(),
                'invalidated_reason' => 'delivery_failed',
            ])->save();

            Log::warning('auth.otp.delivery_failed', [
                'challenge_uuid' => $challenge->uuid,
                'phone' => $phone->forLogging(),
                'provider' => $failure->provider,
                'provider_code' => $failure->providerCode,
                'reason' => $failure->getMessage(),
            ]);

            throw new ApiException(
                ApiErrorCode::OtpSendFailed,
                "We couldn't send your verification code. Please try again.",
            );
        }

        Log::info('auth.otp.requested', [
            'challenge_uuid' => $challenge->uuid,
            'phone' => $phone->forLogging(),
            'provider' => $receipt->provider,
            'provider_reference' => $receipt->providerReference,
        ]);

        return $challenge;
    }

    /**
     * Verifies a submitted code against the newest live challenge.
     *
     * Returns the consumed challenge on success. Every failure path throws an
     * {@see ApiException} carrying a code the client can branch on.
     */
    public function verify(PhoneNumber $phone, string $submitted): OtpChallenge
    {
        /** @var OtpChallenge|null $challenge */
        $challenge = OtpChallenge::query()
            ->where('phone_e164', $phone->e164)
            ->whereNull('consumed_at')
            ->whereNull('invalidated_at')
            ->latest('id')
            // Locked for the duration of the transaction, so two simultaneous
            // verifications cannot both read attempts = 2 and both be allowed.
            ->lockForUpdate()
            ->first();

        if ($challenge === null) {
            Log::info('auth.otp.verify_no_challenge', ['phone' => $phone->forLogging()]);

            throw new ApiException(
                ApiErrorCode::OtpExpired,
                'That code has expired. Request a new one.',
            );
        }

        if ($challenge->isExpired()) {
            $challenge->forceFill([
                'invalidated_at' => now(),
                'invalidated_reason' => 'expired',
            ])->save();

            throw new ApiException(
                ApiErrorCode::OtpExpired,
                'That code has expired. Request a new one.',
            );
        }

        if (! $challenge->hasAttemptsLeft()) {
            throw new ApiException(
                ApiErrorCode::OtpTooManyAttempts,
                'Too many incorrect attempts. Request a new code.',
            );
        }

        // Counted BEFORE comparison. Incrementing afterwards would let a client
        // that disconnects mid-request guess indefinitely for free.
        $challenge->increment('attempts');
        $challenge->refresh();

        if (! hash_equals($challenge->otp_hash, $this->hash($submitted))) {
            $exhausted = ! $challenge->hasAttemptsLeft();

            if ($exhausted) {
                // The challenge dies. A correct code afterwards must NOT work:
                // otherwise an attacker who exhausts the counter simply waits for
                // the real user to be locked out and keeps trying elsewhere.
                $challenge->forceFill([
                    'invalidated_at' => now(),
                    'invalidated_reason' => 'attempts_exhausted',
                ])->save();
            }

            Log::warning('auth.otp.verify_failed', [
                'challenge_uuid' => $challenge->uuid,
                'phone' => $phone->forLogging(),
                'attempts' => $challenge->attempts,
                'exhausted' => $exhausted,
            ]);

            throw new ApiException(
                $exhausted ? ApiErrorCode::OtpTooManyAttempts : ApiErrorCode::OtpInvalid,
                $exhausted
                    ? 'Too many incorrect attempts. Request a new code.'
                    : "That code isn't correct. Please check it and try again.",
            );
        }

        $challenge->forceFill(['consumed_at' => now()])->save();

        Log::info('auth.otp.verified', [
            'challenge_uuid' => $challenge->uuid,
            'phone' => $phone->forLogging(),
        ]);

        return $challenge;
    }

    /**
     * Whether a resend is allowed yet, enforced server-side.
     *
     * The client shows a countdown, but a countdown is a courtesy — anyone can
     * change their device clock or call the endpoint directly, so the rule has to
     * live here.
     */
    public function secondsUntilResendAllowed(PhoneNumber $phone): int
    {
        /** @var OtpChallenge|null $latest */
        $latest = OtpChallenge::query()
            ->where('phone_e164', $phone->e164)
            ->latest('id')
            ->first();

        if ($latest?->last_sent_at === null) {
            return 0;
        }

        $cooldown = (int) config('foodonthego.otp.resend_cooldown_seconds');
        $elapsed = (int) $latest->last_sent_at->diffInSeconds(now(), absolute: true);

        return max(0, $cooldown - $elapsed);
    }

    public function invalidateLiveChallenges(PhoneNumber $phone, string $reason): void
    {
        OtpChallenge::query()
            ->where('phone_e164', $phone->e164)
            ->whereNull('consumed_at')
            ->whereNull('invalidated_at')
            ->update(['invalidated_at' => now(), 'invalidated_reason' => $reason]);
    }

    /**
     * A uniformly distributed numeric code from a cryptographically secure source.
     *
     * `random_int` rather than `rand`/`mt_rand`: the latter are seeded predictably
     * and an attacker who observes a few codes can predict the next.
     */
    private function generateCode(int $length): string
    {
        $code = '';
        for ($i = 0; $i < $length; $i++) {
            $code .= (string) random_int(0, 9);
        }

        return $code;
    }

    /**
     * Peppered SHA-256.
     *
     * The pepper is the application key, which lives in the environment rather
     * than the database — so a dumped `otp_challenges` table cannot be brute
     * forced offline, even though a six-digit space is tiny. bcrypt is not used
     * here on purpose: it would put a deliberate ~100 ms cost on a request that
     * happens on every sign-in, and the pepper already defeats offline attack.
     */
    private function hash(string $code): string
    {
        return hash_hmac('sha256', $code, (string) config('app.key'));
    }
}
