<?php

declare(strict_types=1);

namespace App\Providers;

use App\Services\Otp\OtpDeliveryProvider;
use App\Services\Otp\Providers\LogOtpProvider;
use App\Services\Otp\Providers\TwilioOtpProvider;
use App\Services\Otp\Providers\UnconfiguredOtpProvider;
use Illuminate\Support\ServiceProvider;

/**
 * Binds the OTP delivery provider named in configuration.
 *
 * This is the single seam a real SMS vendor plugs into: implement
 * {@see OtpDeliveryProvider}, add a case here, set `OTP_PROVIDER`. No business
 * logic changes.
 */
final class AuthServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        $this->app->singleton(OtpDeliveryProvider::class, function (): OtpDeliveryProvider {
            return match ((string) config('foodonthego.otp.provider')) {
                // Constructing this in production throws — see the class.
                'log' => new LogOtpProvider($this->app->environment()),
                'twilio' => $this->twilio(),
                default => new UnconfiguredOtpProvider,
            };
        });
    }

    /**
     * Reads the Twilio settings once, at resolution.
     *
     * Casting to string here rather than inside the provider keeps the provider
     * itself free of `config()`, which is what lets a test construct it with
     * explicit values and no framework around it. Whether those values are
     * actually present is not this method's job: `ProductionConfigGuard` refuses
     * to boot on a half-configured provider, which catches it before a customer
     * meets it rather than at the first sign-in.
     */
    private function twilio(): TwilioOtpProvider
    {
        /** @var array<string, mixed> $settings */
        $settings = (array) config('foodonthego.otp.twilio', []);

        $value = static fn (string $key): ?string => is_string($settings[$key] ?? null) && $settings[$key] !== ''
            ? $settings[$key]
            : null;

        return new TwilioOtpProvider(
            accountSid: (string) $value('account_sid'),
            apiKeySid: (string) $value('api_key_sid'),
            apiKeySecret: (string) $value('api_key_secret'),
            messagingServiceSid: $value('messaging_service_sid'),
            from: $value('from'),
            messageTemplate: $value('message_template') ?? '{code} is your verification code.',
            timeoutSeconds: (int) ($settings['timeout_seconds'] ?? 10),
            baseUrl: $value('base_url') ?? 'https://api.twilio.com',
        );
    }
}
