<?php

declare(strict_types=1);

namespace App\Services\Otp\Providers;

use App\Services\Otp\OtpDeliveryFailed;
use App\Services\Otp\OtpDeliveryProvider;
use App\Services\Otp\OtpDeliveryReceipt;
use App\Support\Phone\PhoneNumber;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

/**
 * The development provider. Writes the code to the application log so a developer
 * can complete the flow without an SMS gateway.
 *
 * Three protections, because this class is the single most dangerous thing in the
 * module if it ever runs in production:
 *
 *  1. The constructor throws in a production environment.
 *  2. `deliversToRealDevices()` returns false, and the production configuration
 *     guard refuses to boot when the configured provider reports false.
 *  3. It writes to a dedicated `otp-development` log channel, so the code never
 *     lands in the structured application log that ships to an aggregator.
 *
 * A build that reaches production with this wired up does not start.
 */
final class LogOtpProvider implements OtpDeliveryProvider
{
    public function __construct(private readonly string $environment)
    {
        if ($environment === 'production') {
            throw new \LogicException(
                'LogOtpProvider must never be used in production: it writes one-time codes to a log '
                .'file instead of sending them. Configure a real OTP provider.',
            );
        }
    }

    public function send(PhoneNumber $phone, string $code): OtpDeliveryReceipt
    {
        // A deliberate escape hatch for testing the failure path end to end
        // without unplugging anything. Only ever true in a non-production build.
        if (config('foodonthego.otp.simulate_provider_failure') === true) {
            throw new OtpDeliveryFailed('log', 'Simulated provider failure (development only).');
        }

        Log::channel('otp-development')->info('otp.development_code', [
            'phone' => $phone->forLogging(),
            'phone_e164' => $phone->e164,
            'code' => $code,
            'notice' => 'DEVELOPMENT ONLY — this provider never runs in production.',
        ]);

        return new OtpDeliveryReceipt('log', 'dev-'.Str::uuid()->toString());
    }

    public function name(): string
    {
        return 'log';
    }

    public function deliversToRealDevices(): bool
    {
        return false;
    }
}
