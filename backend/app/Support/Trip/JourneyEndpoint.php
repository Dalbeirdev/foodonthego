<?php

declare(strict_types=1);

namespace App\Support\Trip;

use App\Models\CustomerAddress;

/**
 * One end of a journey, in the form the `trips` table stores it.
 *
 * Both ways of naming a place — picking a saved address, or typing one — end up
 * here, which is the point: the rest of the module deals with an endpoint, not
 * with two shapes of request. Building it from a saved address copies the values
 * out rather than holding the row, so a later edit to that address cannot
 * retroactively change a journey somebody has already planned.
 */
final readonly class JourneyEndpoint
{
    public function __construct(
        public string $label,
        public string $formattedAddress,
        public string $city,
        public string $countryCode,
        public ?string $latitude = null,
        public ?string $longitude = null,
        public ?string $placeId = null,
        public ?int $addressId = null,
    ) {}

    /**
     * Snapshots a saved address.
     *
     * The caller must have resolved the address through the ownership-scoped
     * service — this class cannot check ownership and does not pretend to.
     */
    public static function fromSavedAddress(CustomerAddress $address): self
    {
        return new self(
            label: $address->label,
            formattedAddress: $address->formatted_address,
            city: $address->city,
            countryCode: $address->country_code,
            latitude: $address->latitude,
            longitude: $address->longitude,
            placeId: $address->place_id,
            addressId: $address->getKey(),
        );
    }

    /**
     * Builds an endpoint from typed input that has already been validated.
     *
     * @param  array<string, mixed>  $input
     */
    public static function fromInput(array $input): self
    {
        $city = trim((string) ($input['city'] ?? ''));
        $label = trim((string) ($input['label'] ?? ''));

        return new self(
            // A traveller who typed only a city has named the place: "Jaipur" is
            // a better label than an empty one, and better than repeating the
            // whole formatted line in a list row.
            label: $label !== '' ? $label : $city,
            formattedAddress: self::composeAddress($input, $city),
            city: $city,
            countryCode: strtoupper(trim((string) ($input['country_code'] ?? ''))),
            latitude: self::coordinate($input['latitude'] ?? null),
            longitude: self::coordinate($input['longitude'] ?? null),
            placeId: self::nullIfBlank($input['place_id'] ?? null),
        );
    }

    /**
     * The column values for one end of the journey.
     *
     * @return array<string, mixed>
     */
    public function toColumns(string $prefix): array
    {
        return [
            "{$prefix}_address_id" => $this->addressId,
            "{$prefix}_label" => $this->label,
            "{$prefix}_formatted_address" => $this->formattedAddress,
            "{$prefix}_city" => $this->city,
            "{$prefix}_country_code" => $this->countryCode,
            "{$prefix}_latitude" => $this->latitude,
            "{$prefix}_longitude" => $this->longitude,
            "{$prefix}_place_id" => $this->placeId,
        ];
    }

    /**
     * Whether two endpoints name the same place.
     *
     * Compared on the formatted line and the city, case- and space-insensitively,
     * because "setting off from Connaught Place and arriving at connaught place"
     * is not a journey — it is a typo, and it would later produce a corridor of
     * zero length for the restaurant search to work with.
     *
     * Two *different* saved addresses that happen to format the same way are
     * also caught, which is the desired answer: the customer means one place.
     */
    public function isSamePlaceAs(self $other): bool
    {
        return self::normalize($this->formattedAddress) === self::normalize($other->formattedAddress)
            && self::normalize($this->city) === self::normalize($other->city);
    }

    /**
     * The one-line form, from the parts the traveller gave.
     *
     * Deliberately not the same composer Module 04 uses for a saved address: a
     * journey endpoint has fewer parts (no flat number, no landmark), and reusing
     * that one would mean giving it optional-everything parameters to serve two
     * callers badly.
     *
     * @param  array<string, mixed>  $input
     */
    private static function composeAddress(array $input, string $city): string
    {
        $line = trim((string) ($input['address_line'] ?? ''));
        $state = trim((string) ($input['state'] ?? ''));

        $parts = array_values(array_filter([$line, $city, $state], static fn (string $p): bool => $p !== ''));

        return implode(', ', $parts);
    }

    private static function coordinate(mixed $value): ?string
    {
        if ($value === null || $value === '') {
            return null;
        }

        return (string) $value;
    }

    private static function nullIfBlank(mixed $value): ?string
    {
        if (! is_string($value)) {
            return null;
        }

        $trimmed = trim($value);

        return $trimmed === '' ? null : $trimmed;
    }

    private static function normalize(string $value): string
    {
        return mb_strtolower(preg_replace('/\s+/u', ' ', trim($value)) ?? '');
    }
}
