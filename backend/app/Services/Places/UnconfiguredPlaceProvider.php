<?php

declare(strict_types=1);

namespace App\Services\Places;

use Illuminate\Support\Facades\Log;

/**
 * The default when no place provider is configured.
 *
 * It fails, loudly and every time. The alternative — a provider that returns an
 * empty list — would make an unconfigured deployment look like a working one
 * whose customers never find anywhere to go, and that failure would be
 * discovered by a customer rather than by a deploy.
 *
 * The same shape as Module 03's `UnconfiguredOtpProvider`, for the same reason:
 * a missing integration must be a broken deployment, not a quiet one.
 * `ProductionConfigGuard` refuses to boot on this provider outside development.
 */
final class UnconfiguredPlaceProvider implements PlaceProvider
{
    public function name(): string
    {
        return 'unconfigured';
    }

    public function search(string $query, ?string $sessionToken = null): array
    {
        $this->refuse('search');
    }

    public function details(string $placeId, ?string $sessionToken = null): PlaceDetails
    {
        $this->refuse('details');
    }

    public function reverseGeocode(float $latitude, float $longitude): ?PlaceDetails
    {
        $this->refuse('reverse-geocode');
    }

    private function refuse(string $operation): never
    {
        Log::error('places.provider_unconfigured', ['operation' => $operation]);

        throw new PlaceLookupException(
            'No place provider is configured. Set PLACES_PROVIDER and its credentials.',
        );
    }
}
