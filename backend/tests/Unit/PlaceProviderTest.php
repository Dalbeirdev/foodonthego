<?php

declare(strict_types=1);

namespace Tests\Unit;

use App\Services\Places\DevelopmentGazetteerProvider;
use App\Services\Places\GooglePlacesProvider;
use App\Services\Places\PlaceDetails;
use App\Services\Places\PlaceLookupException;
use App\Services\Places\PlaceSuggestion;
use App\Services\Places\UnconfiguredPlaceProvider;
use Illuminate\Http\Client\Factory as HttpFactory;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

/**
 * The three place providers.
 *
 * The Google one is exercised against a **stubbed HTTP transport**, not against
 * Google. That is a deliberate limit and it is stated plainly in the module's
 * evidence: this environment has no Places credentials and no egress to the
 * provider, so what these tests establish is that the adapter sends the right
 * request and reads the right response *shape*. Whether Google's live responses
 * match that shape is verified the first time a key exists, and until then the
 * module reports live place verification as pending rather than passed.
 *
 * The response fixtures below follow the documented Places API (New) shapes.
 */
final class PlaceProviderTest extends TestCase
{
    private function google(array $stub): GooglePlacesProvider
    {
        Http::fake($stub);

        return new GooglePlacesProvider(
            http: $this->app->make(HttpFactory::class),
            apiKey: 'test-key',
            regions: ['in'],
        );
    }

    // --- the Google adapter -------------------------------------------------

    public function test_the_adapter_maps_autocomplete_into_our_own_shape(): void
    {
        $provider = $this->google([
            'places.googleapis.com/v1/places:autocomplete' => Http::response([
                'suggestions' => [
                    ['placePrediction' => [
                        'placeId' => 'ChIJ_test',
                        'structuredFormat' => [
                            'mainText' => ['text' => 'Jaipur International Airport'],
                            'secondaryText' => ['text' => 'Sanganer, Jaipur, Rajasthan'],
                        ],
                    ]],
                ],
            ]),
        ]);

        $results = $provider->search('Jaipur');

        $this->assertCount(1, $results);
        $this->assertInstanceOf(PlaceSuggestion::class, $results[0]);
        $this->assertSame('ChIJ_test', $results[0]->placeId);
        $this->assertSame('Jaipur International Airport', $results[0]->primaryText);
    }

    public function test_the_key_and_the_field_mask_are_sent_as_headers(): void
    {
        $provider = $this->google([
            '*' => Http::response(['suggestions' => []]),
        ]);

        $provider->search('Jaipur', 'session-1');

        Http::assertSent(function ($request): bool {
            // In the header, never in a query string: a key in a URL ends up in
            // access logs and proxy logs. And a field mask, because Google bills
            // Details by the fields requested and the default is everything.
            return $request->hasHeader('X-Goog-Api-Key', 'test-key')
                && $request->hasHeader('X-Goog-FieldMask')
                && ! str_contains($request->url(), 'test-key');
        });
    }

    public function test_the_session_token_and_region_bias_are_sent(): void
    {
        $provider = $this->google(['*' => Http::response(['suggestions' => []])]);

        $provider->search('Jaipur', 'session-1');

        Http::assertSent(function ($request): bool {
            $body = $request->data();

            return ($body['sessionToken'] ?? null) === 'session-1'
                && ($body['includedRegionCodes'] ?? null) === ['in'];
        });
    }

    public function test_a_suggestion_without_a_place_id_is_skipped_rather_than_half_built(): void
    {
        $provider = $this->google([
            '*' => Http::response(['suggestions' => [
                ['queryPrediction' => ['text' => ['text' => 'restaurants near me']]],
                ['placePrediction' => ['placeId' => 'ChIJ_ok', 'structuredFormat' => []]],
            ]]),
        ]);

        $results = $provider->search('rest');

        $this->assertCount(1, $results);
        $this->assertSame('ChIJ_ok', $results[0]->placeId);
    }

    public function test_details_read_the_position_and_the_address_components(): void
    {
        $provider = $this->google([
            'places.googleapis.com/v1/places/*' => Http::response([
                'id' => 'ChIJ_test',
                'displayName' => ['text' => 'Jaipur International Airport'],
                'formattedAddress' => 'Airport Rd, Sanganer, Jaipur, Rajasthan 302029, India',
                'location' => ['latitude' => 26.8242, 'longitude' => 75.8122],
                'addressComponents' => [
                    ['types' => ['locality'], 'longText' => 'Jaipur', 'shortText' => 'Jaipur'],
                    ['types' => ['administrative_area_level_1'], 'longText' => 'Rajasthan', 'shortText' => 'RJ'],
                    ['types' => ['country'], 'longText' => 'India', 'shortText' => 'in'],
                    ['types' => ['postal_code'], 'longText' => '302029', 'shortText' => '302029'],
                ],
            ]),
        ]);

        $details = $provider->details('ChIJ_test');

        $this->assertInstanceOf(PlaceDetails::class, $details);
        $this->assertSame(26.8242, $details->latitude);
        $this->assertSame('Jaipur', $details->city);
        $this->assertSame('Rajasthan', $details->region);
        $this->assertSame('IN', $details->countryCode);
        $this->assertSame('302029', $details->postalCode);
    }

    public function test_a_place_with_no_location_is_a_failure_not_a_guess(): void
    {
        $provider = $this->google([
            'places.googleapis.com/v1/places/*' => Http::response([
                'id' => 'ChIJ_test',
                'displayName' => ['text' => 'Somewhere'],
                'formattedAddress' => 'Somewhere',
            ]),
        ]);

        // Deriving a position from the address text is precisely what must not
        // happen: it would be indistinguishable from a real one downstream.
        $this->expectException(PlaceLookupException::class);

        $provider->details('ChIJ_test');
    }

    public function test_reverse_geocoding_keeps_the_callers_own_coordinates(): void
    {
        $provider = $this->google([
            'maps.googleapis.com/maps/api/geocode/*' => Http::response([
                'results' => [[
                    'place_id' => 'ChIJ_gurugram',
                    'formatted_address' => 'Gurugram, Haryana, India',
                    'address_components' => [
                        ['types' => ['locality'], 'long_name' => 'Gurugram', 'short_name' => 'Gurugram'],
                        ['types' => ['country'], 'long_name' => 'India', 'short_name' => 'IN'],
                    ],
                ]],
            ]),
        ]);

        $details = $provider->reverseGeocode(28.4949, 77.0886);

        $this->assertNotNull($details);
        // Not the centroid of whatever Google matched: that would move the
        // customer's starting point by kilometres.
        $this->assertSame(28.4949, $details->latitude);
        $this->assertSame('Gurugram', $details->city);
    }

    public function test_reverse_geocoding_an_unnamed_point_returns_null(): void
    {
        $provider = $this->google([
            'maps.googleapis.com/maps/api/geocode/*' => Http::response(['results' => []]),
        ]);

        $this->assertNull($provider->reverseGeocode(-54.8, -68.3));
    }

    public function test_an_upstream_error_becomes_an_opaque_lookup_failure(): void
    {
        $provider = $this->google([
            '*' => Http::response(['error' => ['message' => 'API key not valid']], 403),
        ]);

        try {
            $provider->search('Jaipur');
            $this->fail('a 403 should have raised a lookup failure');
        } catch (PlaceLookupException $e) {
            // The upstream message names our key state. It goes to the log
            // against the request id, not into an exception a controller might
            // one day pass through.
            $this->assertStringNotContainsString('API key', $e->getMessage());
        }
    }

    public function test_a_malformed_response_is_a_failure_rather_than_an_empty_result(): void
    {
        $provider = $this->google(['*' => Http::response('not json', 200)]);

        // "No places match" and "the provider is broken" produce very different
        // screens, and a caller cannot tell them apart from an empty array.
        $this->expectException(PlaceLookupException::class);

        $provider->search('Jaipur');
    }

    // --- the unconfigured provider ------------------------------------------

    public function test_the_unconfigured_provider_fails_loudly_on_every_call(): void
    {
        $provider = new UnconfiguredPlaceProvider;

        foreach ([
            fn () => $provider->search('Jaipur'),
            fn () => $provider->details('x'),
            fn () => $provider->reverseGeocode(1.0, 1.0),
        ] as $call) {
            try {
                $call();
                $this->fail('the unconfigured provider should refuse');
            } catch (PlaceLookupException $e) {
                $this->assertStringContainsString('PLACES_PROVIDER', $e->getMessage());
            }
        }
    }

    // --- the development gazetteer ------------------------------------------

    public function test_the_gazetteer_refuses_to_exist_in_production(): void
    {
        $this->expectException(\RuntimeException::class);

        new DevelopmentGazetteerProvider(isProduction: true);
    }

    public function test_the_gazetteer_finds_a_place_by_name_or_by_address(): void
    {
        $provider = new DevelopmentGazetteerProvider(isProduction: false);

        $this->assertNotEmpty($provider->search('jaipur airport'));
        $this->assertNotEmpty($provider->search('Sanganer'));
        $this->assertSame([], $provider->search('Atlantis'));
    }

    public function test_the_gazetteers_identifiers_can_never_be_mistaken_for_a_providers(): void
    {
        $provider = new DevelopmentGazetteerProvider(isProduction: false);

        foreach ($provider->search('Delhi') as $suggestion) {
            // Namespaced so a row in the database or a line in a log is
            // obviously development data, and so a query for real place ids
            // finds none of these.
            $this->assertStringStartsWith('dev:', $suggestion->placeId);
        }
    }

    public function test_the_gazetteer_returns_real_coordinates_for_a_real_place(): void
    {
        $provider = new DevelopmentGazetteerProvider(isProduction: false);

        $details = $provider->details('dev:jaipur-airport');

        // Jaipur International Airport's published position. Real, because a
        // fabricated coordinate is indistinguishable from a true one to the
        // routing this feeds.
        $this->assertEqualsWithDelta(26.8242, $details->latitude, 0.001);
        $this->assertEqualsWithDelta(75.8122, $details->longitude, 0.001);
    }

    public function test_the_gazetteer_reverse_geocodes_to_the_nearest_known_city(): void
    {
        $provider = new DevelopmentGazetteerProvider(isProduction: false);

        $details = $provider->reverseGeocode(28.4950, 77.0890);

        $this->assertNotNull($details);
        $this->assertSame('Gurugram', $details->city);
        $this->assertSame(28.4950, $details->latitude);
    }

    public function test_the_gazetteer_admits_when_it_does_not_know_a_point(): void
    {
        $provider = new DevelopmentGazetteerProvider(isProduction: false);

        // Mid-Atlantic. Naming it after the nearest Indian city would be worse
        // than admitting ignorance.
        $this->assertNull($provider->reverseGeocode(0.0, -30.0));
    }

    public function test_an_unknown_place_id_is_a_failure(): void
    {
        $provider = new DevelopmentGazetteerProvider(isProduction: false);

        $this->expectException(PlaceLookupException::class);

        $provider->details('dev:atlantis');
    }
}
