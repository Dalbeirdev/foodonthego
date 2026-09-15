<?php

declare(strict_types=1);

namespace Tests\Feature\Api\Customer;

use App\Models\Trip;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Testing\TestResponse;
use Tests\Support\CustomerFactory;
use Tests\TestCase;

/**
 * The trip endpoints as a client sees them.
 */
final class TripApiTest extends TestCase
{
    use RefreshDatabase;

    private const BASE = '/api/v1/customer/trips';

    private User $rahul;

    private string $rahulToken;

    protected function setUp(): void
    {
        parent::setUp();

        $this->rahul = CustomerFactory::rahul();
        $this->rahulToken = CustomerFactory::tokenFor($this->rahul);
    }

    private function as(string $token): self
    {
        $this->app['auth']->forgetGuards();

        return $this->withHeader('Authorization', 'Bearer '.$token);
    }

    private function asRahul(): self
    {
        return $this->as($this->rahulToken);
    }

    /** @param array<string, mixed> $overrides */
    private function payload(array $overrides = []): array
    {
        return array_merge([
            'origin' => [
                'source_type' => 'PLACE_SEARCH',
                'place_id' => 'dev:hauz-khas',
                'display_name' => 'Hauz Khas Village',
                'formatted_address' => 'Hauz Khas, New Delhi, Delhi 110016',
                'latitude' => 28.5494,
                'longitude' => 77.2001,
                'city' => 'New Delhi',
                'region' => 'Delhi',
                'country_code' => 'IN',
            ],
            'destination' => [
                'source_type' => 'PLACE_SEARCH',
                'place_id' => 'dev:jaipur-airport',
                'display_name' => 'Jaipur International Airport',
                'formatted_address' => 'Airport Road, Sanganer, Jaipur, Rajasthan',
                'latitude' => 26.8242,
                'longitude' => 75.8122,
                'city' => 'Jaipur',
                'region' => 'Rajasthan',
                'country_code' => 'IN',
            ],
        ], $overrides);
    }

    /** @param array<string, mixed> $overrides */
    private function create(array $overrides = []): TestResponse
    {
        return $this->asRahul()->postJson(self::BASE, $this->payload($overrides));
    }

    // --- creation ---------------------------------------------------------

    public function test_creating_a_trip_returns_201_and_the_trip(): void
    {
        $this->create()
            ->assertCreated()
            ->assertJsonPath('data.status', 'ROUTE_PENDING')
            ->assertJsonPath('data.route_status', 'NOT_CALCULATED')
            ->assertJsonPath('data.origin.city', 'New Delhi')
            ->assertJsonPath('data.destination.city', 'Jaipur');
    }

    public function test_the_response_follows_the_standard_envelope(): void
    {
        $this->create()->assertJsonStructure([
            'data' => [
                'id', 'status', 'route_status',
                'origin' => ['source_type', 'display_name', 'formatted_address', 'latitude', 'longitude'],
                'destination',
            ],
            'meta' => ['request_id'],
        ]);
    }

    public function test_no_route_data_is_returned_because_none_exists(): void
    {
        $data = $this->create()->json('data');

        // Not "null distance" — no key at all. A client that finds none cannot
        // render an estimate, and nobody can be tempted to seed one.
        foreach (['distance', 'distance_metres', 'duration', 'duration_seconds', 'polyline', 'eta'] as $absent) {
            $this->assertArrayNotHasKey($absent, $data);
        }
    }

    public function test_the_trip_id_is_a_uuid_not_a_database_key(): void
    {
        $this->assertMatchesRegularExpression(
            '/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/',
            (string) $this->create()->json('data.id'),
        );
    }

    public function test_no_internal_identifier_is_exposed(): void
    {
        $data = $this->create()->json('data');

        $this->assertArrayNotHasKey('customer_id', $data);
        $this->assertArrayNotHasKey('saved_address_id', $data['origin']);
    }

    public function test_the_source_of_each_end_comes_back(): void
    {
        $this->create()
            ->assertJsonPath('data.origin.source_type', 'PLACE_SEARCH')
            ->assertJsonPath('data.destination.source_type', 'PLACE_SEARCH');
    }

    public function test_a_current_location_origin_is_accepted(): void
    {
        $this->create([
            'origin' => [
                'source_type' => 'CURRENT_LOCATION',
                'display_name' => 'Current location',
                'formatted_address' => 'Gurugram, Haryana',
                'latitude' => 28.4949,
                'longitude' => 77.0886,
            ],
        ])
            ->assertCreated()
            ->assertJsonPath('data.origin.source_type', 'CURRENT_LOCATION')
            ->assertJsonPath('data.origin.place_id', null);
    }

    public function test_coordinates_round_trip_at_the_column_scale(): void
    {
        $this->create()->assertJsonPath('data.origin.latitude', '28.5494000');
    }

    // --- validation -------------------------------------------------------

    public function test_an_origin_is_required(): void
    {
        $payload = $this->payload();
        unset($payload['origin']);

        $this->asRahul()->postJson(self::BASE, $payload)
            ->assertStatus(422)
            ->assertJsonPath('error.details.fields.origin.0', 'Choose where you are setting off from.');
    }

    public function test_a_destination_is_required(): void
    {
        $payload = $this->payload();
        unset($payload['destination']);

        $this->asRahul()->postJson(self::BASE, $payload)
            ->assertStatus(422)
            ->assertJsonPath('error.details.fields.destination.0', 'Choose where you are going.');
    }

    public function test_an_endpoint_without_coordinates_is_refused(): void
    {
        $origin = $this->payload()['origin'];
        unset($origin['latitude'], $origin['longitude']);

        $this->create(['origin' => $origin])
            ->assertStatus(422)
            ->assertJsonPath('error.code', 'VALIDATION_FAILED');
    }

    public function test_an_impossible_latitude_is_refused_by_the_server(): void
    {
        $this->create([
            'origin' => $this->payload()['origin'] + [] === [] ? [] : array_merge(
                $this->payload()['origin'],
                ['latitude' => 999, 'longitude' => -999],
            ),
        ])->assertStatus(422)->assertJsonPath('error.code', 'VALIDATION_FAILED');

        $this->assertSame(0, Trip::query()->count());
    }

    public function test_null_island_is_refused_with_its_own_code(): void
    {
        $this->create([
            'origin' => array_merge($this->payload()['origin'], ['latitude' => 0, 'longitude' => 0]),
        ])
            ->assertStatus(422)
            ->assertJsonPath('error.code', 'INVALID_COORDINATES');
    }

    public function test_an_unknown_source_type_is_refused(): void
    {
        $this->create([
            'origin' => array_merge($this->payload()['origin'], ['source_type' => 'TELEPORT']),
        ])->assertStatus(422);
    }

    public function test_the_same_place_at_both_ends_is_refused_with_its_own_code(): void
    {
        $this->create(['destination' => $this->payload()['origin']])
            ->assertStatus(422)
            ->assertJsonPath('error.code', 'SAME_LOCATION');
    }

    public function test_a_saved_address_endpoint_needs_an_address_id(): void
    {
        $response = $this->create([
            'origin' => ['source_type' => 'SAVED_ADDRESS'],
        ])->assertStatus(422);

        // Read as an array rather than by dotted path: the field key itself
        // contains a dot, which a path lookup would split.
        $fields = $response->json('error.details.fields');

        $this->assertSame('Choose a saved address.', $fields['origin.saved_address_id'][0]);
    }

    // --- reading ----------------------------------------------------------

    public function test_a_trip_can_be_read_back(): void
    {
        $id = $this->create()->json('data.id');

        $this->asRahul()->getJson(self::BASE.'/'.$id)
            ->assertOk()
            ->assertJsonPath('data.id', $id)
            ->assertJsonPath('data.route_status', 'NOT_CALCULATED');
    }

    public function test_the_list_is_newest_first(): void
    {
        $older = Trip::factory()->ownedBy($this->rahul)->create();
        $newer = Trip::factory()->ownedBy($this->rahul)->delhiToAgra()->create();

        $this->asRahul()->getJson(self::BASE)
            ->assertOk()
            ->assertJsonPath('data.0.id', $newer->uuid)
            ->assertJsonPath('data.1.id', $older->uuid);
    }

    public function test_the_list_can_be_filtered_by_status(): void
    {
        Trip::factory()->ownedBy($this->rahul)->create();
        Trip::factory()->ownedBy($this->rahul)->discarded()->create();

        $this->asRahul()->getJson(self::BASE.'?status=ROUTE_PENDING')->assertJsonCount(1, 'data');
        $this->asRahul()->getJson(self::BASE.'?status=CANCELLED')->assertJsonCount(1, 'data');
        $this->asRahul()->getJson(self::BASE)->assertJsonCount(2, 'data');
    }

    public function test_an_unknown_status_filter_is_a_validation_failure(): void
    {
        $this->asRahul()->getJson(self::BASE.'?status=ACTIVE')
            ->assertStatus(422)
            ->assertJsonPath('error.code', 'VALIDATION_FAILED');
    }

    public function test_current_returns_the_newest_live_trip(): void
    {
        Trip::factory()->ownedBy($this->rahul)->discarded()->create();
        $live = Trip::factory()->ownedBy($this->rahul)->create();

        $this->asRahul()->getJson(self::BASE.'/current')
            ->assertOk()
            ->assertJsonPath('data.id', $live->uuid);
    }

    public function test_current_returns_null_rather_than_404_when_there_is_none(): void
    {
        // An ordinary state, not a failure: the home screen renders nothing for
        // trips when it gets one.
        $this->asRahul()->getJson(self::BASE.'/current')->assertOk()->assertJsonPath('data', null);
    }

    public function test_current_is_matched_as_a_literal_not_as_a_trip_id(): void
    {
        Trip::factory()->ownedBy($this->rahul)->create();

        $this->asRahul()->getJson(self::BASE.'/current')
            ->assertOk()
            ->assertJsonMissingPath('error');
    }

    // --- discarding -------------------------------------------------------

    public function test_a_trip_can_be_discarded(): void
    {
        $id = $this->create()->json('data.id');

        $this->asRahul()->postJson(self::BASE.'/'.$id.'/discard')
            ->assertOk()
            ->assertJsonPath('data.status', 'CANCELLED');
    }

    public function test_discarding_twice_is_refused(): void
    {
        $id = $this->create()->json('data.id');
        $this->asRahul()->postJson(self::BASE.'/'.$id.'/discard');

        $this->asRahul()->postJson(self::BASE.'/'.$id.'/discard')
            ->assertStatus(422)
            ->assertJsonPath('error.code', 'TRIP_NOT_EDITABLE');
    }

    public function test_there_is_no_delete_endpoint(): void
    {
        $id = $this->create()->json('data.id');

        $this->asRahul()->deleteJson(self::BASE.'/'.$id)->assertStatus(405);
    }

    public function test_the_pending_limit_is_reported_with_its_own_code(): void
    {
        $limit = (int) config('foodonthego.trips.max_pending_per_customer');
        Trip::factory()->count($limit)->ownedBy($this->rahul)->create();

        $this->create()
            ->assertStatus(422)
            ->assertJsonPath('error.code', 'TRIP_LIMIT_REACHED');
    }

    // --- duplicate submission ---------------------------------------------

    public function test_an_idempotency_key_makes_a_retried_create_return_the_same_trip(): void
    {
        $payload = $this->payload();
        $key = 'trip-create-'.uniqid();

        // Module 01's idempotency middleware already answers the double-tap
        // problem properly, and it applies here for free.
        $first = $this->asRahul()->withHeader('Idempotency-Key', $key)
            ->postJson(self::BASE, $payload)->assertCreated()->json('data.id');

        $second = $this->asRahul()->withHeader('Idempotency-Key', $key)
            ->postJson(self::BASE, $payload)->json('data.id');

        $this->assertSame($first, $second);
        $this->assertSame(1, Trip::query()->count());
    }

    // --- authentication ---------------------------------------------------

    public function test_every_endpoint_requires_a_token(): void
    {
        $trip = Trip::factory()->ownedBy($this->rahul)->create();
        $this->flushHeaders();

        $this->getJson(self::BASE)->assertUnauthorized();
        $this->getJson(self::BASE.'/current')->assertUnauthorized();
        $this->postJson(self::BASE, $this->payload())->assertUnauthorized();
        $this->getJson(self::BASE.'/'.$trip->uuid)->assertUnauthorized();
        $this->postJson(self::BASE.'/'.$trip->uuid.'/discard')->assertUnauthorized();
    }

    public function test_a_revoked_token_reaches_nothing(): void
    {
        $this->asRahul()->postJson('/api/v1/auth/logout')->assertNoContent();

        $this->asRahul()->getJson(self::BASE)->assertUnauthorized();
    }
}
