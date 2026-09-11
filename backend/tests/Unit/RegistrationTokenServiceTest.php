<?php

declare(strict_types=1);

namespace Tests\Unit;

use App\Enums\ApiErrorCode;
use App\Exceptions\ApiException;
use App\Models\OtpChallenge;
use App\Services\Auth\RegistrationTokenService;
use App\Services\Otp\OtpChallengeService;
use App\Services\Otp\OtpDeliveryProvider;
use App\Support\Phone\PhoneNumber;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Crypt;
use Illuminate\Support\Str;
use Tests\Support\RecordingOtpProvider;
use Tests\TestCase;

/**
 * The attack this class exists to stop, stated plainly: verify a number you
 * control, then register somebody else's number and own their account.
 */
final class RegistrationTokenServiceTest extends TestCase
{
    use RefreshDatabase;

    private RecordingOtpProvider $provider;

    private OtpChallengeService $otp;

    private RegistrationTokenService $tokens;

    protected function setUp(): void
    {
        parent::setUp();

        $this->provider = new RecordingOtpProvider;
        $this->app->instance(OtpDeliveryProvider::class, $this->provider);
        $this->otp = $this->app->make(OtpChallengeService::class);
        $this->tokens = $this->app->make(RegistrationTokenService::class);
    }

    /** Runs a real verification and returns the token it produces. */
    private function verifiedTokenFor(string $e164): string
    {
        $phone = PhoneNumber::fromE164($e164);
        $this->otp->issue($phone);
        $challenge = $this->otp->verify($phone, $this->provider->lastCode());

        return $this->tokens->issue($challenge, $phone);
    }

    public function test_a_token_carries_the_verified_number_back_out(): void
    {
        $token = $this->verifiedTokenFor('+919876543210');

        $this->assertSame('+919876543210', $this->tokens->verifiedPhoneFor($token)->e164);
    }

    public function test_the_number_is_not_readable_from_the_token(): void
    {
        $token = $this->verifiedTokenFor('+919876543210');

        // A token is handed to a client and may end up in a log, a proxy or a
        // screenshot. It must not be a phone number in transit.
        $this->assertStringNotContainsString('9876543210', $token);
        $this->assertStringNotContainsString('919876543210', base64_decode($token, true) ?: '');
    }

    public function test_a_forged_token_is_rejected(): void
    {
        // Encrypted with a different key: the MAC will not verify.
        $forged = Crypt::encryptString(json_encode([
            'challenge_uuid' => (string) Str::uuid(),
            'phone_e164' => '+919812345678',
            'issued_at' => now()->timestamp,
        ], JSON_THROW_ON_ERROR));

        // Even correctly encrypted by us, it names a challenge that never existed.
        $this->assertRejects($forged, ApiErrorCode::RegistrationTokenInvalid);
    }

    public function test_garbage_is_rejected_rather_than_crashing(): void
    {
        foreach (['', 'not-a-token', base64_encode('{"phone_e164":"+919876543210"}')] as $garbage) {
            $this->assertRejects($garbage, ApiErrorCode::RegistrationTokenInvalid);
        }
    }

    public function test_a_tampered_token_is_rejected(): void
    {
        $token = $this->verifiedTokenFor('+919876543210');

        // Flip a character in the middle of the ciphertext.
        $tampered = substr($token, 0, 40).(($token[40] === 'a') ? 'b' : 'a').substr($token, 41);

        $this->assertRejects($tampered, ApiErrorCode::RegistrationTokenInvalid);
    }

    public function test_a_token_whose_challenge_was_never_verified_is_rejected(): void
    {
        $phone = PhoneNumber::fromE164('+919876543210');
        $challenge = $this->otp->issue($phone);

        // Issued without ever calling verify() — the shape a caller would forge if
        // they could reach the token-minting code directly.
        $token = $this->tokens->issue($challenge, $phone);

        $this->assertRejects($token, ApiErrorCode::RegistrationTokenInvalid);
    }

    public function test_a_token_naming_a_different_number_than_its_challenge_is_rejected(): void
    {
        $attacker = PhoneNumber::fromE164('+919812345678');
        $this->otp->issue($attacker);
        $challenge = $this->otp->verify($attacker, $this->provider->lastCode());

        // The attacker verified their own number and now mints a token claiming
        // the victim's. The mismatch against the challenge row is what stops it.
        $token = $this->tokens->issue($challenge, PhoneNumber::fromE164('+919876543210'));

        $this->assertRejects($token, ApiErrorCode::RegistrationTokenInvalid);
    }

    public function test_a_token_expires(): void
    {
        config(['foodonthego.otp.registration_token_ttl_seconds' => 900]);
        $token = $this->verifiedTokenFor('+919876543210');

        $this->travel(901)->seconds();

        $this->assertRejects($token, ApiErrorCode::RegistrationTokenExpired);
    }

    public function test_a_token_whose_challenge_row_is_gone_is_rejected(): void
    {
        $token = $this->verifiedTokenFor('+919876543210');

        // Pruning removes consumed challenges after their retention window.
        OtpChallenge::query()->delete();

        $this->assertRejects($token, ApiErrorCode::RegistrationTokenInvalid);
    }

    private function assertRejects(string $token, ApiErrorCode $expected): void
    {
        try {
            $this->tokens->verifiedPhoneFor($token);
            $this->fail('Expected the token to be rejected.');
        } catch (ApiException $e) {
            $this->assertSame($expected, $e->errorCode);
        }
    }
}
