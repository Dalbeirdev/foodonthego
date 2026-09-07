<?php

declare(strict_types=1);

namespace App\Providers;

use App\Services\Discovery\RestaurantDiscoveryEligibilityService;
use App\Services\Discovery\RestaurantDiscoveryService;
use App\Services\Pickup\ArrivalEstimateProvider;
use App\Services\Pickup\PickupOptionSelectionService;
use App\Services\Pickup\PickupOptionStore;
use App\Services\Pickup\PickupPlanningService;
use App\Services\Pickup\PickupWindowGenerator;
use App\Services\Pickup\PlannedRouteArrivalEstimateProvider;
use App\Services\Pickup\PreparationEstimateService;
use Illuminate\Support\ServiceProvider;

/**
 * Wires pickup time planning.
 *
 * The binding worth looking at is the first one. {@see ArrivalEstimateProvider}
 * is the ETA boundary, and it is a seam in the code rather than a paragraph in a
 * document precisely so that this line is the whole of the change when the live
 * ETA engine arrives: the planner consumes the interface and no arithmetic
 * anywhere moves.
 *
 * Today's implementation reads the journey the customer planned and assumes they
 * set off now. That is an approximation, it is the module's largest one, and it
 * is stated on the class rather than hidden behind the interface.
 */
final class PickupServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        $this->app->singleton(
            ArrivalEstimateProvider::class,
            fn (): ArrivalEstimateProvider => new PlannedRouteArrivalEstimateProvider(
                $this->app->make(RestaurantDiscoveryService::class),
            ),
        );

        $this->app->singleton(
            PreparationEstimateService::class,
            fn (): PreparationEstimateService => new PreparationEstimateService,
        );

        $this->app->singleton(
            PickupWindowGenerator::class,
            fn (): PickupWindowGenerator => new PickupWindowGenerator,
        );

        $this->app->singleton(
            PickupPlanningService::class,
            fn (): PickupPlanningService => new PickupPlanningService(
                arrival: $this->app->make(ArrivalEstimateProvider::class),
                preparation: $this->app->make(PreparationEstimateService::class),
                windows: $this->app->make(PickupWindowGenerator::class),
                eligibility: $this->app->make(RestaurantDiscoveryEligibilityService::class),
            ),
        );

        $this->app->singleton(
            PickupOptionStore::class,
            fn (): PickupOptionStore => new PickupOptionStore,
        );

        $this->app->singleton(
            PickupOptionSelectionService::class,
            fn (): PickupOptionSelectionService => new PickupOptionSelectionService(
                planning: $this->app->make(PickupPlanningService::class),
                store: $this->app->make(PickupOptionStore::class),
            ),
        );
    }
}
