<?php

declare(strict_types=1);

namespace App\Services\Places;

use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\Client\Factory as HttpFactory;
use Illuminate\Http\Client\Response;
use Illuminate\Support\Facades\Log;
use Throwable;

/**
 * Google Places API (New), called from the server.
 *
 * **Why the server and not the app.** A Places key in a mobile binary is a key
 * that has been published: it can be pulled out of an APK in a minute, and the
 * only protections available are the platform restrictions Google offers, which
 * bound the damage rather than preventing it. Held here, the key is
 * IP-restricted to our servers, never ships to a device, and can be rotated
 * without an app release. The trade is a hop through our API, which this product
 * pays gladly — the same hop is where rate limiting and the customer's own
 * session already live.
 *
 * **Session tokens.** Autocomplete is billed per session when a token groups the
 * keystrokes with the Details call that ends them, and per request when it does
 * not. The token is minted by the client when a search screen opens, sent with
 * every keystroke and with the final Details call, and then discarded — see
 * `docs/20-trip-planner.md`. This class does not invent one: a token generated
 * per request would be strictly worse than none at all, because it would bill a
 * session per keystroke.
 *
 * **Field masks.** Both calls send an explicit `X-Goog-FieldMask`. Google bills
 * Details by the fields requested, and the default is everything.
 */
final class GooglePlacesProvider implements PlaceProvider
{
    private const SEARCH_URL = 'https://places.googleapis.com/v1/places:autocomplete';

    private const DETAILS_URL = 'https://places.googleapis.com/v1/places/';

    private const GEOCODE_URL = 'https://maps.googleapis.com/maps/api/geocode/json';

    public function __construct(
        private readonly HttpFactory $http,
        private readonly string $apiKey,
        /** ISO-3166-1 alpha-2 codes the search is biased towards. Empty means worldwide. */
        private readonly array $regions = [],
        private readonly int $timeoutSeconds = 5,
        private readonly int $maxResults = 8,
    ) {}

    public function name(): string
    {
        return 'google-places';
    }

    /** @return list<PlaceSuggestion> */
    public function search(string $query, ?string $sessionToken = null): array
    {
        $body = [
            'input' => $query,
            // A bias, not a filter, and configurable: the launch market is India,
            // and a permanent hard-coding of it would have to be found and undone
            // in the first month of the second market.
            'includedRegionCodes' => $this->regions === [] ? null : array_values($this->regions),
            'sessionToken' => $sessionToken,
        ];

        $payload = $this->call(
            fn (): Response => $this->http
                ->timeout($this->timeoutSeconds)
                ->withHeaders($this->headers([
                    'suggestions.placePrediction.placeId',
                    'suggestions.placePrediction.structuredFormat',
                ]))
                ->post(self::SEARCH_URL, array_filter($body, static fn ($v): bool => $v !== null)),
            'search',
        );

        $suggestions = [];

        foreach ($payload['suggestions'] ?? [] as $entry) {
            $prediction = $entry['placePrediction'] ?? null;
            if (! is_array($prediction)) {
                continue;
            }

            $placeId = $prediction['placeId'] ?? null;
            if (! is_string($placeId) || $placeId === '') {
                continue;
            }

            $format = $prediction['structuredFormat'] ?? [];

            $suggestions[] = new PlaceSuggestion(
                placeId: $placeId,
                primaryText: (string) ($format['mainText']['text'] ?? ''),
                secondaryText: (string) ($format['secondaryText']['text'] ?? ''),
            );

            if (count($suggestions) >= $this->maxResults) {
                break;
            }
        }

        return $suggestions;
    }

    public function details(string $placeId, ?string $sessionToken = null): PlaceDetails
    {
        $url = self::DETAILS_URL.rawurlencode($placeId);

        $payload = $this->call(
            fn (): Response => $this->http
                ->timeout($this->timeoutSeconds)
                ->withHeaders($this->headers([
                    'id', 'displayName', 'formattedAddress', 'location', 'addressComponents',
                ]))
                ->get($url, array_filter(['sessionToken' => $sessionToken])),
            'details',
        );

        $location = $payload['location'] ?? [];

        if (! isset($location['latitude'], $location['longitude'])) {
            // A place with no position is not a place this product can use, and
            // guessing one from the address text is exactly what must not happen.
            throw new PlaceLookupException('Google returned a place with no location.');
        }

        $components = $this->addressComponents($payload['addressComponents'] ?? []);

        return new PlaceDetails(
            placeId: (string) ($payload['id'] ?? $placeId),
            displayName: (string) ($payload['displayName']['text'] ?? ''),
            formattedAddress: (string) ($payload['formattedAddress'] ?? ''),
            latitude: (float) $location['latitude'],
            longitude: (float) $location['longitude'],
            city: $components['city'],
            region: $components['region'],
            countryCode: $components['country'],
            postalCode: $components['postal'],
        );
    }

    public function reverseGeocode(float $latitude, float $longitude): ?PlaceDetails
    {
        $payload = $this->call(
            fn (): Response => $this->http
                ->timeout($this->timeoutSeconds)
                ->get(self::GEOCODE_URL, [
                    'latlng' => "{$latitude},{$longitude}",
                    'key' => $this->apiKey,
                ]),
            'reverse-geocode',
        );

        $first = $payload['results'][0] ?? null;

        if (! is_array($first)) {
            return null;
        }

        $components = $this->addressComponents(
            $this->normalizeLegacyComponents($first['address_components'] ?? []),
        );

        return new PlaceDetails(
            placeId: (string) ($first['place_id'] ?? ''),
            displayName: $components['city'] ?? (string) ($first['formatted_address'] ?? ''),
            formattedAddress: (string) ($first['formatted_address'] ?? ''),
            // The device's own fix, unchanged. Replacing it with the centroid of
            // whatever Google matched would move the customer's starting point.
            latitude: $latitude,
            longitude: $longitude,
            city: $components['city'],
            region: $components['region'],
            countryCode: $components['country'],
            postalCode: $components['postal'],
        );
    }

    /** @param list<string> $fields */
    private function headers(array $fields): array
    {
        return [
            'X-Goog-Api-Key' => $this->apiKey,
            'X-Goog-FieldMask' => implode(',', $fields),
        ];
    }

    /**
     * Runs a call and turns every failure into one opaque exception.
     *
     * The upstream body goes to the log against the request id and nowhere near
     * the client: a Google error names our project, our key state and our quota.
     *
     * @param  callable(): Response  $send
     * @return array<string, mixed>
     */
    private function call(callable $send, string $operation): array
    {
        try {
            $response = $send();
        } catch (ConnectionException $e) {
            $this->logFailure($operation, 'connection', $e->getMessage());
            throw new PlaceLookupException('The place provider could not be reached.');
        } catch (Throwable $e) {
            $this->logFailure($operation, 'exception', $e->getMessage());
            throw new PlaceLookupException('The place provider failed.');
        }

        if ($response->failed()) {
            $this->logFailure($operation, 'http', (string) $response->status());
            throw new PlaceLookupException('The place provider returned an error.');
        }

        $decoded = $response->json();

        if (! is_array($decoded)) {
            $this->logFailure($operation, 'malformed', 'response was not an object');
            throw new PlaceLookupException('The place provider returned something unreadable.');
        }

        return $decoded;
    }

    private function logFailure(string $operation, string $kind, string $detail): void
    {
        // No query text and no coordinates: what somebody searched for is as
        // personal as where they live.
        Log::warning('places.provider_failed', [
            'provider' => $this->name(),
            'operation' => $operation,
            'kind' => $kind,
            'detail' => mb_substr($detail, 0, 200),
        ]);
    }

    /**
     * @param  list<array<string, mixed>>  $components
     * @return array{city: ?string, region: ?string, country: ?string, postal: ?string}
     */
    private function addressComponents(array $components): array
    {
        $found = ['city' => null, 'region' => null, 'country' => null, 'postal' => null];

        foreach ($components as $component) {
            $types = (array) ($component['types'] ?? []);
            $long = $component['longText'] ?? null;
            $short = $component['shortText'] ?? null;

            if (in_array('locality', $types, true) && $found['city'] === null) {
                $found['city'] = is_string($long) ? $long : null;
            }
            if (in_array('administrative_area_level_1', $types, true) && $found['region'] === null) {
                $found['region'] = is_string($long) ? $long : null;
            }
            if (in_array('country', $types, true) && $found['country'] === null) {
                $found['country'] = is_string($short) ? strtoupper($short) : null;
            }
            if (in_array('postal_code', $types, true) && $found['postal'] === null) {
                $found['postal'] = is_string($long) ? $long : null;
            }
        }

        return $found;
    }

    /**
     * The Geocoding API is the older one and names the same fields differently.
     *
     * @param  list<array<string, mixed>>  $components
     * @return list<array<string, mixed>>
     */
    private function normalizeLegacyComponents(array $components): array
    {
        return array_map(static fn (array $c): array => [
            'types' => $c['types'] ?? [],
            'longText' => $c['long_name'] ?? null,
            'shortText' => $c['short_name'] ?? null,
        ], $components);
    }
}
