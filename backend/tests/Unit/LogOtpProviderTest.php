<?php

declare(strict_types=1);

namespace Tests\Unit;

use App\Services\Otp\OtpDeliveryFailed;
use App\Services\Otp\Providers\LogOtpProvider;
use App\Services\Otp\Providers\UnconfiguredOtpProvider;
use App\Support\Phone\PhoneNumber;
use LogicException;
use Tests\TestCase;

/**
 * The development provider is the most dangerous class in the module, because it
 * writes codes in plaintext. These tests pin the protections that keep it out of
 * production.
 */
final class LogOtpProviderTest extends TestCase
{
    public function test_it_refuses_to_be_constructed_in_production(): void
    {
        $this->expectException(LogicException::class);
        $this->expectExceptionMessageMatches('/never be used in production/');

        new LogOtpProvider('production');
    }

    public function test_it_constructs_in_local_and_testing(): void
    {
        foreach (['local', 'testing', 'development'] as $environment) {
            $this->assertSame('log', (new LogOtpProvider($environment))->name());
        }
    }

    public function test_it_declares_that_it_cannot_reach_a_real_handset(): void
    {
        // This is what ProductionConfigGuard keys off, so it is the second lock
        // on the same door.
        $this->assertFalse((new LogOtpProvider('local'))->deliversToRealDevices());
    }

    public function test_the_code_goes_to_a_dedicated_channel_and_not_the_application_log(): void
    {
        $devLog = storage_path('logs/otp-development.log');
        $appLog = storage_path('logs/testing-app-'.getmypid().'.log');

        @unlink($appLog);
        $before = is_file($devLog) ? (string) file_get_contents($devLog) : '';

        config([
            'logging.default' => 'testing-app',
            'logging.channels.testing-app' => ['driver' => 'single', 'path' => $appLog, 'level' => 'debug'],
        ]);

        (new LogOtpProvider('local'))->send(PhoneNumber::fromE164('+919876543210'), '424242');

        $after = is_file($devLog) ? (string) file_get_contents($devLog) : '';

        // In the development log, where a developer expects it.
        $this->assertStringContainsString('424242', substr($after, strlen($before)));

        // Not in the application log, which is what ships to an aggregator.
        $this->assertStringNotContainsString('424242', is_file($appLog) ? (string) file_get_contents($appLog) : '');

        @unlink($appLog);
    }

    public function test_the_simulated_failure_switch_produces_a_delivery_failure(): void
    {
        config(['foodonthego.otp.simulate_provider_failure' => true]);

        $this->expectException(OtpDeliveryFailed::class);

        (new LogOtpProvider('local'))->send(PhoneNumber::fromE164('+919876543210'), '424242');
    }

    public function test_the_default_production_provider_sends_nothing_at_all(): void
    {
        // What a deployment gets when OTP_PROVIDER is unset: a provider that
        // fails loudly rather than one that quietly pretends to work.
        $provider = new UnconfiguredOtpProvider;

        $this->assertFalse($provider->deliversToRealDevices());

        $this->expectException(OtpDeliveryFailed::class);
        $provider->send(PhoneNumber::fromE164('+919876543210'), '424242');
    }
}
