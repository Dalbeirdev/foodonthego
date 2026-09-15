<?php

declare(strict_types=1);

namespace App\Providers;

use App\Services\Orders\PickupCredentialService;
use Illuminate\Support\ServiceProvider;

/**
 * Module 16's wiring.
 *
 * The pepper is resolved here rather than read inside the service, so that the
 * secret has exactly one route into the application and a test can substitute a
 * known one without reaching for config in the middle of an assertion.
 */
final class OrderServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        $this->app->singleton(
            PickupCredentialService::class,
            static fn (): PickupCredentialService => new PickupCredentialService(
                (string) config('foodonthego.orders.pickup_pepper'),
            ),
        );
    }
}
