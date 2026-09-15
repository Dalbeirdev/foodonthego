<?php

declare(strict_types=1);

namespace Tests\Feature\Api\Customer;

use App\Models\CustomerAddress;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Testing\TestResponse;
use Tests\Support\CustomerFactory;
use Tests\TestCase;

final class AddressApiTest extends TestCase
{
    use RefreshDatabase;

    private const BASE = '/api/v1/customer/addresses';

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
            'type' => 'HOME',
            'address_line_1' => '12 Green Park Road',
            'address_line_2' => 'Green Park',
            'landmark' => 'Near Green Park Metro',
            'city' => 'New Delhi',
            'state' => 'Delhi',
            'postal_code' => '110016',
            'country_code' => 'IN',
        ], $overrides);
    }

    private function createHome(): TestResponse
    {
        return $this->asRahul()->postJson(self::BASE, $this->payload());
    }

    private function createWork(): TestResponse
    {
        return $this->asRahul()->postJson(self::BASE, $this->payload([
            'type' => 'WORK',
            'address_line_1' => 'Connaught Place',
            'address_line_2' => null,
            'landmark' => null,
            'postal_code' => '110001',
        ]));
    }

    // --- CRUD ---------------------------------------------------------------

    public function test_the_list_starts_empty(): void
    {
        $this->asRahul()->getJson(self::BASE)
            ->assertOk()
            ->assertJsonPath('data', []);
    }

    public function test_creating_an_address_returns_it_composed_and_default(): void
    {
        $this->createHome()
            ->assertCreated()
            ->assertJsonPath('data.type', 'HOME')
            ->assertJsonPath('data.label', 'Home')
            ->assertJsonPath('data.city', 'New Delhi')
            ->assertJsonPath('data.formatted_address', '12 Green Park Road, Green Park, New Delhi, Delhi 110016, IN')
            // The first address a customer saves becomes their default.
            ->assertJsonPath('data.is_default', true)
            // Never invented from a text address.
            ->assertJsonPath('data.latitude', null)
            ->assertJsonPath('data.longitude', null);
    }

    public function test_the_response_exposes_a_uuid_and_no_internal_columns(): void
    {
        $body = $this->createHome()->json('data');

        $this->assertMatchesRegularExpression('/^[0-9a-f-]{36}$/', $body['id']);
        foreach (['customer_id', 'default_for_customer'] as $internal) {
            $this->assertArrayNotHasKey($internal, $body);
        }
    }

    public function test_a_second_address_does_not_take_the_default(): void
    {
        $this->createHome()->assertCreated();
        $this->createWork()
            ->assertCreated()
            ->assertJsonPath('data.is_default', false);

        $list = $this->asRahul()->getJson(self::BASE)->json('data');

        $this->assertCount(2, $list);
        // Default first, deterministically — a list that reorders makes people
        // tap the wrong row.
        $this->assertTrue($list[0]['is_default']);
        $this->assertSame('HOME', $list[0]['type']);
    }

    public function test_an_address_can_be_retrieved_by_its_uuid(): void
    {
        $id = $this->createHome()->json('data.id');

        $this->asRahul()->getJson(self::BASE.'/'.$id)
            ->assertOk()
            ->assertJsonPath('data.id', $id);
    }

    public function test_a_partial_update_changes_only_what_was_sent(): void
    {
        $id = $this->createHome()->json('data.id');

        $this->asRahul()->patchJson(self::BASE.'/'.$id, ['landmark' => 'Opposite the park'])
            ->assertOk()
            ->assertJsonPath('data.landmark', 'Opposite the park')
            ->assertJsonPath('data.address_line_1', '12 Green Park Road')
            // The one-line form is recomposed, not left stale.
            ->assertJsonPath('data.formatted_address', '12 Green Park Road, Green Park, New Delhi, Delhi 110016, IN');
    }

    public function test_deleting_an_address_removes_it(): void
    {
        $id = $this->createHome()->json('data.id');

        $this->asRahul()->deleteJson(self::BASE.'/'.$id)->assertNoContent();

        $this->assertDatabaseCount('customer_addresses', 0);
        $this->asRahul()->getJson(self::BASE.'/'.$id)->assertStatus(404);
    }

    // --- default handling ---------------------------------------------------

    public function test_the_dedicated_endpoint_moves_the_default(): void
    {
        $homeId = $this->createHome()->json('data.id');
        $workId = $this->createWork()->json('data.id');

        $this->asRahul()->postJson(self::BASE.'/'.$workId.'/default')
            ->assertOk()
            ->assertJsonPath('data.is_default', true);

        $this->assertDefaultCountIs(1);
        $this->assertFalse($this->addressByUuid($homeId)->is_default);
    }

    public function test_a_patch_can_also_set_the_default(): void
    {
        $homeId = $this->createHome()->json('data.id');
        $workId = $this->createWork()->json('data.id');

        $this->asRahul()->patchJson(self::BASE.'/'.$workId, ['is_default' => true])
            ->assertOk()
            ->assertJsonPath('data.is_default', true);

        $this->assertFalse($this->addressByUuid($homeId)->is_default);
        $this->assertDefaultCountIs(1);
    }

    public function test_a_patch_cannot_leave_a_customer_with_no_default(): void
    {
        $homeId = $this->createHome()->json('data.id');

        $this->asRahul()->patchJson(self::BASE.'/'.$homeId, ['is_default' => false])
            ->assertOk();

        // Un-defaulting by PATCH is ignored. Choosing a different default is what
        // setting one on another address is for.
        $this->assertDefaultCountIs(1);
    }

    public function test_setting_the_current_default_again_is_a_no_op(): void
    {
        $homeId = $this->createHome()->json('data.id');

        $this->asRahul()->postJson(self::BASE.'/'.$homeId.'/default')->assertOk();
        $this->asRahul()->postJson(self::BASE.'/'.$homeId.'/default')->assertOk();

        // Safe to retry: this is a control somebody taps in a list.
        $this->assertDefaultCountIs(1);
    }

    public function test_deleting_the_default_promotes_a_replacement(): void
    {
        $homeId = $this->createHome()->json('data.id');
        $workId = $this->createWork()->json('data.id');

        $this->asRahul()->deleteJson(self::BASE.'/'.$homeId)->assertNoContent();

        $this->assertTrue($this->addressByUuid($workId)->is_default);
        $this->assertDefaultCountIs(1);
    }

    // --- validation ---------------------------------------------------------

    public function test_the_required_fields_are_required(): void
    {
        foreach (['type', 'address_line_1', 'city', 'state', 'country_code'] as $field) {
            $payload = $this->payload();
            unset($payload[$field]);

            $this->asRahul()->postJson(self::BASE, $payload)
                ->assertStatus(422)
                ->assertJsonPath('error.code', 'VALIDATION_FAILED')
                ->assertJsonStructure(['error' => ['details' => ['fields' => [$field]]]]);
        }

        $this->assertDatabaseCount('customer_addresses', 0);
    }

    public function test_an_unknown_address_type_is_rejected(): void
    {
        $this->asRahul()->postJson(self::BASE, $this->payload(['type' => 'WAREHOUSE']))
            ->assertStatus(422);
    }

    public function test_an_other_address_must_be_named(): void
    {
        $this->asRahul()->postJson(self::BASE, $this->payload(['type' => 'OTHER', 'label' => '  ']))
            ->assertStatus(422)
            ->assertJsonStructure(['error' => ['details' => ['fields' => ['label']]]]);

        $this->asRahul()->postJson(self::BASE, $this->payload([
            'type' => 'OTHER',
            'label' => "Parents' House",
        ]))
            ->assertCreated()
            ->assertJsonPath('data.label', "Parents' House");
    }

    public function test_home_and_work_are_labelled_from_their_type(): void
    {
        $this->asRahul()->postJson(self::BASE, $this->payload(['label' => null]))
            ->assertCreated()
            ->assertJsonPath('data.label', 'Home');
    }

    public function test_an_indian_address_needs_a_valid_pin_code(): void
    {
        foreach (['11001', '1100166', '010016', 'ABC123', ''] as $bad) {
            $this->asRahul()->postJson(self::BASE, $this->payload(['postal_code' => $bad]))
                ->assertStatus(422);
        }
    }

    public function test_a_country_without_pin_codes_is_not_forced_to_have_one(): void
    {
        $this->asRahul()->postJson(self::BASE, $this->payload([
            'city' => 'Dubai',
            'state' => 'Dubai',
            'country_code' => 'AE',
            'postal_code' => null,
        ]))->assertCreated();
    }

    public function test_out_of_range_coordinates_are_rejected(): void
    {
        $this->asRahul()->postJson(self::BASE, $this->payload(['latitude' => 91]))
            ->assertStatus(422);
        $this->asRahul()->postJson(self::BASE, $this->payload(['longitude' => -181]))
            ->assertStatus(422);

        $this->asRahul()->postJson(self::BASE, $this->payload([
            'latitude' => 28.5602,
            'longitude' => 77.2043,
        ]))
            ->assertCreated()
            // The stored scale, not the submitted string — the response is what
            // the database holds.
            ->assertJsonPath('data.latitude', '28.5602000')
            ->assertJsonPath('data.longitude', '77.2043000');
    }

    public function test_an_over_long_label_is_rejected(): void
    {
        $this->asRahul()->postJson(self::BASE, $this->payload([
            'type' => 'OTHER',
            'label' => str_repeat('A', 200),
        ]))->assertStatus(422);
    }

    public function test_a_country_code_must_be_two_letters(): void
    {
        foreach (['IND', 'I', '12', ''] as $bad) {
            $this->asRahul()->postJson(self::BASE, $this->payload(['country_code' => $bad]))
                ->assertStatus(422);
        }
    }

    public function test_a_lowercase_country_code_is_normalised(): void
    {
        $this->asRahul()->postJson(self::BASE, $this->payload(['country_code' => 'in']))
            ->assertCreated()
            ->assertJsonPath('data.country_code', 'IN');
    }

    public function test_markup_and_sql_shaped_text_are_stored_as_typed(): void
    {
        $payload = "12 <script>alert('x')</script> Road'; DROP TABLE customer_addresses; --";

        $this->asRahul()->postJson(self::BASE, $this->payload(['address_line_1' => $payload]))
            ->assertCreated()
            ->assertJsonPath('data.address_line_1', $payload);

        $this->assertDatabaseCount('customer_addresses', 1);
    }

    public function test_the_saved_address_limit_is_reported_with_its_own_code(): void
    {
        config(['foodonthego.addresses.max_per_customer' => 2]);

        $this->createHome()->assertCreated();
        $this->createWork()->assertCreated();

        $this->asRahul()->postJson(self::BASE, $this->payload(['address_line_1' => 'Third Road']))
            ->assertStatus(422)
            ->assertJsonPath('error.code', 'ADDRESS_LIMIT_REACHED');
    }

    // --- authentication -----------------------------------------------------

    public function test_every_endpoint_requires_a_token(): void
    {
        $id = $this->createHome()->json('data.id');

        $unauthenticated = [
            ['getJson', self::BASE],
            ['getJson', self::BASE.'/'.$id],
            ['postJson', self::BASE],
            ['patchJson', self::BASE.'/'.$id],
            ['deleteJson', self::BASE.'/'.$id],
            ['postJson', self::BASE.'/'.$id.'/default'],
        ];

        foreach ($unauthenticated as [$method, $uri]) {
            $this->app['auth']->forgetGuards();
            // Headers accumulate on the test instance, so the bearer token from
            // the setup call above would still be sent without this.
            $this->flushHeaders();

            $this->{$method}($uri, [])
                ->assertStatus(401)
                ->assertJsonPath('error.code', 'UNAUTHENTICATED');
        }
    }

    private function addressByUuid(string $uuid): CustomerAddress
    {
        return CustomerAddress::query()->where('uuid', $uuid)->firstOrFail();
    }

    private function assertDefaultCountIs(int $expected): void
    {
        $this->assertSame(
            $expected,
            CustomerAddress::query()
                ->where('customer_id', $this->rahul->getKey())
                ->where('is_default', true)
                ->count(),
        );
    }
}
