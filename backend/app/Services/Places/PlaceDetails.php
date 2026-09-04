<?php

declare(strict_types=1);

namespace App\Services\Places;

/**
 * A resolved place: the thing a trip endpoint can actually be built from.
 *
 * Coordinates are non-nullable here by construction. A provider that cannot say
 * where a place is has not resolved it, and returning a details object without a
 * position would push that judgement onto every caller.
 */
final readonly class PlaceDetails
{
    public function __construct(
        public string $placeId,
        public string $displayName,
        public string $formattedAddress,
        public float $latitude,
        public float $longitude,
        public ?string $city = null,
        public ?string $region = null,
        public ?string $countryCode = null,
        public ?string $postalCode = null,
    ) {}

    /** @return array<string, mixed> */
    public function toApiArray(): array
    {
        return [
            'place_id' => $this->placeId,
            'display_name' => $this->displayName,
            'formatted_address' => $this->formattedAddress,
            'latitude' => $this->latitude,
            'longitude' => $this->longitude,
            'city' => $this->city,
            'region' => $this->region,
            'country_code' => $this->countryCode,
            'postal_code' => $this->postalCode,
        ];
    }
}
