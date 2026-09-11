<?php

declare(strict_types=1);

namespace App\Providers;

use App\Services\Discovery\DiscoveryRankingService;
use App\Services\Discovery\DiscoveryRefiner;
use App\Services\Discovery\RestaurantAvailabilityService;
use App\Services\Discovery\RestaurantDetourService;
use App\Services\Discovery\RestaurantDiscoveryEligibilityService;
use App\Services\Discovery\RestaurantDiscoveryService;
use App\Services\Discovery\SearchMatcher;
use App\Services\Routing\RouteCalculationService;
use App\Services\Routing\RouteProvider;
use Illuminate\Support\ServiceProvider;

/**
 * Wires restaurant route discovery.
 *
 * Every threshold is read here and injected, rather than read from `config()`
 * inside the services that use it. That is what makes the ranking service
 * testable at a boundary somebody chooses — a test can build one with a
 * five-minute detour limit without touching global configuration — and it keeps
 * the answer to "what does this service depend on" in its constructor.
 *
 * The detour service takes the **same** {@see RouteProvider} Module 06 uses.
 * Deliberately: a detour is only meaningful as a difference against the selected
 * route, and comparing one provider's route to another provider's would produce
 * a number that is mostly the disagreement between them.
 */
final class DiscoveryServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        $this->app->singleton(
            RestaurantDiscoveryEligibilityService::class,
            fn (): RestaurantDiscoveryEligibilityService => new RestaurantDiscoveryEligibilityService,
        );

        $this->app->singleton(
            RestaurantAvailabilityService::class,
            fn (): RestaurantAvailabilityService => new RestaurantAvailabilityService,
        );

        $this->app->singleton(
            RestaurantDetourService::class,
            fn (): RestaurantDetourService => new RestaurantDetourService(
                provider: $this->app->make(RouteProvider::class),
                maxEvaluations: (int) config('foodonthego.discovery.max_detour_evaluations'),
            ),
        );

        $this->app->singleton(
            DiscoveryRankingService::class,
            fn (): DiscoveryRankingService => new DiscoveryRankingService(
                maxDetourDurationSeconds: (int) config(
                    'foodonthego.discovery.max_detour_duration_seconds',
                ),
                corridorMetres: (int) config('foodonthego.discovery.corridor_metres'),
                // Read here and injected, so the weights are a property of the
                // deployment rather than something a scoring method reaches out
                // to global state for.
                weights: (array) config('foodonthego.discovery.weights'),
            ),
        );

        $this->app->singleton(SearchMatcher::class, fn (): SearchMatcher => new SearchMatcher);

        // Module 08's refiner takes the *result* of Module 07's discovery, never
        // the database. That is what makes "a search cannot resurrect a
        // suspended restaurant" a property of the wiring rather than a check
        // somebody has to remember.
        $this->app->singleton(
            DiscoveryRefiner::class,
            fn (): DiscoveryRefiner => new DiscoveryRefiner(
                matcher: $this->app->make(SearchMatcher::class),
                ranking: $this->app->make(DiscoveryRankingService::class),
            ),
        );

        $this->app->singleton(
            RestaurantDiscoveryService::class,
            fn (): RestaurantDiscoveryService => new RestaurantDiscoveryService(
                routes: $this->app->make(RouteCalculationService::class),
                eligibility: $this->app->make(RestaurantDiscoveryEligibilityService::class),
                availability: $this->app->make(RestaurantAvailabilityService::class),
                detours: $this->app->make(RestaurantDetourService::class),
                ranking: $this->app->make(DiscoveryRankingService::class),
            ),
        );
    }
}
