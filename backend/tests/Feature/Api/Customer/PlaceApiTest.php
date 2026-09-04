<?php

declare(strict_types=1);

namespace Tests\Feature\Api\Customer;

use App\Models\User;
use App\Services\Places\PlaceDetails;
use App\Services\Places\PlaceLookupException;
use App\Services\Places\PlaceProvider;
use App\Services\Places\PlaceSuggestion;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Support\CustomerFactory;
use Tests\TestCase;

/**
 * The place endpoints, and the way a provider failure reaches a customer.
 *
 * The provider is swapped for a recording double so the tests exercise *this
 * server's* behaviour — caching, error translation, authentication — rather than
 * whichever provider happens to be configured.
 */
final class PlaceApiTest extends TestCase
{
    use RefreshDatabase;

    private const SEARCH = '/api/v1/customer/places/search';

    private User $rahul;

    private string $token;

    protected function setUp(): void
    {
        parent::setUp();

        $this->rahul = CustomerFactory::rahul();
        $this->token = CustomerFactory::tokenFor($this->rahul);
    }

    private function asRahul(): self
    {
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', 'Bearer '.$this->token);
    }

    private function useProvider(PlaceProvider $provider): PlaceProvider
    {
        $this->app->instance(PlaceProvider::class, $provider);

        return $provider;
    }

    // --- search ------------------------------------------------------------

    public function test_search_returns_the_providers_suggestions_in_our_own_shape(): void
    {
        $this->useProvider(new RecordingPlaceProvider);

        $this->asRahul()->getJson(self::SEARCH.'?q=Jaipur')
            ->assertOk()
            ->assertJsonPath('data.0.place_id', 'dev:jaipur-airport')
            ->assertJsonPath('data.0.primary_text', 'Jaipur International Airport')
            ->assertJsonPath('data.0.secondary_text', 'Sanganer, Jaipur, Rajasthan');
    }

    public function test_a_suggestion_carries_no_coordinates(): void
    {
        $this->useProvider(new RecordingPlaceProvider);

        $first = $this->asRahul()->getJson(self::SEARCH.'?q=Jaipur')->json('data.0');

        // Autocomplete answers "which place did you mean". Coordinates come from
        // the details call, and a suggestion that carried them would invite a
        // client to route to the centroid of a search term.
        $this->assertArrayNotHasKey('latitude', $first);
        $this->assertArrayNotHasKey('longitude', $first);
    }

    public function test_a_query_that_is_too_short_is_refused_before_the_provider_is_called(): void
    {
        $provider = $this->useProvider(new RecordingPlaceProvider);

        $this->asRahul()->getJson(self::SEARCH.'?q=J')->assertStatus(422);

        // A single letter is not a search; sending it upstream would spend a
        // metered request on nothing.
        $this->assertSame(0, $provider->searchCount);
    }

    public function test_the_session_token_is_passed_through_to_the_provider(): void
    {
        $provider = $this->useProvider(new RecordingPlaceProvider);

        $this->asRahul()->getJson(self::SEARCH.'?q=Jaipur&session_token=abc-123')->assertOk();

        // Without this the provider bills a session per keystroke rather than one
        // per search.
        $this->assertSame('abc-123', $provider->lastSessionToken);
    }

    public function test_an_identical_query_is_served_from_cache(): void
    {
        $provider = $this->useProvider(new RecordingPlaceProvider);

        $this->asRahul()->getJson(self::SEARCH.'?q=Jaipur')->assertOk();
        $this->asRahul()->getJson(self::SEARCH.'?q=jaipur')->assertOk();

        // Case-folded and keyed by the query alone, so a retyped search does not
        // cost twice.
        $this->assertSame(1, $provider->searchCount);
    }

    public function test_the_cache_is_not_scoped_to_a_customer_and_holds_nothing_personal(): void
    {
        $provider = $this->useProvider(new RecordingPlaceProvider);
        $ananya = CustomerFactory::ananya();
        $hers = CustomerFactory::tokenFor($ananya);

        $this->asRahul()->getJson(self::SEARCH.'?q=Jaipur')->assertOk();

        $this->app['auth']->forgetGuards();
        $this->flushHeaders();
        $this->withHeader('Authorization', 'Bearer '.$hers)
            ->getJson(self::SEARCH.'?q=Jaipur')
            ->assertOk()
            ->assertJsonPath('data.0.place_id', 'dev:jaipur-airport');

        // The same public answer to the same public question. What is *not*
        // cached is anything customer-specific, which is why sharing it is safe.
        $this->assertSame(1, $provider->searchCount);
    }

    public function test_a_provider_failure_becomes_one_opaque_code(): void
    {
        $this->useProvider(new FailingPlaceProvider);

        $response = $this->asRahul()->getJson(self::SEARCH.'?q=Jaipur')
            ->assertStatus(503)
            ->assertJsonPath('error.code', 'PLACE_LOOKUP_FAILED');

        // Nothing about our key, our quota or our project reaches the client.
        $body = (string) $response->getContent();
        $this->assertStringNotContainsString('quota', $body);
        $this->assertStringNotContainsString('API key', $body);
    }

    public function test_no_results_is_an_empty_list_and_not_an_error(): void
    {
        $this->useProvider(new RecordingPlaceProvider(suggestions: []));

        $this->asRahul()->getJson(self::SEARCH.'?q=Atlantis')
            ->assertOk()
            ->assertJsonCount(0, 'data');
    }

    // --- details -----------------------------------------------------------

    public function test_details_resolve_a_suggestion_into_something_with_a_position(): void
    {
        $this->useProvider(new RecordingPlaceProvider);

        $this->asRahul()->getJson('/api/v1/customer/places/dev:jaipur-airport')
            ->assertOk()
            ->assertJsonPath('data.latitude', 26.8242)
            ->assertJsonPath('data.longitude', 75.8122)
            ->assertJsonPath('data.country_code', 'IN');
    }

    public function test_details_pass_the_session_token_that_closes_the_search(): void
    {
        $provider = $this->useProvider(new RecordingPlaceProvider);

        $this->asRahul()->getJson('/api/v1/customer/places/dev:jaipur-airport?session_token=abc-123')
            ->assertOk();

        $this->assertSame('abc-123', $provider->lastSessionToken);
    }

    // --- reverse geocoding -------------------------------------------------

    public function test_reverse_geocoding_names_a_coordinate(): void
    {
        $this->useProvider(new RecordingPlaceProvider);

        $this->asRahul()->postJson('/api/v1/customer/places/reverse-geocode', [
            'latitude' => 28.4949,
            'longitude' => 77.0886,
        ])
            ->assertOk()
            ->assertJsonPath('data.city', 'Gurugram')
            // The caller's own fix, unchanged: snapping it to a landmark would
            // move somebody's starting point.
            ->assertJsonPath('data.latitude', 28.4949);
    }

    public function test_a_coordinate_with_no_name_is_a_success_not_a_failure(): void
    {
        $this->useProvider(new RecordingPlaceProvider(reverse: false));

        // The coordinates came from the device and are authoritative. "Current
        // location" is a perfectly good label over them.
        $this->asRahul()->postJson('/api/v1/customer/places/reverse-geocode', [
            'latitude' => -54.8,
            'longitude' => -68.3,
        ])->assertOk()->assertJsonPath('data', null);
    }

    public function test_an_impossible_coordinate_is_refused(): void
    {
        $provider = $this->useProvider(new RecordingPlaceProvider);

        $this->asRahul()->postJson('/api/v1/customer/places/reverse-geocode', [
            'latitude' => 999,
            'longitude' => -999,
        ])->assertStatus(422);

        $this->assertSame(0, $provider->reverseCount);
    }

    // --- authentication ----------------------------------------------------

    public function test_place_lookup_requires_a_token(): void
    {
        $this->useProvider(new RecordingPlaceProvider);
        $this->flushHeaders();

        // An open endpoint on a server holding a metered provider key is
        // somebody else's free geocoder.
        $this->getJson(self::SEARCH.'?q=Jaipur')->assertUnauthorized();
        $this->getJson('/api/v1/customer/places/dev:jaipur-airport')->assertUnauthorized();
        $this->postJson('/api/v1/customer/places/reverse-geocode', [
            'latitude' => 28.4949, 'longitude' => 77.0886,
        ])->assertUnauthorized();
    }
}

/** A provider that records what it was asked and answers predictably. */
final class RecordingPlaceProvider implements PlaceProvider
{
    public int $searchCount = 0;

    public int $detailsCount = 0;

    public int $reverseCount = 0;

    public ?string $lastSessionToken = null;

    /**
     * @param  list<PlaceSuggestion>|null  $suggestions  Null means "the usual one result".
     * @param  bool  $reverse  False makes reverse geocoding answer "no name for this point".
     */
    public function __construct(
        private readonly ?array $suggestions = null,
        private readonly bool $reverse = true,
    ) {}

    public function name(): string
    {
        return 'recording';
    }

    /** @return list<PlaceSuggestion> */
    public function search(string $query, ?string $sessionToken = null): array
    {
        $this->searchCount++;
        $this->lastSessionToken = $sessionToken;

        return $this->suggestions ?? [
            new PlaceSuggestion(
                'dev:jaipur-airport',
                'Jaipur International Airport',
                'Sanganer, Jaipur, Rajasthan',
            ),
        ];
    }

    public function details(string $placeId, ?string $sessionToken = null): PlaceDetails
    {
        $this->detailsCount++;
        $this->lastSessionToken = $sessionToken;

        return new PlaceDetails(
            placeId: $placeId,
            displayName: 'Jaipur International Airport',
            formattedAddress: 'Airport Road, Sanganer, Jaipur, Rajasthan 302029',
            latitude: 26.8242,
            longitude: 75.8122,
            city: 'Jaipur',
            region: 'Rajasthan',
            countryCode: 'IN',
            postalCode: '302029',
        );
    }

    public function reverseGeocode(float $latitude, float $longitude): ?PlaceDetails
    {
        $this->reverseCount++;

        if (! $this->reverse) {
            return null;
        }

        return new PlaceDetails(
            placeId: 'dev:cyber-city',
            displayName: 'Gurugram',
            formattedAddress: 'Gurugram, Haryana',
            // The caller's own fix, unchanged.
            latitude: $latitude,
            longitude: $longitude,
            city: 'Gurugram',
            region: 'Haryana',
            countryCode: 'IN',
        );
    }
}

/** A provider that is down. */
final class FailingPlaceProvider implements PlaceProvider
{
    public function name(): string
    {
        return 'failing';
    }

    public function search(string $query, ?string $sessionToken = null): array
    {
        throw new PlaceLookupException('quota exceeded for project fotg-123, API key AIza…');
    }

    public function details(string $placeId, ?string $sessionToken = null): PlaceDetails
    {
        throw new PlaceLookupException('quota exceeded');
    }

    public function reverseGeocode(float $latitude, float $longitude): ?PlaceDetails
    {
        throw new PlaceLookupException('quota exceeded');
    }
}
