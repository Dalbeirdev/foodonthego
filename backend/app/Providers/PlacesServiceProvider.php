<?php

declare(strict_types=1);

namespace App\Providers;

use App\Services\Places\DevelopmentGazetteerProvider;
use App\Services\Places\GooglePlacesProvider;
use App\Services\Places\PlaceProvider;
use App\Services\Places\UnconfiguredPlaceProvider;
use Illuminate\Http\Client\Factory as HttpFactory;
use Illuminate\Support\ServiceProvider;

/**
 * Binds the place provider named in configuration.
 *
 * The same seam as {@see AuthServiceProvider}'s OTP binding: implement
 * {@see PlaceProvider}, add a case, set `PLACES_PROVIDER`. No business logic
 * changes, and no screen learns the provider's name.
 *
 * `google` falls back to unconfigured when no key is set, rather than
 * constructing a provider that would fail on every call with an authentication
 * error. `ProductionConfigGuard` turns that fallback into a refusal to boot.
 */
final class PlacesServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        $this->app->singleton(PlaceProvider::class, function (): PlaceProvider {
            $configured = (string) config('foodonthego.places.provider');
            $key = (string) config('foodonthego.places.google_api_key');

            return match ($configured) {
                'google' => $key !== ''
                    ? new GooglePlacesProvider(
                        http: $this->app->make(HttpFactory::class),
                        apiKey: $key,
                        regions: (array) config('foodonthego.places.regions'),
                        timeoutSeconds: (int) config('foodonthego.places.timeout_seconds'),
                        maxResults: (int) config('foodonthego.places.max_results'),
                    )
                    : new UnconfiguredPlaceProvider,

                // Constructing this in production throws — see the class.
                'development' => new DevelopmentGazetteerProvider(
                    $this->app->environment('production'),
                ),

                default => new UnconfiguredPlaceProvider,
            };
        });
    }
}
