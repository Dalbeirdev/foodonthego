<?php

declare(strict_types=1);

namespace App\Providers;

use App\Services\Routing\DevelopmentRouteProvider;
use App\Services\Routing\GoogleRouteProvider;
use App\Services\Routing\RouteCalculationService;
use App\Services\Routing\RouteProvider;
use App\Services\Routing\RouteValidator;
use App\Services\Routing\UnconfiguredRouteProvider;
use Illuminate\Contracts\Cache\Repository as Cache;
use Illuminate\Http\Client\Factory as HttpFactory;
use Illuminate\Support\ServiceProvider;

/**
 * Binds the routing provider named in configuration.
 *
 * The same seam as {@see PlacesServiceProvider}: implement {@see RouteProvider},
 * add a case, set `ROUTE_PROVIDER`. No service and no screen learns the
 * provider's name.
 *
 * `google` falls back to unconfigured when no key is set, rather than
 * constructing a provider that would fail every call with an authentication
 * error and bill nothing but log noise. `ProductionConfigGuard` turns that
 * fallback into a refusal to boot.
 */
final class RoutingServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        $this->app->singleton(RouteProvider::class, function (): RouteProvider {
            $configured = (string) config('foodonthego.routing.provider');
            $key = (string) config('foodonthego.routing.google_api_key');

            return match ($configured) {
                'google' => $key !== ''
                    ? new GoogleRouteProvider(
                        http: $this->app->make(HttpFactory::class),
                        apiKey: $key,
                        timeoutSeconds: (int) config('foodonthego.routing.timeout_seconds'),
                        maxAlternatives: (int) config('foodonthego.routing.max_alternatives'),
                        languageCode: (string) config('foodonthego.routing.language_code'),
                    )
                    : new UnconfiguredRouteProvider,

                // Constructing this in production throws — see the class.
                'development' => new DevelopmentRouteProvider(
                    $this->app->environment('production'),
                ),

                default => new UnconfiguredRouteProvider,
            };
        });

        $this->app->singleton(RouteValidator::class, fn (): RouteValidator => new RouteValidator(
            maxPolylineBytes: (int) config('foodonthego.routing.max_polyline_bytes'),
            endpointToleranceMetres: (int) config('foodonthego.routing.endpoint_tolerance_metres'),
        ));

        $this->app->singleton(RouteCalculationService::class, fn (): RouteCalculationService => new RouteCalculationService(
            provider: $this->app->make(RouteProvider::class),
            validator: $this->app->make(RouteValidator::class),
            // The cache store rather than the facade, so a test can swap it and
            // the lock is a real lock rather than a no-op.
            cache: $this->app->make(Cache::class),
        ));
    }
}
