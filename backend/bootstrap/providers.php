<?php

declare(strict_types=1);

use App\Providers\AppServiceProvider;
use App\Providers\AuthServiceProvider;
use App\Providers\PlacesServiceProvider;

return [
    AppServiceProvider::class,
    AuthServiceProvider::class,
    PlacesServiceProvider::class,
];
