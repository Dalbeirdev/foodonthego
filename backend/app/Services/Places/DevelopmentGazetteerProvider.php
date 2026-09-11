<?php

declare(strict_types=1);

namespace App\Services\Places;

/**
 * A small, fixed gazetteer for development and automated verification.
 *
 * **What this is.** Around a dozen real, well-known places with their real
 * published coordinates, so the trip planner can be driven end to end — search,
 * details, reverse geocoding, trip creation, database inspection — in an
 * environment that has no Places credentials and no egress to a provider.
 *
 * **What this is not.** It is not Google, and nothing it returns is presented as
 * Google's. Its identifiers are namespaced `dev:` precisely so that a row in the
 * database or a line in a log can never be mistaken for a provider place id, and
 * so that a query for real place ids finds none of these.
 *
 * **Why not fabricate coordinates instead.** Because a fabricated coordinate is
 * indistinguishable from a real one to Module 06's routing, and a corridor drawn
 * between two invented points would look entirely convincing while being wrong.
 * These are the real positions of real places; what is limited is the *size* of
 * the gazetteer, which is a limitation anybody can see rather than one hiding
 * inside plausible-looking data.
 *
 * It refuses to be constructed outside development, exactly as Module 03's
 * `LogOtpProvider` does.
 */
final class DevelopmentGazetteerProvider implements PlaceProvider
{
    /**
     * @var list<array{id: string, name: string, address: string, lat: float, lng: float, city: string, region: string, postal: ?string}>
     */
    private const PLACES = [
        [
            'id' => 'dev:igi-airport-t3',
            'name' => 'Indira Gandhi International Airport, Terminal 3',
            'address' => 'Terminal 3, IGI Airport, New Delhi, Delhi 110037',
            'lat' => 28.5562, 'lng' => 77.1000,
            'city' => 'New Delhi', 'region' => 'Delhi', 'postal' => '110037',
        ],
        [
            'id' => 'dev:connaught-place',
            'name' => 'Connaught Place',
            'address' => 'Connaught Place, New Delhi, Delhi 110001',
            'lat' => 28.6315, 'lng' => 77.2167,
            'city' => 'New Delhi', 'region' => 'Delhi', 'postal' => '110001',
        ],
        [
            'id' => 'dev:hauz-khas',
            'name' => 'Hauz Khas Village',
            'address' => 'Hauz Khas, New Delhi, Delhi 110016',
            'lat' => 28.5494, 'lng' => 77.2001,
            'city' => 'New Delhi', 'region' => 'Delhi', 'postal' => '110016',
        ],
        [
            'id' => 'dev:green-park',
            'name' => 'Green Park',
            'address' => 'Green Park, New Delhi, Delhi 110016',
            'lat' => 28.5590, 'lng' => 77.2070,
            'city' => 'New Delhi', 'region' => 'Delhi', 'postal' => '110016',
        ],
        [
            'id' => 'dev:jaipur-airport',
            'name' => 'Jaipur International Airport',
            'address' => 'Airport Road, Sanganer, Jaipur, Rajasthan 302029',
            'lat' => 26.8242, 'lng' => 75.8122,
            'city' => 'Jaipur', 'region' => 'Rajasthan', 'postal' => '302029',
        ],
        [
            'id' => 'dev:hawa-mahal',
            'name' => 'Hawa Mahal',
            'address' => 'Hawa Mahal Road, Badi Choupad, Jaipur, Rajasthan 302002',
            'lat' => 26.9239, 'lng' => 75.8267,
            'city' => 'Jaipur', 'region' => 'Rajasthan', 'postal' => '302002',
        ],
        [
            'id' => 'dev:mi-road-jaipur',
            'name' => 'MI Road',
            'address' => 'Mirza Ismail Road, Jaipur, Rajasthan 302001',
            'lat' => 26.9157, 'lng' => 75.8080,
            'city' => 'Jaipur', 'region' => 'Rajasthan', 'postal' => '302001',
        ],
        [
            'id' => 'dev:taj-mahal',
            'name' => 'Taj Mahal',
            'address' => 'Dharmapuri, Forest Colony, Tajganj, Agra, Uttar Pradesh 282001',
            'lat' => 27.1751, 'lng' => 78.0421,
            'city' => 'Agra', 'region' => 'Uttar Pradesh', 'postal' => '282001',
        ],
        [
            'id' => 'dev:agra-fort',
            'name' => 'Agra Fort',
            'address' => 'Rakabganj, Agra, Uttar Pradesh 282003',
            'lat' => 27.1795, 'lng' => 78.0211,
            'city' => 'Agra', 'region' => 'Uttar Pradesh', 'postal' => '282003',
        ],
        [
            'id' => 'dev:cyber-city',
            'name' => 'DLF Cyber City',
            'address' => 'DLF Cyber City, Gurugram, Haryana 122002',
            'lat' => 28.4949, 'lng' => 77.0886,
            'city' => 'Gurugram', 'region' => 'Haryana', 'postal' => '122002',
        ],
        [
            'id' => 'dev:chandigarh-sector-17',
            'name' => 'Sector 17 Plaza',
            'address' => 'Sector 17, Chandigarh 160017',
            'lat' => 30.7412, 'lng' => 76.7825,
            'city' => 'Chandigarh', 'region' => 'Chandigarh', 'postal' => '160017',
        ],
        [
            'id' => 'dev:mumbai-cst',
            'name' => 'Chhatrapati Shivaji Maharaj Terminus',
            'address' => 'Fort, Mumbai, Maharashtra 400001',
            'lat' => 18.9401, 'lng' => 72.8352,
            'city' => 'Mumbai', 'region' => 'Maharashtra', 'postal' => '400001',
        ],
    ];

    public function __construct(bool $isProduction)
    {
        if ($isProduction) {
            // The same refusal `LogOtpProvider` makes. A development stand-in
            // that can be constructed in production is one that will be.
            throw new \RuntimeException(
                'DevelopmentGazetteerProvider must never run in production. Configure a real place provider.',
            );
        }
    }

    public function name(): string
    {
        return 'development-gazetteer';
    }

    /** @return list<PlaceSuggestion> */
    public function search(string $query, ?string $sessionToken = null): array
    {
        // Every word must appear, in any order. A contiguous-substring match
        // would miss "jaipur airport" against "Jaipur International Airport",
        // which is exactly the shape of query a person types.
        $words = array_values(array_filter(explode(' ', $this->fold($query))));

        if ($words === []) {
            return [];
        }

        $matches = [];

        foreach (self::PLACES as $place) {
            $haystack = $this->fold($place['name'].' '.$place['address'].' '.$place['city'].' '.$place['region']);

            $matchesAll = true;
            foreach ($words as $word) {
                if (! str_contains($haystack, $word)) {
                    $matchesAll = false;
                    break;
                }
            }

            if ($matchesAll) {
                $matches[] = new PlaceSuggestion(
                    placeId: $place['id'],
                    primaryText: $place['name'],
                    secondaryText: $this->secondaryText($place),
                );
            }
        }

        return $matches;
    }

    public function details(string $placeId, ?string $sessionToken = null): PlaceDetails
    {
        foreach (self::PLACES as $place) {
            if ($place['id'] === $placeId) {
                return $this->toDetails($place);
            }
        }

        throw new PlaceLookupException('No such place in the development gazetteer.');
    }

    public function reverseGeocode(float $latitude, float $longitude): ?PlaceDetails
    {
        $nearest = null;
        $nearestDistance = INF;

        foreach (self::PLACES as $place) {
            $distance = $this->distanceInMetres($latitude, $longitude, $place['lat'], $place['lng']);

            if ($distance < $nearestDistance) {
                $nearest = $place;
                $nearestDistance = $distance;
            }
        }

        // Beyond this there is nothing in the gazetteer worth calling the place
        // by. Returning null is honest — the caller falls back to "Current
        // location", which is true of any coordinate.
        if ($nearest === null || $nearestDistance > 25_000) {
            return null;
        }

        return new PlaceDetails(
            placeId: $nearest['id'],
            displayName: $nearest['city'],
            formattedAddress: "{$nearest['city']}, {$nearest['region']}",
            // The caller's own fix, unchanged. Snapping it to the nearest known
            // landmark would move somebody's starting point by kilometres.
            latitude: $latitude,
            longitude: $longitude,
            city: $nearest['city'],
            region: $nearest['region'],
            countryCode: 'IN',
            postalCode: null,
        );
    }

    /** @param array{id: string, name: string, address: string, lat: float, lng: float, city: string, region: string, postal: ?string} $place */
    private function toDetails(array $place): PlaceDetails
    {
        return new PlaceDetails(
            placeId: $place['id'],
            displayName: $place['name'],
            formattedAddress: $place['address'],
            latitude: $place['lat'],
            longitude: $place['lng'],
            city: $place['city'],
            region: $place['region'],
            countryCode: 'IN',
            postalCode: $place['postal'],
        );
    }

    /** @param array{city: string, region: string} $place */
    private function secondaryText(array $place): string
    {
        return "{$place['city']}, {$place['region']}";
    }

    private function fold(string $value): string
    {
        return trim(mb_strtolower(preg_replace('/\s+/u', ' ', $value) ?? ''));
    }

    private function distanceInMetres(float $lat1, float $lon1, float $lat2, float $lon2): float
    {
        $earthRadius = 6_371_000.0;

        $phi1 = deg2rad($lat1);
        $phi2 = deg2rad($lat2);
        $deltaPhi = $phi2 - $phi1;
        $deltaLambda = deg2rad($lon2 - $lon1);

        $a = sin($deltaPhi / 2) ** 2 + cos($phi1) * cos($phi2) * sin($deltaLambda / 2) ** 2;

        return $earthRadius * 2 * atan2(sqrt($a), sqrt(1 - $a));
    }
}
