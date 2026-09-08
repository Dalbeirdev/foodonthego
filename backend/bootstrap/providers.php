<?php

declare(strict_types=1);

use App\Providers\AppServiceProvider;
use App\Providers\AuthServiceProvider;
use App\Providers\CheckoutServiceProvider;
use App\Providers\DiscoveryServiceProvider;
use App\Providers\PickupServiceProvider;
use App\Providers\PlacesServiceProvider;
use App\Providers\RoutingServiceProvider;

return [
    AppServiceProvider::class,
    AuthServiceProvider::class,
    CheckoutServiceProvider::class,
    DiscoveryServiceProvider::class,
    PickupServiceProvider::class,
    PlacesServiceProvider::class,
    RoutingServiceProvider::class,
];
