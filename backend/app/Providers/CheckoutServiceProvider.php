<?php

declare(strict_types=1);

namespace App\Providers;

use App\Services\Cart\CartTotalsService;
use App\Services\Checkout\CheckoutPreparationService;
use App\Services\Checkout\CommercialCalculationService;
use App\Services\Pickup\PreCheckoutValidationService;
use Illuminate\Support\ServiceProvider;

/**
 * Wires checkout.
 *
 * The binding worth reading is the commercial one: it takes Module 12's
 * {@see CartTotalsService} rather than constructing its own arithmetic. There is
 * one place in this project that turns a cart into a total, and this wiring is
 * what keeps that true — a second implementation would be a second answer.
 */
final class CheckoutServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        $this->app->singleton(
            CommercialCalculationService::class,
            fn (): CommercialCalculationService => new CommercialCalculationService(
                $this->app->make(CartTotalsService::class),
            ),
        );

        $this->app->singleton(
            CheckoutPreparationService::class,
            fn (): CheckoutPreparationService => new CheckoutPreparationService(
                preCheckout: $this->app->make(PreCheckoutValidationService::class),
                commercial: $this->app->make(CommercialCalculationService::class),
            ),
        );
    }
}
