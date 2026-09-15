<?php

declare(strict_types=1);

namespace App\Support\Trip;

use App\Enums\LocationSourceType;
use App\Models\CustomerAddress;

/**
 * One end of a trip, in the form the `trips` table stores it.
 *
 * All three ways of choosing a place — the device's location, a saved address, a
 * place-search result — end up here, which is the point: the rest of the module
 * deals with a selection, not with three shapes of request.
 *
 * Two properties are load-bearing:
 *
 *  - **Coordinates are required.** A selection without a usable pair is not a
 *    place this product can plan a journey through, and Module 06 would silently
 *    receive one endpoint it cannot route to. Module 04 allows a saved address
 *    with no coordinates; a trip does not, and the customer is asked to resolve
 *    it rather than having something plausible filled in for them.
 *  - **It is a snapshot.** Building one from a saved address copies the values
 *    out rather than holding the row, so a later edit to that address cannot
 *    retroactively change a trip already created from it. The address id is kept
 *    alongside as provenance only.
 */
final readonly class LocationSelection
{
    public function __construct(
        public LocationSourceType $sourceType,
        public string $displayName,
        public string $formattedAddress,
        public string $latitude,
        public string $longitude,
        public ?string $placeId = null,
        public ?int $savedAddressId = null,
        public ?string $city = null,
        public ?string $region = null,
        public ?string $countryCode = null,
        public ?string $postalCode = null,
    ) {}

    /**
     * Snapshots a saved address that already has coordinates.
     *
     * The caller must have resolved the address through the ownership-scoped
     * service and must have established that it is usable — this class cannot
     * check ownership and does not pretend to.
     */
    public static function fromSavedAddress(CustomerAddress $address): self
    {
        return new self(
            sourceType: LocationSourceType::SavedAddress,
            displayName: $address->label,
            formattedAddress: $address->formatted_address,
            latitude: (string) $address->latitude,
            longitude: (string) $address->longitude,
            placeId: $address->place_id,
            savedAddressId: $address->getKey(),
            city: $address->city,
            region: $address->state,
            countryCode: $address->country_code,
            postalCode: $address->postal_code,
        );
    }

    /**
     * Builds a selection from validated request input.
     *
     * @param  array<string, mixed>  $input
     */
    public static function fromInput(array $input, LocationSourceType $sourceType): self
    {
        return new self(
            sourceType: $sourceType,
            displayName: trim((string) ($input['display_name'] ?? '')),
            formattedAddress: trim((string) ($input['formatted_address'] ?? '')),
            // Kept as the strings they arrived as. A coordinate that round-trips
            // through a float loses its last place, and the last place of a
            // coordinate is metres.
            latitude: (string) $input['latitude'],
            longitude: (string) $input['longitude'],
            placeId: self::nullIfBlank($input['place_id'] ?? null),
            city: self::nullIfBlank($input['city'] ?? null),
            region: self::nullIfBlank($input['region'] ?? null),
            countryCode: self::upperOrNull($input['country_code'] ?? null),
            postalCode: self::nullIfBlank($input['postal_code'] ?? null),
        );
    }

    /**
     * The column values for one end of the trip.
     *
     * @return array<string, mixed>
     */
    public function toColumns(string $prefix): array
    {
        return [
            "{$prefix}_source_type" => $this->sourceType,
            "{$prefix}_saved_address_id" => $this->savedAddressId,
            "{$prefix}_place_id" => $this->placeId,
            "{$prefix}_name" => $this->displayName,
            "{$prefix}_formatted_address" => $this->formattedAddress,
            "{$prefix}_latitude" => $this->latitude,
            "{$prefix}_longitude" => $this->longitude,
            "{$prefix}_city" => $this->city,
            "{$prefix}_region" => $this->region,
            "{$prefix}_country_code" => $this->countryCode,
            "{$prefix}_postal_code" => $this->postalCode,
        ];
    }

    public function latitudeAsFloat(): float
    {
        return (float) $this->latitude;
    }

    public function longitudeAsFloat(): float
    {
        return (float) $this->longitude;
    }

    /**
     * Whether two selections name the same physical place.
     *
     * Three tests, in order of confidence, because display text is the weakest
     * evidence there is — "Jaipur Airport" and "Jaipur International Airport" are
     * one place, and two different flats can share a formatted line.
     *
     *  1. The same provider place id.
     *  2. The same saved address.
     *  3. Within {@see $thresholdMetres} of each other.
     *
     * The distance test is what catches the real case: the same airport reached
     * once from a saved address and once from a search. The threshold is
     * deliberately tight — see the note on `trips.same_location_threshold_metres`
     * in config — because a generous one would refuse a legitimate short journey
     * between two nearby addresses.
     */
    public function isSamePlaceAs(self $other, float $thresholdMetres): bool
    {
        if ($this->placeId !== null && $this->placeId === $other->placeId) {
            return true;
        }

        if ($this->savedAddressId !== null && $this->savedAddressId === $other->savedAddressId) {
            return true;
        }

        return $this->distanceInMetresTo($other) <= $thresholdMetres;
    }

    /**
     * Great-circle distance, in metres.
     *
     * The haversine formula on a spherical earth. Accurate to about 0.3% — far
     * better than this is needed to decide "is this the same building", and this
     * is emphatically *not* a routing distance: Module 06 computes those from a
     * real road network, and nothing here should be mistaken for one.
     */
    public function distanceInMetresTo(self $other): float
    {
        $earthRadius = 6_371_000.0;

        $lat1 = deg2rad($this->latitudeAsFloat());
        $lat2 = deg2rad($other->latitudeAsFloat());
        $deltaLat = $lat2 - $lat1;
        $deltaLon = deg2rad($other->longitudeAsFloat() - $this->longitudeAsFloat());

        $a = sin($deltaLat / 2) ** 2
            + cos($lat1) * cos($lat2) * sin($deltaLon / 2) ** 2;

        return $earthRadius * 2 * atan2(sqrt($a), sqrt(1 - $a));
    }

    private static function nullIfBlank(mixed $value): ?string
    {
        if (! is_string($value)) {
            return null;
        }

        $trimmed = trim($value);

        return $trimmed === '' ? null : $trimmed;
    }

    private static function upperOrNull(mixed $value): ?string
    {
        $trimmed = self::nullIfBlank($value);

        return $trimmed === null ? null : strtoupper($trimmed);
    }
}
