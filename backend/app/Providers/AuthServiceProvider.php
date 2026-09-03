<?php

declare(strict_types=1);

namespace App\Providers;

use App\Services\Otp\OtpDeliveryProvider;
use App\Services\Otp\Providers\LogOtpProvider;
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
                default => new UnconfiguredOtpProvider,
            };
        });
    }
}
