<?php

declare(strict_types=1);

namespace Tests\Feature\Api\Auth;

use App\Logging\StructuredLogger;
use App\Services\Otp\OtpDeliveryProvider;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Log;
use Tests\Support\RecordingOtpProvider;
use Tests\TestCase;

/**
 * Reads what the application actually wrote to disk during a complete sign-up.
 *
 * Asserting on the redaction helper in isolation is not enough: the failure mode
 * is a call site that passes an unredacted value under a key nobody thought to
 * add to the list. This runs the real flow and greps the real file.
 */
final class AuthLoggingTest extends TestCase
{
    use RefreshDatabase;

    private RecordingOtpProvider $provider;

    private string $logFile;

    protected function setUp(): void
    {
        parent::setUp();

        $this->provider = new RecordingOtpProvider;
        $this->app->instance(OtpDeliveryProvider::class, $this->provider);

        $this->logFile = storage_path('logs/testing-auth-'.getmypid().'.log');
        @unlink($this->logFile);

        config([
            'logging.default' => 'testing-auth',
            'logging.channels.testing-auth' => [
                'driver' => 'single',
                'path' => $this->logFile,
                'level' => 'debug',
                'tap' => [StructuredLogger::class],
            ],
        ]);

        Log::forgetChannel('testing-auth');
    }

    protected function tearDown(): void
    {
        @unlink($this->logFile);

        parent::tearDown();
    }

    private function logContents(): string
    {
        return is_file($this->logFile) ? (string) file_get_contents($this->logFile) : '';
    }

    private function completeSignUp(): array
    {
        $this->postJson('/api/v1/auth/customer/otp/request', ['phone' => '9876543210'])->assertOk();
        $code = $this->provider->lastCode();

        $registrationToken = $this->postJson('/api/v1/auth/customer/otp/verify', [
            'phone' => '9876543210',
            'otp' => $code,
        ])->assertOk()->json('data.registration_token');

        $accessToken = $this->postJson('/api/v1/auth/customer/register', [
            'registration_token' => $registrationToken,
            'first_name' => 'Ravi',
        ])->assertCreated()->json('data.access_token');

        return compact('code', 'registrationToken', 'accessToken');
    }

    public function test_a_complete_sign_up_writes_no_otp_no_token_and_no_full_phone_number(): void
    {
        ['code' => $code, 'registrationToken' => $registrationToken, 'accessToken' => $accessToken] = $this->completeSignUp();

        $log = $this->logContents();

        $this->assertNotSame('', $log, 'Nothing was logged, so this test would pass vacuously.');

        $this->assertStringNotContainsString($code, $log, 'The OTP reached the log.');
        $this->assertStringNotContainsString($registrationToken, $log, 'The registration token reached the log.');
        $this->assertStringNotContainsString($accessToken, $log, 'The access token reached the log.');
        $this->assertStringNotContainsString('9876543210', $log, 'A full phone number reached the log.');
        $this->assertStringNotContainsString('+919876543210', $log, 'A full phone number reached the log.');
    }

    public function test_failed_verification_attempts_are_logged_without_the_submitted_code(): void
    {
        $this->postJson('/api/v1/auth/customer/otp/request', ['phone' => '9876543210'])->assertOk();

        $this->postJson('/api/v1/auth/customer/otp/verify', ['phone' => '9876543210', 'otp' => '135791'])
            ->assertStatus(422);

        $log = $this->logContents();

        // The event must be recorded — an abuse investigation needs to see the
        // attempts — but the guessed value is not part of that record.
        $this->assertStringContainsString('auth.otp.verify_failed', $log);
        $this->assertStringNotContainsString('135791', $log);
    }

    public function test_the_masked_number_is_what_appears_in_the_log(): void
    {
        $this->postJson('/api/v1/auth/customer/otp/request', ['phone' => '9876543210'])->assertOk();

        // Support still needs to correlate a log line with a customer, so the
        // last four digits are kept. The rest is not.
        $this->assertStringContainsString('3210', $this->logContents());
        $this->assertStringNotContainsString('98765', $this->logContents());
    }

    public function test_a_delivery_failure_is_logged_without_the_code_it_failed_to_send(): void
    {
        $this->provider->shouldFail = true;

        $this->postJson('/api/v1/auth/customer/otp/request', ['phone' => '9876543210'])->assertStatus(503);

        $log = $this->logContents();

        $this->assertStringContainsString('auth.otp.delivery_failed', $log);
        $this->assertMatchesRegularExpression('/"phone":"\+91 [^0-9]*3210"/', $log);
    }

    public function test_every_line_is_parseable_json_carrying_the_correlation_id(): void
    {
        $this->completeSignUp();

        foreach (array_filter(explode("\n", $this->logContents())) as $line) {
            $decoded = json_decode($line, true);

            $this->assertIsArray($decoded, "Not JSON: {$line}");
            $this->assertArrayHasKey('request_id', $decoded);
            $this->assertArrayHasKey('context', $decoded);
        }
    }
}
