<?php

declare(strict_types=1);

namespace Tests\Unit;

use App\Enums\ApiErrorCode;
use App\Exceptions\ApiException;
use App\Models\OtpChallenge;
use App\Services\Otp\OtpChallengeService;
use App\Services\Otp\OtpDeliveryProvider;
use App\Support\Phone\PhoneNumber;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Support\RecordingOtpProvider;
use Tests\TestCase;

/**
 * The security core of Module 03. Every test here corresponds to an attack that
 * works against a naive OTP implementation.
 */
final class OtpChallengeServiceTest extends TestCase
{
    use RefreshDatabase;

    private RecordingOtpProvider $provider;

    private OtpChallengeService $service;

    private PhoneNumber $phone;

    protected function setUp(): void
    {
        parent::setUp();

        $this->provider = new RecordingOtpProvider;
        $this->app->instance(OtpDeliveryProvider::class, $this->provider);
        $this->service = $this->app->make(OtpChallengeService::class);
        $this->phone = PhoneNumber::fromE164('+919876543210');
    }

    public function test_a_code_is_never_stored_in_plaintext(): void
    {
        $challenge = $this->service->issue($this->phone);
        $code = $this->provider->lastCode();

        // The row must not contain the code in any column, in any form.
        $row = (array) \DB::table('otp_challenges')->where('id', $challenge->id)->first();

        foreach ($row as $column => $value) {
            $this->assertStringNotContainsString(
                $code,
                (string) $value,
                "Column {$column} contains the plaintext OTP.",
            );
        }
    }

    public function test_the_stored_hash_is_peppered_with_the_application_key(): void
    {
        $challenge = $this->service->issue($this->phone);
        $code = $this->provider->lastCode();

        // Anybody holding the table but not the key cannot brute force the six
        // digit space, because the hash they would have to reproduce needs the
        // pepper.
        $this->assertSame(hash_hmac('sha256', $code, (string) config('app.key')), $challenge->otp_hash);
        $this->assertNotSame(hash('sha256', $code), $challenge->otp_hash);
    }

    public function test_the_hash_is_hidden_from_serialization(): void
    {
        $challenge = $this->service->issue($this->phone);

        // A future controller that returns a challenge by accident must not leak
        // the material an offline attack would need.
        $this->assertArrayNotHasKey('otp_hash', $challenge->toArray());
    }

    public function test_codes_are_the_configured_length_and_numeric(): void
    {
        config(['foodonthego.otp.length' => 6]);
        $this->service->issue($this->phone);

        $this->assertMatchesRegularExpression('/^[0-9]{6}$/', $this->provider->lastCode());
    }

    public function test_generated_codes_are_not_predictable(): void
    {
        // Not a statistical proof — a smoke test that we are not returning a
        // constant, a counter, or a seeded sequence.
        $codes = [];
        for ($i = 0; $i < 40; $i++) {
            $this->service->issue($this->phone);
            $codes[] = $this->provider->lastCode();
        }

        $this->assertGreaterThan(30, count(array_unique($codes)));
    }

    public function test_a_correct_code_verifies_once_and_then_never_again(): void
    {
        $this->service->issue($this->phone);
        $code = $this->provider->lastCode();

        $challenge = $this->service->verify($this->phone, $code);
        $this->assertNotNull($challenge->consumed_at);

        // Replay. An intercepted code must be worthless the moment it is used.
        try {
            $this->service->verify($this->phone, $code);
            $this->fail('A consumed code was accepted a second time.');
        } catch (ApiException $e) {
            $this->assertSame(ApiErrorCode::OtpExpired, $e->errorCode);
        }
    }

    public function test_a_wrong_code_is_rejected_and_burns_an_attempt(): void
    {
        $challenge = $this->service->issue($this->phone);

        try {
            $this->service->verify($this->phone, '000000');
            $this->fail('A wrong code was accepted.');
        } catch (ApiException $e) {
            $this->assertSame(ApiErrorCode::OtpInvalid, $e->errorCode);
        }

        $this->assertSame(1, $challenge->fresh()->attempts);
    }

    public function test_the_challenge_dies_after_the_configured_number_of_wrong_guesses(): void
    {
        config(['foodonthego.otp.max_attempts' => 3]);
        $this->service->issue($this->phone);
        $correct = $this->provider->lastCode();

        for ($i = 0; $i < 2; $i++) {
            try {
                $this->service->verify($this->phone, $this->wrongCodeFor($correct));
            } catch (ApiException $e) {
                $this->assertSame(ApiErrorCode::OtpInvalid, $e->errorCode);
            }
        }

        // Third wrong guess exhausts it.
        try {
            $this->service->verify($this->phone, $this->wrongCodeFor($correct));
            $this->fail('Expected the challenge to be exhausted.');
        } catch (ApiException $e) {
            $this->assertSame(ApiErrorCode::OtpTooManyAttempts, $e->errorCode);
        }

        // And the *correct* code no longer works. This is the part that is easy to
        // get wrong: an attacker who burns the counter must not be able to wait
        // and then use a code they later obtain.
        try {
            $this->service->verify($this->phone, $correct);
            $this->fail('A correct code was accepted after the challenge was exhausted.');
        } catch (ApiException $e) {
            $this->assertSame(ApiErrorCode::OtpExpired, $e->errorCode);
        }
    }

    public function test_an_expired_code_is_rejected_even_when_correct(): void
    {
        config(['foodonthego.otp.ttl_seconds' => 300]);
        $this->service->issue($this->phone);
        $code = $this->provider->lastCode();

        $this->travel(301)->seconds();

        try {
            $this->service->verify($this->phone, $code);
            $this->fail('An expired code was accepted.');
        } catch (ApiException $e) {
            $this->assertSame(ApiErrorCode::OtpExpired, $e->errorCode);
        }
    }

    public function test_requesting_a_new_code_invalidates_the_previous_one(): void
    {
        $this->service->issue($this->phone);
        $first = $this->provider->lastCode();

        $this->service->issue($this->phone);
        $second = $this->provider->lastCode();

        // Two live codes would double an attacker's chances per challenge for no
        // benefit to the customer, who is looking at the newest SMS anyway.
        try {
            $this->service->verify($this->phone, $first);
            $this->fail('A superseded code was accepted.');
        } catch (ApiException $e) {
            $this->assertContains($e->errorCode, [ApiErrorCode::OtpInvalid, ApiErrorCode::OtpExpired]);
        }

        $this->assertNotNull($this->service->verify($this->phone, $second)->consumed_at);
    }

    public function test_a_code_for_one_number_does_not_verify_another_number(): void
    {
        $this->service->issue($this->phone);
        $code = $this->provider->lastCode();

        $other = PhoneNumber::fromE164('+919812345678');

        try {
            $this->service->verify($other, $code);
            $this->fail("One number's code verified a different number.");
        } catch (ApiException $e) {
            $this->assertSame(ApiErrorCode::OtpExpired, $e->errorCode);
        }
    }

    public function test_verifying_a_number_that_never_requested_a_code_fails(): void
    {
        try {
            $this->service->verify($this->phone, '123456');
            $this->fail('Verification succeeded with no challenge at all.');
        } catch (ApiException $e) {
            $this->assertSame(ApiErrorCode::OtpExpired, $e->errorCode);
        }
    }

    public function test_a_delivery_failure_leaves_no_live_challenge_behind(): void
    {
        $this->provider->shouldFail = true;

        try {
            $this->service->issue($this->phone);
            $this->fail('Expected the send failure to surface.');
        } catch (ApiException $e) {
            $this->assertSame(ApiErrorCode::OtpSendFailed, $e->errorCode);
        }

        // The customer received nothing, so nothing should be verifiable and no
        // attempts should be burnable against a code that does not exist.
        $challenge = OtpChallenge::query()->where('phone_e164', $this->phone->e164)->firstOrFail();
        $this->assertNotNull($challenge->invalidated_at);
        $this->assertSame('delivery_failed', $challenge->invalidated_reason);
    }

    public function test_the_resend_cooldown_is_enforced_from_the_server_clock(): void
    {
        config(['foodonthego.otp.resend_cooldown_seconds' => 30]);

        $this->assertSame(0, $this->service->secondsUntilResendAllowed($this->phone));

        $this->service->issue($this->phone);
        $this->assertGreaterThan(0, $this->service->secondsUntilResendAllowed($this->phone));

        $this->travel(31)->seconds();
        $this->assertSame(0, $this->service->secondsUntilResendAllowed($this->phone));
    }

    public function test_the_code_never_appears_in_the_challenge_record_returned_to_callers(): void
    {
        $challenge = $this->service->issue($this->phone);
        $code = $this->provider->lastCode();

        $this->assertStringNotContainsString($code, json_encode($challenge->toArray(), JSON_THROW_ON_ERROR));
    }

    private function wrongCodeFor(string $correct): string
    {
        $wrong = str_repeat('0', strlen($correct));

        return $wrong === $correct ? str_repeat('1', strlen($correct)) : $wrong;
    }
}
