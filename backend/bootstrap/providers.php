<?php

declare(strict_types=1);

use App\Providers\AppServiceProvider;
use App\Providers\AuthServiceProvider;
use App\Providers\PlacesServiceProvider;
use App\Providers\RoutingServiceProvider;

return [
    AppServiceProvider::class,
    AuthServiceProvider::class,
    PlacesServiceProvider::class,
    RoutingServiceProvider::class,
];
