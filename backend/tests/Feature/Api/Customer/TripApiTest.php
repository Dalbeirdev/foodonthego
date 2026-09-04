<?php

declare(strict_types=1);

namespace Tests\Feature\Api\Customer;

use App\Models\Trip;
use App\Models\User;
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Testing\TestResponse;
use Tests\Support\CustomerFactory;
use Tests\TestCase;

/**
 * The journey endpoints as a client sees them.
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
                'label' => 'Home',
                'address_line' => 'Hauz Khas',
                'city' => 'New Delhi',
                'state' => 'Delhi',
                'country_code' => 'IN',
            ],
            'destination' => [
                'label' => 'Jaipur',
                'address_line' => 'MI Road',
                'city' => 'Jaipur',
                'state' => 'Rajasthan',
                'country_code' => 'IN',
            ],
            'departure_at' => CarbonImmutable::now()->addDay()->toIso8601String(),
        ], $overrides);
    }

    /** @param array<string, mixed> $overrides */
    private function plan(array $overrides = []): TestResponse
    {
        return $this->asRahul()->postJson(self::BASE, $this->payload($overrides));
    }

    private function savedAddress(User $owner, string $label = 'Home'): string
    {
        $token = $owner->is($this->rahul) ? $this->rahulToken : CustomerFactory::tokenFor($owner);

        return $this->as($token)->postJson('/api/v1/customer/addresses', [
            'type' => 'HOME',
            'label' => $label,
            'address_line_1' => '12 Green Park Road',
            'city' => 'New Delhi',
            'state' => 'Delhi',
            'postal_code' => '110016',
            'country_code' => 'IN',
        ])->json('data.id');
    }

    public function test_planning_a_journey_returns_201_and_the_journey(): void
    {
        $response = $this->plan();

        $response->assertCreated()
            ->assertJsonPath('data.status', 'PLANNED')
            ->assertJsonPath('data.origin.city', 'New Delhi')
            ->assertJsonPath('data.destination.city', 'Jaipur')
            ->assertJsonPath('data.traveller_count', 1)
            ->assertJsonPath('data.is_editable', true)
            ->assertJsonPath('data.has_departed', false);
    }

    public function test_the_response_follows_the_standard_envelope(): void
    {
        $this->plan()->assertJsonStructure([
            'data' => [
                'id', 'status', 'origin' => ['label', 'formatted_address', 'city', 'country_code'],
                'destination', 'departure_at', 'traveller_count', 'is_editable',
            ],
            'meta' => ['request_id'],
        ]);
    }

    public function test_the_journey_id_is_a_uuid_not_a_database_key(): void
    {
        $id = $this->plan()->json('data.id');

        $this->assertMatchesRegularExpression(
            '/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/',
            (string) $id,
        );
    }

    public function test_no_internal_identifier_is_exposed(): void
    {
        $data = $this->plan()->json('data');

        foreach (['customer_id', 'origin_address_id', 'destination_address_id'] as $leak) {
            $this->assertArrayNotHasKey($leak, $data);
        }
    }

    public function test_the_formatted_address_is_composed_from_the_parts(): void
    {
        $this->plan()->assertJsonPath(
            'data.origin.formatted_address',
            'Hauz Khas, New Delhi, Delhi',
        );
    }

    public function test_coordinates_come_back_null_rather_than_invented(): void
    {
        $this->plan()
            ->assertJsonPath('data.origin.latitude', null)
            ->assertJsonPath('data.origin.longitude', null)
            ->assertJsonPath('data.destination.latitude', null)
            ->assertJsonPath('data.destination.longitude', null);
    }

    public function test_real_coordinates_are_kept_when_a_client_supplies_them(): void
    {
        $this->plan([
            'origin' => [
                'label' => 'Home', 'city' => 'New Delhi', 'country_code' => 'IN',
                'latitude' => 28.5602, 'longitude' => 77.2100,
            ],
        ])->assertCreated()->assertJsonPath('data.origin.latitude', '28.5602000');
    }

    public function test_half_a_coordinate_is_refused(): void
    {
        $this->plan([
            'origin' => [
                'label' => 'Home', 'city' => 'New Delhi', 'country_code' => 'IN',
                'latitude' => 28.5602,
            ],
        ])->assertStatus(422)->assertJsonPath('error.code', 'VALIDATION_FAILED');
    }

    public function test_an_endpoint_can_be_a_saved_address(): void
    {
        $addressId = $this->savedAddress($this->rahul);

        $this->plan(['origin' => ['address_id' => $addressId]])
            ->assertCreated()
            ->assertJsonPath('data.origin.label', 'Home')
            ->assertJsonPath('data.origin.city', 'New Delhi');
    }

    public function test_a_journey_needs_a_destination(): void
    {
        $payload = $this->payload();
        unset($payload['destination']);

        $this->asRahul()->postJson(self::BASE, $payload)
            ->assertStatus(422)
            ->assertJsonPath('error.code', 'VALIDATION_FAILED')
            ->assertJsonPath('error.details.fields.destination.0', 'Choose where you are going.');
    }

    public function test_a_typed_endpoint_needs_a_city_and_a_country(): void
    {
        $response = $this->plan(['destination' => ['label' => 'Somewhere']])->assertStatus(422);

        // Read as an array rather than by dotted path: the field key itself
        // contains a dot ("destination.city"), which a path lookup would split.
        $fields = $response->json('error.details.fields');

        $this->assertSame('Enter the city you are going to.', $fields['destination.city'][0]);
        $this->assertArrayHasKey('destination.country_code', $fields);
    }

    public function test_a_departure_in_the_past_is_refused(): void
    {
        $this->plan(['departure_at' => CarbonImmutable::now()->subDay()->toIso8601String()])
            ->assertStatus(422)
            ->assertJsonPath('error.details.fields.departure_at.0', 'Choose a departure time in the future.');
    }

    public function test_a_departure_moments_ago_is_accepted_within_the_grace(): void
    {
        // A handset whose clock runs a little behind the server's must still be
        // able to say "leaving now".
        $this->plan(['departure_at' => CarbonImmutable::now()->subMinute()->toIso8601String()])
            ->assertCreated();
    }

    public function test_a_departure_beyond_the_planning_horizon_is_refused(): void
    {
        $days = (int) config('foodonthego.trips.max_days_ahead');

        $this->plan(['departure_at' => CarbonImmutable::now()->addDays($days + 2)->toIso8601String()])
            ->assertStatus(422)
            ->assertJsonPath('error.details.fields.departure_at.0', 'That is too far ahead to plan a journey.');
    }

    public function test_the_same_place_twice_is_not_a_journey(): void
    {
        $this->plan(['destination' => $this->payload()['origin']])
            ->assertStatus(422)
            ->assertJsonPath('error.code', 'VALIDATION_FAILED');
    }

    public function test_a_traveller_count_above_the_ceiling_is_refused(): void
    {
        $max = (int) config('foodonthego.trips.max_travellers');

        $this->plan(['traveller_count' => $max + 1])->assertStatus(422);
    }

    public function test_a_note_longer_than_the_column_is_refused(): void
    {
        $this->plan(['note' => str_repeat('a', 281)])->assertStatus(422);
    }

    public function test_the_list_defaults_to_upcoming(): void
    {
        Trip::factory()->ownedBy($this->rahul)->departed()->create();
        $ahead = Trip::factory()->ownedBy($this->rahul)->departingAt(CarbonImmutable::now()->addDays(2))->create();

        $this->asRahul()->getJson(self::BASE)
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.id', $ahead->uuid);
    }

    public function test_the_list_scope_can_be_asked_for_explicitly(): void
    {
        Trip::factory()->ownedBy($this->rahul)->departed()->create();
        Trip::factory()->ownedBy($this->rahul)->departingAt(CarbonImmutable::now()->addDay())->create();

        $this->asRahul()->getJson(self::BASE.'?scope=past')->assertOk()->assertJsonCount(1, 'data');
        $this->asRahul()->getJson(self::BASE.'?scope=all')->assertOk()->assertJsonCount(2, 'data');
    }

    public function test_an_unknown_scope_is_a_validation_failure_not_a_silent_everything(): void
    {
        $this->asRahul()->getJson(self::BASE.'?scope=everything')
            ->assertStatus(422)
            ->assertJsonPath('error.code', 'VALIDATION_FAILED');
    }

    public function test_next_returns_the_soonest_journey_still_ahead(): void
    {
        Trip::factory()->ownedBy($this->rahul)->departingAt(CarbonImmutable::now()->addDays(4))->create();
        $soonest = Trip::factory()->ownedBy($this->rahul)->departingAt(CarbonImmutable::now()->addHours(5))->create();

        $this->asRahul()->getJson(self::BASE.'/next')
            ->assertOk()
            ->assertJsonPath('data.id', $soonest->uuid);
    }

    public function test_next_returns_null_rather_than_404_when_there_is_no_journey(): void
    {
        // Null is a normal answer here: the home screen renders nothing for
        // journeys, and a 404 would make an ordinary state look like a failure.
        $this->asRahul()->getJson(self::BASE.'/next')->assertOk()->assertJsonPath('data', null);
    }

    public function test_next_is_matched_as_a_literal_not_as_a_journey_id(): void
    {
        Trip::factory()->ownedBy($this->rahul)->create();

        $this->asRahul()->getJson(self::BASE.'/next')
            ->assertOk()
            ->assertJsonMissingPath('error');
    }

    public function test_a_journey_can_be_read_back(): void
    {
        $id = $this->plan()->json('data.id');

        $this->asRahul()->getJson(self::BASE.'/'.$id)
            ->assertOk()
            ->assertJsonPath('data.id', $id);
    }

    public function test_a_planned_journey_can_be_changed(): void
    {
        $id = $this->plan()->json('data.id');

        $this->asRahul()->patchJson(self::BASE.'/'.$id, [
            'traveller_count' => 4,
            'note' => 'Two stops on the way',
        ])
            ->assertOk()
            ->assertJsonPath('data.traveller_count', 4)
            ->assertJsonPath('data.note', 'Two stops on the way');
    }

    public function test_a_change_persists(): void
    {
        $id = $this->plan()->json('data.id');
        $this->asRahul()->patchJson(self::BASE.'/'.$id, ['traveller_count' => 2]);

        $this->asRahul()->getJson(self::BASE.'/'.$id)->assertJsonPath('data.traveller_count', 2);
    }

    public function test_a_departed_journey_reports_that_it_cannot_be_changed(): void
    {
        $trip = Trip::factory()->ownedBy($this->rahul)->departed()->create();

        $this->asRahul()->getJson(self::BASE.'/'.$trip->uuid)
            ->assertOk()
            ->assertJsonPath('data.is_editable', false)
            ->assertJsonPath('data.has_departed', true);

        $this->asRahul()->patchJson(self::BASE.'/'.$trip->uuid, ['traveller_count' => 2])
            ->assertStatus(422)
            ->assertJsonPath('error.code', 'TRIP_NOT_EDITABLE');
    }

    public function test_a_journey_can_be_cancelled_with_a_reason(): void
    {
        $id = $this->plan()->json('data.id');

        $this->asRahul()->postJson(self::BASE.'/'.$id.'/cancel', ['reason' => 'Meeting moved'])
            ->assertOk()
            ->assertJsonPath('data.status', 'CANCELLED')
            ->assertJsonPath('data.cancellation_reason', 'Meeting moved');
    }

    public function test_cancelling_twice_is_refused(): void
    {
        $id = $this->plan()->json('data.id');
        $this->asRahul()->postJson(self::BASE.'/'.$id.'/cancel');

        $this->asRahul()->postJson(self::BASE.'/'.$id.'/cancel')
            ->assertStatus(422)
            ->assertJsonPath('error.code', 'TRIP_NOT_EDITABLE');
    }

    public function test_a_cancelled_journey_leaves_the_upcoming_list(): void
    {
        $id = $this->plan()->json('data.id');
        $this->asRahul()->postJson(self::BASE.'/'.$id.'/cancel');

        $this->asRahul()->getJson(self::BASE)->assertOk()->assertJsonCount(0, 'data');
        $this->asRahul()->getJson(self::BASE.'?scope=cancelled')->assertOk()->assertJsonCount(1, 'data');
    }

    public function test_there_is_no_delete_endpoint(): void
    {
        $id = $this->plan()->json('data.id');

        // A journey is history. Cancelling records a decision; deleting would
        // erase the record a later module's orders point at.
        $this->asRahul()->deleteJson(self::BASE.'/'.$id)->assertStatus(405);
    }

    public function test_the_upcoming_limit_is_reported_with_its_own_code(): void
    {
        $limit = (int) config('foodonthego.trips.max_upcoming_per_customer');

        Trip::factory()->count($limit)->ownedBy($this->rahul)
            ->departingAt(CarbonImmutable::now()->addDays(3))->create();

        $this->plan()
            ->assertStatus(422)
            ->assertJsonPath('error.code', 'TRIP_LIMIT_REACHED');
    }

    public function test_every_endpoint_requires_a_token(): void
    {
        $trip = Trip::factory()->ownedBy($this->rahul)->create();
        $this->flushHeaders();

        $this->getJson(self::BASE)->assertUnauthorized();
        $this->getJson(self::BASE.'/next')->assertUnauthorized();
        $this->postJson(self::BASE, $this->payload())->assertUnauthorized();
        $this->getJson(self::BASE.'/'.$trip->uuid)->assertUnauthorized();
        $this->patchJson(self::BASE.'/'.$trip->uuid, [])->assertUnauthorized();
        $this->postJson(self::BASE.'/'.$trip->uuid.'/cancel')->assertUnauthorized();
    }

    public function test_a_revoked_token_reaches_nothing(): void
    {
        $this->asRahul()->postJson('/api/v1/auth/logout')->assertNoContent();

        $this->asRahul()->getJson(self::BASE)->assertUnauthorized();
    }
}
