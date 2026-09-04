<?php

declare(strict_types=1);

namespace Tests\Feature\Api\Customer;

use App\Models\Trip;
use App\Models\User;
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\Support\CustomerFactory;
use Tests\TestCase;

/**
 * The mandatory IDOR matrix for journeys.
 *
 * Rahul is authenticated throughout and attacks Ananya's journey by its real
 * uuid. Every attempt must be refused, must leak nothing about the journey, and
 * must leave Ananya's data byte-identical.
 *
 * The last two tests cover the subtler surface this module adds: a journey is
 * planned *from* a saved address, so "plan a journey from somebody else's saved
 * address" is an ownership attack against Module 04 through a Module 05
 * endpoint.
 */
final class TripOwnershipTest extends TestCase
{
    use RefreshDatabase;

    private const BASE = '/api/v1/customer/trips';

    private User $rahul;

    private User $ananya;

    private string $rahulToken;

    private string $ananyaToken;

    private Trip $ananyasTrip;

    protected function setUp(): void
    {
        parent::setUp();

        $this->rahul = CustomerFactory::rahul();
        $this->ananya = CustomerFactory::ananya();
        $this->rahulToken = CustomerFactory::tokenFor($this->rahul);
        $this->ananyaToken = CustomerFactory::tokenFor($this->ananya);

        $this->ananyasTrip = Trip::factory()->ownedBy($this->ananya)->create([
            'origin_label' => 'Ananya Home',
            'origin_formatted_address' => 'Sector 44, Gurugram, Haryana',
            'origin_city' => 'Gurugram',
            'destination_label' => 'Chandigarh',
            'destination_formatted_address' => 'Sector 17, Chandigarh',
            'destination_city' => 'Chandigarh',
            'note' => 'Visiting my parents',
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
        return self::BASE.'/'.$this->ananyasTrip->uuid;
    }

    public function test_rahul_cannot_read_ananyas_journey(): void
    {
        $response = $this->asRahul()->getJson($this->target());

        $response->assertNotFound()->assertJsonPath('error.code', 'TRIP_NOT_FOUND');

        // Nothing about the journey may appear anywhere in the body — not the
        // cities, not the labels, not the note.
        $body = $response->getContent();
        foreach (['Gurugram', 'Chandigarh', 'Ananya Home', 'Visiting my parents'] as $secret) {
            $this->assertStringNotContainsString($secret, (string) $body);
        }
    }

    public function test_rahul_cannot_change_ananyas_journey(): void
    {
        $this->asRahul()->patchJson($this->target(), ['traveller_count' => 9])
            ->assertNotFound()
            ->assertJsonPath('error.code', 'TRIP_NOT_FOUND');

        $this->assertSame(1, $this->ananyasTrip->fresh()?->traveller_count);
    }

    public function test_rahul_cannot_cancel_ananyas_journey(): void
    {
        $this->asRahul()->postJson($this->target().'/cancel', ['reason' => 'Not mine to cancel'])
            ->assertNotFound()
            ->assertJsonPath('error.code', 'TRIP_NOT_FOUND');

        $trip = $this->ananyasTrip->fresh();
        $this->assertNotNull($trip);
        $this->assertSame('PLANNED', $trip->status->value);
        $this->assertNull($trip->cancelled_at);
    }

    public function test_rahul_cannot_delete_ananyas_journey(): void
    {
        // There is no DELETE at all, which is the strongest possible answer.
        $this->asRahul()->deleteJson($this->target())->assertStatus(405);

        $this->assertNotNull($this->ananyasTrip->fresh());
    }

    public function test_ananyas_journey_is_untouched_after_every_attempt(): void
    {
        $before = $this->ananyasTrip->fresh()?->toArray();

        $this->asRahul()->getJson($this->target());
        $this->asRahul()->patchJson($this->target(), ['traveller_count' => 9, 'note' => 'changed']);
        $this->asRahul()->postJson($this->target().'/cancel');
        $this->asRahul()->deleteJson($this->target());

        $this->assertEquals($before, $this->ananyasTrip->fresh()?->toArray());
    }

    public function test_a_journey_that_does_not_exist_answers_identically(): void
    {
        $missing = $this->asRahul()->getJson(self::BASE.'/'.Str::uuid());
        $notMine = $this->asRahul()->getJson($this->target());

        $missing->assertNotFound();
        $notMine->assertNotFound();

        // Identical code and message. Only the request id differs, and that is
        // per-request by design.
        $this->assertSame($missing->json('error.code'), $notMine->json('error.code'));
        $this->assertSame($missing->json('error.message'), $notMine->json('error.message'));
    }

    public function test_a_customer_id_in_the_body_does_not_change_ownership(): void
    {
        $response = $this->asRahul()->postJson(self::BASE, [
            'customer_id' => $this->ananya->getKey(),
            'origin' => ['label' => 'Home', 'city' => 'New Delhi', 'country_code' => 'IN'],
            'destination' => ['label' => 'Agra', 'city' => 'Agra', 'country_code' => 'IN'],
            'departure_at' => CarbonImmutable::now()->addDay()->toIso8601String(),
        ])->assertCreated();

        $trip = Trip::query()->where('uuid', $response->json('data.id'))->firstOrFail();

        // The injected id validated fine, was never read, and the journey belongs
        // to the caller.
        $this->assertSame($this->rahul->getKey(), $trip->customer_id);
    }

    public function test_a_status_in_the_body_cannot_set_the_lifecycle(): void
    {
        $response = $this->asRahul()->postJson(self::BASE, [
            'status' => 'CANCELLED',
            'cancelled_at' => CarbonImmutable::now()->toIso8601String(),
            'cancellation_reason' => 'injected',
            'origin' => ['label' => 'Home', 'city' => 'New Delhi', 'country_code' => 'IN'],
            'destination' => ['label' => 'Agra', 'city' => 'Agra', 'country_code' => 'IN'],
            'departure_at' => CarbonImmutable::now()->addDay()->toIso8601String(),
        ])->assertCreated();

        $trip = Trip::query()->where('uuid', $response->json('data.id'))->firstOrFail();

        $this->assertSame('PLANNED', $trip->status->value);
        $this->assertNull($trip->cancelled_at);
        $this->assertNull($trip->cancellation_reason);
    }

    public function test_a_status_in_a_patch_body_cannot_cancel_a_journey(): void
    {
        $mine = Trip::factory()->ownedBy($this->rahul)->create();

        $this->asRahul()->patchJson(self::BASE.'/'.$mine->uuid, [
            'status' => 'CANCELLED',
            'cancelled_at' => CarbonImmutable::now()->toIso8601String(),
        ])->assertOk();

        $this->assertSame('PLANNED', $mine->fresh()?->status->value);
    }

    public function test_planning_a_journey_from_another_customers_saved_address_is_refused(): void
    {
        $ananyasAddress = $this->as($this->ananyaToken)->postJson('/api/v1/customer/addresses', [
            'type' => 'HOME',
            'label' => 'Ananya Home',
            'address_line_1' => '9 Sector 44',
            'city' => 'Gurugram',
            'state' => 'Haryana',
            'postal_code' => '122003',
            'country_code' => 'IN',
        ])->json('data.id');

        $response = $this->asRahul()->postJson(self::BASE, [
            'origin' => ['address_id' => $ananyasAddress],
            'destination' => ['label' => 'Agra', 'city' => 'Agra', 'country_code' => 'IN'],
            'departure_at' => CarbonImmutable::now()->addDay()->toIso8601String(),
        ]);

        // The same 404 a direct read of that address gives. Crucially *not* a
        // validation error saying the address exists but is not yours.
        $response->assertNotFound()->assertJsonPath('error.code', 'ADDRESS_NOT_FOUND');
        $this->assertStringNotContainsString('Gurugram', (string) $response->getContent());

        $this->assertSame(0, Trip::query()->where('customer_id', $this->rahul->getKey())->count());
    }

    public function test_updating_a_journey_onto_another_customers_saved_address_is_refused(): void
    {
        $mine = Trip::factory()->ownedBy($this->rahul)->create();

        $ananyasAddress = $this->as($this->ananyaToken)->postJson('/api/v1/customer/addresses', [
            'type' => 'WORK',
            'label' => 'Ananya Work',
            'address_line_1' => 'Cyber City',
            'city' => 'Gurugram',
            'state' => 'Haryana',
            'postal_code' => '122002',
            'country_code' => 'IN',
        ])->json('data.id');

        $this->asRahul()->patchJson(self::BASE.'/'.$mine->uuid, [
            'destination' => ['address_id' => $ananyasAddress],
        ])->assertNotFound()->assertJsonPath('error.code', 'ADDRESS_NOT_FOUND');

        $this->assertSame('Jaipur', $mine->fresh()?->destination_city);
    }

    public function test_each_customer_sees_only_their_own_journeys(): void
    {
        Trip::factory()->count(2)->ownedBy($this->rahul)->create();

        $this->asRahul()->getJson(self::BASE.'?scope=all')->assertOk()->assertJsonCount(2, 'data');
        $this->as($this->ananyaToken)->getJson(self::BASE.'?scope=all')->assertOk()->assertJsonCount(1, 'data');
    }

    public function test_next_never_returns_another_customers_journey(): void
    {
        // Rahul has none of his own; Ananya's is the only journey in the database.
        $this->asRahul()->getJson(self::BASE.'/next')->assertOk()->assertJsonPath('data', null);
    }
}
