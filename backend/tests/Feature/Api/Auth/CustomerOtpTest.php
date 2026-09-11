<?php

declare(strict_types=1);

namespace Tests\Feature\Api\Auth;

use App\Enums\AccountStatus;
use App\Enums\Role;
use App\Models\OtpChallenge;
use App\Models\User;
use App\Services\Otp\OtpDeliveryProvider;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\Str;
use Illuminate\Testing\TestResponse;
use Tests\Support\RecordingOtpProvider;
use Tests\TestCase;

/**
 * The OTP endpoints as a client actually sees them.
 */
final class CustomerOtpTest extends TestCase
{
    use RefreshDatabase;

    private RecordingOtpProvider $provider;

    protected function setUp(): void
    {
        parent::setUp();

        $this->provider = new RecordingOtpProvider;
        $this->app->instance(OtpDeliveryProvider::class, $this->provider);
        RateLimiter::clear('otp:phone:'.hash('sha256', '+919876543210'));
    }

    private function requestOtp(string $phone = '9876543210', array $extra = []): TestResponse
    {
        return $this->postJson('/api/v1/auth/customer/otp/request', ['phone' => $phone] + $extra);
    }

    private function existingCustomer(string $e164 = '+919876543210'): User
    {
        return User::create([
            'uuid' => (string) Str::uuid(),
            'name' => 'Ravi Kumar',
            'first_name' => 'Ravi',
            'last_name' => 'Kumar',
            'phone_e164' => $e164,
            'phone_verified_at' => now(),
            'role' => Role::Customer->value,
            'status' => AccountStatus::Active->value,
        ]);
    }

    public function test_requesting_a_code_returns_only_masked_information(): void
    {
        $response = $this->requestOtp();

        $response->assertOk()
            ->assertJsonPath('data.phone_masked', '+91 ••••••3210')
            ->assertJsonStructure(['data' => [
                'phone_masked', 'expires_in_seconds', 'resend_available_in_seconds', 'otp_length',
            ], 'meta' => ['request_id']]);

        // The single most important assertion in the module: the code is not in
        // the response body under any key.
        $response->assertDontSee($this->provider->lastCode());
    }

    public function test_the_response_is_identical_whether_or_not_an_account_exists(): void
    {
        $newNumber = $this->requestOtp('9876543210')->json('data');

        $this->existingCustomer('+919812345678');
        RateLimiter::clear('otp:phone:'.hash('sha256', '+919812345678'));
        $known = $this->requestOtp('9812345678')->json('data');

        // Otherwise this endpoint is a free directory of who has an account.
        $this->assertSame(array_keys($newNumber), array_keys($known));
        $this->assertSame($newNumber['otp_length'], $known['otp_length']);
        $this->assertSame($newNumber['expires_in_seconds'], $known['expires_in_seconds']);
    }

    public function test_an_invalid_number_is_rejected_before_any_sms_is_attempted(): void
    {
        $this->requestOtp('12345')
            ->assertStatus(422)
            ->assertJsonPath('error.code', 'INVALID_PHONE');

        $this->assertSame(0, $this->provider->count());
        $this->assertDatabaseCount('otp_challenges', 0);
    }

    public function test_an_unsupported_country_is_rejected_with_its_own_code(): void
    {
        $this->requestOtp('+33612345678')
            ->assertStatus(422)
            ->assertJsonPath('error.code', 'INVALID_PHONE');
    }

    public function test_every_written_form_of_one_number_reaches_the_same_account(): void
    {
        $this->existingCustomer();

        foreach (['9876543210', '09876543210', '+91 98765 43210', '919876543210'] as $form) {
            RateLimiter::clear('otp:phone:'.hash('sha256', '+919876543210'));
            $this->travel(60)->seconds();

            $this->requestOtp($form)->assertOk()->assertJsonPath('data.phone_masked', '+91 ••••••3210');
        }

        $this->assertSame(
            ['+919876543210'],
            OtpChallenge::query()->distinct()->pluck('phone_e164')->all(),
        );
    }

    public function test_a_resend_inside_the_cooldown_is_refused(): void
    {
        config(['foodonthego.otp.resend_cooldown_seconds' => 30]);

        $this->requestOtp()->assertOk();

        $this->requestOtp()
            ->assertStatus(429)
            ->assertJsonPath('error.code', 'OTP_RESEND_TOO_SOON')
            ->assertJsonPath('error.details.retry_after_seconds', fn (int $s): bool => $s > 0 && $s <= 30);

        // Only one SMS was actually paid for.
        $this->assertSame(1, $this->provider->count());
    }

    public function test_a_resend_after_the_cooldown_succeeds_and_supersedes_the_first_code(): void
    {
        config(['foodonthego.otp.resend_cooldown_seconds' => 30]);

        $this->requestOtp()->assertOk();
        $first = $this->provider->lastCode();

        $this->travel(31)->seconds();
        $this->requestOtp()->assertOk();

        $this->postJson('/api/v1/auth/customer/otp/verify', ['phone' => '9876543210', 'otp' => $first])
            ->assertStatus(422);

        $this->postJson('/api/v1/auth/customer/otp/verify', ['phone' => '9876543210', 'otp' => $this->provider->lastCode()])
            ->assertOk();
    }

    public function test_too_many_requests_for_one_number_are_rate_limited(): void
    {
        config([
            'foodonthego.otp.max_requests_per_phone' => 3,
            'foodonthego.otp.resend_cooldown_seconds' => 0,
        ]);

        for ($i = 0; $i < 3; $i++) {
            $this->requestOtp()->assertOk();
        }

        $this->requestOtp()
            ->assertStatus(429)
            ->assertJsonPath('error.code', 'OTP_RATE_LIMITED')
            ->assertJsonStructure(['error' => ['details' => ['retry_after_seconds']]]);
    }

    public function test_the_rate_limit_response_does_not_disclose_the_threshold(): void
    {
        config(['foodonthego.otp.max_requests_per_phone' => 2, 'foodonthego.otp.resend_cooldown_seconds' => 0]);

        $this->requestOtp();
        $this->requestOtp();
        $body = $this->requestOtp()->json();

        // Publishing "5 per hour" hands an attacker the shape of the limit.
        $this->assertSame(['retry_after_seconds'], array_keys($body['error']['details']));
        $this->assertStringNotContainsString('2', $body['error']['message']);
    }

    public function test_a_provider_outage_is_reported_as_a_dependency_failure_not_a_success(): void
    {
        $this->provider->shouldFail = true;

        $this->requestOtp()
            ->assertStatus(503)
            ->assertJsonPath('error.code', 'OTP_SEND_FAILED');

        // A customer told "code sent" who received nothing is worse than an error.
        $this->assertNotNull(OtpChallenge::query()->firstOrFail()->invalidated_at);
    }

    public function test_a_correct_code_signs_an_existing_customer_in(): void
    {
        $customer = $this->existingCustomer();
        $this->requestOtp()->assertOk();

        $response = $this->postJson('/api/v1/auth/customer/otp/verify', [
            'phone' => '9876543210',
            'otp' => $this->provider->lastCode(),
        ]);

        $response->assertOk()
            ->assertJsonPath('data.registration_required', false)
            ->assertJsonPath('data.token_type', 'Bearer')
            ->assertJsonPath('data.user.id', $customer->uuid)
            ->assertJsonStructure(['data' => ['access_token', 'expires_at', 'user' => ['first_name', 'phone']]]);

        $this->assertNotNull($customer->fresh()->last_login_at);
    }

    public function test_a_correct_code_for_an_unknown_number_starts_registration_instead(): void
    {
        $this->requestOtp()->assertOk();

        $this->postJson('/api/v1/auth/customer/otp/verify', [
            'phone' => '9876543210',
            'otp' => $this->provider->lastCode(),
        ])
            ->assertOk()
            ->assertJsonPath('data.registration_required', true)
            ->assertJsonStructure(['data' => ['registration_token', 'registration_token_expires_in_seconds']])
            // No session until there is an account behind it.
            ->assertJsonMissingPath('data.access_token');

        $this->assertDatabaseCount('personal_access_tokens', 0);
    }

    public function test_a_wrong_code_is_rejected_with_a_message_that_does_not_help_the_guesser(): void
    {
        $this->requestOtp()->assertOk();

        $body = $this->postJson('/api/v1/auth/customer/otp/verify', ['phone' => '9876543210', 'otp' => '000000'])
            ->assertStatus(422)
            ->assertJsonPath('error.code', 'OTP_INVALID')
            ->json();

        // No "2 attempts remaining" — that is a countdown for an attacker as much
        // as for a customer, and it confirms the challenge exists.
        $this->assertArrayNotHasKey('details', array_filter($body['error']));
    }

    public function test_the_code_dies_after_the_configured_wrong_guesses(): void
    {
        config(['foodonthego.otp.max_attempts' => 3]);
        $this->requestOtp()->assertOk();
        $correct = $this->provider->lastCode();
        $wrong = $correct === '000000' ? '111111' : '000000';

        $this->postJson('/api/v1/auth/customer/otp/verify', ['phone' => '9876543210', 'otp' => $wrong])
            ->assertJsonPath('error.code', 'OTP_INVALID');
        $this->postJson('/api/v1/auth/customer/otp/verify', ['phone' => '9876543210', 'otp' => $wrong])
            ->assertJsonPath('error.code', 'OTP_INVALID');
        $this->postJson('/api/v1/auth/customer/otp/verify', ['phone' => '9876543210', 'otp' => $wrong])
            ->assertStatus(422)
            ->assertJsonPath('error.code', 'OTP_TOO_MANY_ATTEMPTS');

        // And the real code is now worthless.
        $this->postJson('/api/v1/auth/customer/otp/verify', ['phone' => '9876543210', 'otp' => $correct])
            ->assertJsonPath('error.code', 'OTP_EXPIRED');
    }

    public function test_an_expired_code_is_rejected(): void
    {
        config(['foodonthego.otp.ttl_seconds' => 300]);
        $this->requestOtp()->assertOk();
        $code = $this->provider->lastCode();

        $this->travel(301)->seconds();

        $this->postJson('/api/v1/auth/customer/otp/verify', ['phone' => '9876543210', 'otp' => $code])
            ->assertStatus(422)
            ->assertJsonPath('error.code', 'OTP_EXPIRED');
    }

    public function test_a_code_cannot_be_replayed(): void
    {
        $this->existingCustomer();
        $this->requestOtp()->assertOk();
        $code = $this->provider->lastCode();

        $this->postJson('/api/v1/auth/customer/otp/verify', ['phone' => '9876543210', 'otp' => $code])->assertOk();

        $this->postJson('/api/v1/auth/customer/otp/verify', ['phone' => '9876543210', 'otp' => $code])
            ->assertStatus(422)
            ->assertJsonPath('error.code', 'OTP_EXPIRED');
    }

    public function test_a_suspended_customer_cannot_sign_in_with_a_correct_code(): void
    {
        $this->existingCustomer()->forceFill(['status' => AccountStatus::Suspended->value])->save();
        $this->requestOtp()->assertOk();

        $this->postJson('/api/v1/auth/customer/otp/verify', [
            'phone' => '9876543210',
            'otp' => $this->provider->lastCode(),
        ])
            ->assertStatus(403)
            ->assertJsonPath('error.code', 'ACCOUNT_SUSPENDED');

        $this->assertDatabaseCount('personal_access_tokens', 0);
    }

    public function test_verification_requires_a_code_of_the_configured_shape(): void
    {
        $this->requestOtp()->assertOk();

        foreach (['', '12345', '1234567', 'abcdef', '12 34 56'] as $bad) {
            $this->postJson('/api/v1/auth/customer/otp/verify', ['phone' => '9876543210', 'otp' => $bad])
                ->assertStatus(422)
                ->assertJsonPath('error.code', 'VALIDATION_FAILED');
        }

        // None of those burned an attempt against the real challenge.
        $this->assertSame(0, OtpChallenge::query()->firstOrFail()->attempts);
    }

    public function test_the_endpoints_answer_in_the_standard_envelope(): void
    {
        $this->requestOtp()->assertJsonStructure(['data', 'meta' => ['request_id']]);

        $this->postJson('/api/v1/auth/customer/otp/verify', ['phone' => '9876543210', 'otp' => '000000'])
            ->assertJsonStructure(['error' => ['code', 'message', 'request_id']]);
    }
}
