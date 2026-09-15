<?php

declare(strict_types=1);

namespace Tests\Feature\Api\Customer;

use App\Enums\LocationSourceType;
use App\Enums\RouteStatus;
use App\Enums\TripStatus;
use App\Models\Trip;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\Support\CustomerFactory;
use Tests\TestCase;

/**
 * The mandatory IDOR matrix, plus the injection attacks.
 *
 * Rahul is authenticated throughout and attacks Ananya's trip and her saved
 * address by their real identifiers. Every attempt must be refused, must leak
 * nothing, and must leave her data byte-identical.
 */
final class TripOwnershipTest extends TestCase
{
    use RefreshDatabase;

    private const BASE = '/api/v1/customer/trips';

    private const ADDRESSES = '/api/v1/customer/addresses';

    private User $rahul;

    private User $ananya;

    private string $rahulToken;

    private string $ananyaToken;

    private Trip $hers;

    protected function setUp(): void
    {
        parent::setUp();

        $this->rahul = CustomerFactory::rahul();
        $this->ananya = CustomerFactory::ananya();
        $this->rahulToken = CustomerFactory::tokenFor($this->rahul);
        $this->ananyaToken = CustomerFactory::tokenFor($this->ananya);

        $this->hers = Trip::factory()->ownedBy($this->ananya)->create([
            'origin_name' => 'Ananya Home',
            'origin_formatted_address' => 'Sector 44, Gurugram, Haryana',
            'origin_city' => 'Gurugram',
            'destination_name' => 'Sector 17 Plaza',
            'destination_formatted_address' => 'Sector 17, Chandigarh',
            'destination_city' => 'Chandigarh',
        ]);
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

    private function target(): string
    {
        return self::BASE.'/'.$this->hers->uuid;
    }

    /** @param array<string, mixed> $overrides */
    private function payload(array $overrides = []): array
    {
        return array_merge([
            'origin' => [
                'source_type' => 'PLACE_SEARCH',
                'place_id' => 'dev:hauz-khas',
                'display_name' => 'Hauz Khas Village',
                'formatted_address' => 'Hauz Khas, New Delhi',
                'latitude' => 28.5494,
                'longitude' => 77.2001,
            ],
            'destination' => [
                'source_type' => 'PLACE_SEARCH',
                'place_id' => 'dev:jaipur-airport',
                'display_name' => 'Jaipur International Airport',
                'formatted_address' => 'Sanganer, Jaipur',
                'latitude' => 26.8242,
                'longitude' => 75.8122,
            ],
        ], $overrides);
    }

    private function rahulsAddress(): string
    {
        return $this->asRahul()->postJson(self::ADDRESSES, [
            'type' => 'HOME',
            'label' => 'Rahul Home',
            'address_line_1' => '12 Mandi House',
            'city' => 'New Delhi',
            'state' => 'Delhi',
            'postal_code' => '110001',
            'country_code' => 'IN',
            'latitude' => 28.6100,
            'longitude' => 77.2300,
        ])->assertCreated()->json('data.id');
    }

    private function ananyasAddress(): string
    {
        return $this->as($this->ananyaToken)->postJson(self::ADDRESSES, [
            'type' => 'HOME',
            'label' => 'Ananya Home',
            'address_line_1' => '9 Sector 44',
            'city' => 'Gurugram',
            'state' => 'Haryana',
            'postal_code' => '122003',
            'country_code' => 'IN',
            'latitude' => 28.4400,
            'longitude' => 77.0500,
        ])->assertCreated()->json('data.id');
    }

    // --- the trip matrix ---------------------------------------------------

    public function test_rahul_cannot_read_ananyas_trip(): void
    {
        $response = $this->asRahul()->getJson($this->target());

        $response->assertNotFound()->assertJsonPath('error.code', 'TRIP_NOT_FOUND');

        $body = (string) $response->getContent();
        foreach (['Gurugram', 'Chandigarh', 'Ananya Home', '28.4', '76.7'] as $secret) {
            $this->assertStringNotContainsString($secret, $body);
        }
    }

    public function test_rahul_cannot_discard_ananyas_trip(): void
    {
        $this->asRahul()->postJson($this->target().'/discard')
            ->assertNotFound()
            ->assertJsonPath('error.code', 'TRIP_NOT_FOUND');

        $trip = $this->hers->fresh();
        $this->assertNotNull($trip);
        $this->assertSame(TripStatus::RoutePending, $trip->status);
        $this->assertNull($trip->cancelled_at);
    }

    public function test_rahul_cannot_delete_ananyas_trip(): void
    {
        // There is no DELETE at all, which is the strongest possible answer.
        $this->asRahul()->deleteJson($this->target())->assertStatus(405);

        $this->assertNotNull($this->hers->fresh());
    }

    public function test_ananyas_trip_is_untouched_after_every_attempt(): void
    {
        $before = $this->hers->fresh()?->toArray();

        $this->asRahul()->getJson($this->target());
        $this->asRahul()->postJson($this->target().'/discard');
        $this->asRahul()->deleteJson($this->target());
        $this->asRahul()->patchJson($this->target(), ['status' => 'CANCELLED']);

        $this->assertEquals($before, $this->hers->fresh()?->toArray());
    }

    public function test_a_missing_trip_answers_identically_to_a_foreign_one(): void
    {
        $missing = $this->asRahul()->getJson(self::BASE.'/'.Str::uuid())->assertNotFound();
        $notMine = $this->asRahul()->getJson($this->target())->assertNotFound();

        $this->assertSame($missing->json('error.code'), $notMine->json('error.code'));
        $this->assertSame($missing->json('error.message'), $notMine->json('error.message'));
    }

    public function test_each_customer_sees_only_their_own_trips(): void
    {
        Trip::factory()->count(2)->ownedBy($this->rahul)->create();

        $this->asRahul()->getJson(self::BASE)->assertOk()->assertJsonCount(2, 'data');
        $this->as($this->ananyaToken)->getJson(self::BASE)->assertOk()->assertJsonCount(1, 'data');
    }

    public function test_current_never_returns_another_customers_trip(): void
    {
        $this->asRahul()->getJson(self::BASE.'/current')->assertOk()->assertJsonPath('data', null);
    }

    // --- the saved-address attack -----------------------------------------

    public function test_rahul_cannot_create_a_trip_from_ananyas_saved_address(): void
    {
        $hers = $this->ananyasAddress();

        $response = $this->asRahul()->postJson(self::BASE, $this->payload([
            'origin' => [
                'source_type' => 'SAVED_ADDRESS',
                'saved_address_id' => $hers,
            ],
        ]));

        // The same 404 a direct read of that address gives. Crucially *not* a
        // validation error saying the address exists but is not his — and not a
        // 403, which would confirm the identifier is real.
        $response->assertNotFound()->assertJsonPath('error.code', 'ADDRESS_NOT_FOUND');
        $this->assertStringNotContainsString('Gurugram', (string) $response->getContent());

        $this->assertSame(0, Trip::query()->where('customer_id', $this->rahul->getKey())->count());
    }

    public function test_the_refusal_reveals_nothing_about_whether_the_address_exists(): void
    {
        $real = $this->ananyasAddress();
        $imaginary = (string) Str::uuid();

        $withReal = $this->asRahul()->postJson(self::BASE, $this->payload([
            'origin' => ['source_type' => 'SAVED_ADDRESS', 'saved_address_id' => $real],
        ]));

        $withImaginary = $this->asRahul()->postJson(self::BASE, $this->payload([
            'origin' => ['source_type' => 'SAVED_ADDRESS', 'saved_address_id' => $imaginary],
        ]));

        $this->assertSame($withReal->status(), $withImaginary->status());
        $this->assertSame($withReal->json('error.code'), $withImaginary->json('error.code'));
        $this->assertSame($withReal->json('error.message'), $withImaginary->json('error.message'));
    }

    // --- injection ---------------------------------------------------------

    /**
     * A saved address supplies its own position, whatever the client claims.
     *
     * The attack is subtler than an IDOR and easy to miss: Rahul uses *his own*
     * address, which he is entitled to, but sends coordinates a thousand
     * kilometres away with it. If those were written, a customer could make a
     * journey appear to start anywhere while pointing at a legitimate saved
     * record — and Module 07 would then look for restaurants along a corridor
     * that has nothing to do with where they are.
     *
     * Nothing rejects the extra fields. They are simply never read: the service
     * resolves the row through Module 04 and takes the position from it, so a
     * tampered client is sending values into a void. The assertion is on what
     * the trip *holds*, not on a refusal.
     */
    public function test_coordinates_sent_with_a_saved_address_are_ignored(): void
    {
        $his = $this->rahulsAddress();

        $response = $this->asRahul()->postJson(self::BASE, $this->payload([
            'origin' => [
                'source_type' => 'SAVED_ADDRESS',
                'saved_address_id' => $his,
                // Mumbai, roughly 1,150 km from the saved address in Delhi.
                'latitude' => 19.0760,
                'longitude' => 72.8777,
                'display_name' => 'NOT WHERE HE LIVES',
                'formatted_address' => 'Somewhere else entirely',
                'place_id' => 'attacker-supplied',
            ],
        ]));

        $response->assertCreated();

        $trip = Trip::query()->where('uuid', $response->json('data.id'))->firstOrFail();

        $this->assertSame('28.6100000', (string) $trip->origin_latitude);
        $this->assertSame('77.2300000', (string) $trip->origin_longitude);
        $this->assertSame('Rahul Home', $trip->origin_name);
        $this->assertNotSame('attacker-supplied', $trip->origin_place_id);
        $this->assertStringNotContainsString('NOT WHERE HE LIVES', (string) $response->getContent());
    }

    /**
     * The negative control for the test above.
     *
     * Those same coordinates *are* honoured for a place-search endpoint, which
     * is what makes the previous assertion mean something: the values are not
     * being dropped by a validator that discards unknown keys, they are being
     * overridden by the saved address specifically.
     */
    public function test_the_same_coordinates_are_honoured_for_a_searched_place(): void
    {
        $response = $this->asRahul()->postJson(self::BASE, $this->payload([
            'origin' => [
                'source_type' => 'PLACE_SEARCH',
                'place_id' => 'dev:somewhere',
                'display_name' => 'A place in Mumbai',
                'latitude' => 19.0760,
                'longitude' => 72.8777,
            ],
        ]));

        $response->assertCreated();

        $trip = Trip::query()->where('uuid', $response->json('data.id'))->firstOrFail();

        $this->assertSame('19.0760000', (string) $trip->origin_latitude);
        $this->assertSame('72.8777000', (string) $trip->origin_longitude);
    }

    public function test_a_customer_id_in_the_body_does_not_change_ownership(): void
    {
        $response = $this->asRahul()->postJson(self::BASE, $this->payload([
            'customer_id' => $this->ananya->getKey(),
        ]))->assertCreated();

        $trip = Trip::query()->where('uuid', $response->json('data.id'))->firstOrFail();

        $this->assertSame($this->rahul->getKey(), $trip->customer_id);
    }

    public function test_a_status_in_the_body_cannot_set_the_lifecycle(): void
    {
        $response = $this->asRahul()->postJson(self::BASE, $this->payload([
            'status' => 'CANCELLED',
            'route_status' => 'READY',
            'cancelled_at' => now()->toIso8601String(),
        ]))->assertCreated();

        $trip = Trip::query()->where('uuid', $response->json('data.id'))->firstOrFail();

        $this->assertSame(TripStatus::RoutePending, $trip->status);
        $this->assertSame(RouteStatus::NotCalculated, $trip->route_status);
        $this->assertNull($trip->cancelled_at);
    }

    public function test_route_results_cannot_be_injected(): void
    {
        $response = $this->asRahul()->postJson(self::BASE, $this->payload([
            'distance_metres' => 1,
            'duration_seconds' => 1,
            'polyline' => 'abc',
            'eta' => now()->toIso8601String(),
        ]))->assertCreated();

        $trip = Trip::query()->where('uuid', $response->json('data.id'))->firstOrFail();
        $columns = $trip->getAttributes();

        // Not "they were ignored" — there is nowhere for them to go. A schema
        // with a nullable distance column is an invitation to fill one in.
        foreach (['distance_metres', 'duration_seconds', 'polyline', 'eta'] as $absent) {
            $this->assertArrayNotHasKey($absent, $columns);
        }

        $this->assertSame(RouteStatus::NotCalculated, $trip->route_status);
    }

    public function test_a_saved_address_id_pointing_at_a_trip_is_not_confused_for_one(): void
    {
        // Identifiers are uuids across every table, so a caller can try one from
        // the wrong one. The ownership-scoped lookup does not care what kind of
        // row it is: it is not this customer's address, so it is not found.
        $this->asRahul()->postJson(self::BASE, $this->payload([
            'origin' => [
                'source_type' => 'SAVED_ADDRESS',
                'saved_address_id' => $this->hers->uuid,
            ],
        ]))->assertNotFound()->assertJsonPath('error.code', 'ADDRESS_NOT_FOUND');
    }

    public function test_markup_in_a_place_name_is_stored_as_text_and_returned_as_text(): void
    {
        // Place names come from an external provider. They are stored and
        // returned as data; nothing in this API renders HTML, and the JSON
        // encoder escapes what it must.
        $hostile = '<script>alert(1)</script>';

        $response = $this->asRahul()->postJson(self::BASE, $this->payload([
            'origin' => array_merge($this->payload()['origin'], ['display_name' => $hostile]),
        ]))->assertCreated();

        $trip = Trip::query()->where('uuid', $response->json('data.id'))->firstOrFail();

        // Stored verbatim: it is a name, and mangling somebody's data on the way
        // in is not sanitisation, it is corruption. The escaping that matters
        // happens where the value is rendered.
        $this->assertSame($hostile, $trip->origin_name);
        $this->assertSame(LocationSourceType::PlaceSearch, $trip->origin_source_type);

        $body = (string) $response->getContent();

        // The response is JSON, not a document, and every angle bracket leaves
        // as a \uXXXX escape — so neither the opening tag nor the closing one
        // survives as markup if this body is ever inlined into a document.
        //
        // This assertion used to accept the weaker guarantee PHP gives for
        // free: the closing tag escaped by the slash, the opening tag left
        // alone as inert. It is inert only until somebody inlines the body
        // somewhere a `<` starts something. ApiResponse now encodes with
        // JSON_HEX_TAG and its neighbours, so the guarantee no longer depends
        // on which half of the tag it is.
        $response->assertHeader('Content-Type', 'application/json');
        $this->assertStringNotContainsString('<script>', $body);
        $this->assertStringNotContainsString('</script>', $body);
        $this->assertStringContainsString('\\u003Cscript\\u003E', $body);

        // Lossless, not sanitised: a client decoding the body gets the name
        // back exactly as the provider gave it.
        $this->assertSame($hostile, $response->json('data.origin.display_name'));
    }
}
