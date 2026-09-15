<?php

declare(strict_types=1);

namespace App\Providers;

use App\Services\Payments\PaymentGateway;
use App\Services\Payments\RazorpayGateway;
use App\Services\Payments\UnconfiguredPaymentGateway;
use Illuminate\Support\ServiceProvider;

/**
 * Which payment gateway the application talks to.
 *
 * The default is the one that refuses. A gateway is bound only when both halves
 * of the credential are present — an id without a secret is a half-configured
 * deployment, and treating it as configured produces authentication failures at
 * the moment a customer tries to pay rather than at boot.
 *
 * As this project stands there are no credentials, so this binds
 * {@see UnconfiguredPaymentGateway} everywhere outside tests. That is a stated
 * position, not an oversight: no Razorpay key was invented to make a screen look
 * finished.
 */
final class PaymentServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        $this->app->singleton(PaymentGateway::class, function (): PaymentGateway {
            $keyId = (string) config('services.razorpay.key_id');
            $keySecret = (string) config('services.razorpay.key_secret');

            if ($keyId === '' || $keySecret === '') {
                return new UnconfiguredPaymentGateway;
            }

            return new RazorpayGateway(
                keyId: $keyId,
                keySecret: $keySecret,
                timeoutSeconds: (int) config('services.razorpay.timeout_seconds', 15),
            );
        });
    }
}
