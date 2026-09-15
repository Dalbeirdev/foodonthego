<?php

declare(strict_types=1);

namespace Tests\Feature\Api\Customer;

use App\Models\Trip;
use App\Models\TripRoute;
use App\Models\User;
use App\Services\Routing\RouteCalculationService;
use App\Services\Routing\RouteProvider;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\Support\CustomerFactory;
use Tests\TestCase;
use Tests\Unit\RecordingRouteProvider;

/**
 * Rahul, Ananya, and everything Rahul must not be able to do.
 *
 * A route is location data about a person: where they are going, when, and by
 * which road. The rules are Module 05's, carried forward — every refusal is the
 * same 404, and none of them says anything about her journey.
 *
 * The one this module adds is *calculating* on somebody else's trip. It would
 * not merely leak: it would spend our money doing it.
 */
final class TripRouteOwnershipTest extends TestCase
{
    use RefreshDatabase;

    private User $rahul;

    private User $ananya;

    private string $rahulToken;

    private string $ananyaToken;

    private RecordingRouteProvider $provider;

    protected function setUp(): void
    {
        parent::setUp();

        $this->rahul = CustomerFactory::rahul();
        $this->ananya = CustomerFactory::ananya();
        $this->rahulToken = CustomerFactory::tokenFor($this->rahul);
        $this->ananyaToken = CustomerFactory::tokenFor($this->ananya);

        $this->provider = new RecordingRouteProvider(alternatives: 2);
        $this->app->instance(RouteProvider::class, $this->provider);
        $this->app->forgetInstance(RouteCalculationService::class);
    }

    private function as(string $token): self
    {
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', 'Bearer '.$token);
    }

    /** Ananya's trip, with a calculated and selected route. */
    private function herRoutedTrip(): Trip
    {
        $trip = Trip::factory()->ownedBy($this->ananya)->create([
            'origin_name' => 'DLF Cyber City',
            'origin_city' => 'Gurugram',
            'destination_name' => 'Sector 17 Plaza',
            'destination_city' => 'Chandigarh',
        ]);

        $this->as($this->ananyaToken)
            ->postJson("/api/v1/customer/trips/{$trip->uuid}/route/calculate")
            ->assertOk();

        return $trip->refresh();
    }

    public function test_rahul_cannot_calculate_a_route_for_ananyas_trip(): void
    {
        $hers = Trip::factory()->ownedBy($this->ananya)->create();
        $before = $this->provider->calls;

        $this->as($this->rahulToken)
            ->postJson("/api/v1/customer/trips/{$hers->uuid}/route/calculate")
            ->assertNotFound()
            ->assertJsonPath('error.code', 'TRIP_NOT_FOUND');

        // Refused before the provider was troubled. An ownership hole here would
        // be a leak *and* a bill.
        $this->assertSame($before, $this->provider->calls);
        $this->assertSame(0, TripRoute::query()->forTrip($hers)->count());
    }

    public function test_rahul_cannot_list_ananyas_routes(): void
    {
        $hers = $this->herRoutedTrip();

        $this->as($this->rahulToken)
            ->getJson("/api/v1/customer/trips/{$hers->uuid}/routes")
            ->assertNotFound()
            ->assertJsonPath('error.code', 'TRIP_NOT_FOUND');
    }

    public function test_rahul_cannot_select_a_route_on_ananyas_trip(): void
    {
        $hers = $this->herRoutedTrip();
        $herRoute = TripRoute::query()->forTrip($hers)->firstOrFail();

        $this->as($this->rahulToken)
            ->postJson("/api/v1/customer/trips/{$hers->uuid}/routes/{$herRoute->uuid}/select")
            ->assertNotFound();

        // Her selection is untouched.
        $this->assertTrue($herRoute->refresh()->is_selected);
    }

    public function test_rahul_cannot_attach_her_route_to_his_own_trip(): void
    {
        $hers = $this->herRoutedTrip();
        $herRoute = TripRoute::query()->forTrip($hers)->firstOrFail();

        $his = Trip::factory()->ownedBy($this->rahul)->create();
        $this->as($this->rahulToken)
            ->postJson("/api/v1/customer/trips/{$his->uuid}/route/calculate")
            ->assertOk();

        // His trip, her route id. The route is looked up *within the trip*, so
        // there is no branch that could be reached with her row in hand.
        $this->as($this->rahulToken)
            ->postJson("/api/v1/customer/trips/{$his->uuid}/routes/{$herRoute->uuid}/select")
            ->assertNotFound()
            ->assertJsonPath('error.code', 'ROUTE_NOT_FOUND');

        $this->assertTrue($herRoute->refresh()->is_selected);
        $this->assertSame(
            0,
            TripRoute::query()->forTrip($his)->where('uuid', $herRoute->uuid)->count(),
        );
    }

    public function test_no_refusal_leaks_a_word_about_her_journey(): void
    {
        $hers = $this->herRoutedTrip();
        $herRoute = TripRoute::query()->forTrip($hers)->firstOrFail();

        $responses = [
            $this->as($this->rahulToken)->getJson("/api/v1/customer/trips/{$hers->uuid}/routes"),
            $this->as($this->rahulToken)->postJson("/api/v1/customer/trips/{$hers->uuid}/route/calculate"),
            $this->as($this->rahulToken)
                ->postJson("/api/v1/customer/trips/{$hers->uuid}/routes/{$herRoute->uuid}/select"),
        ];

        foreach ($responses as $response) {
            $body = (string) $response->getContent();

            foreach ([
                'Gurugram', 'Cyber City', 'Sector 17', 'Chandigarh',
                (string) $herRoute->distance_meters,
                $herRoute->encoded_polyline,
            ] as $secret) {
                $this->assertStringNotContainsString($secret, $body);
            }
        }
    }

    public function test_a_missing_trip_and_a_forbidden_one_are_indistinguishable(): void
    {
        $hers = Trip::factory()->ownedBy($this->ananya)->create();

        $forbidden = $this->as($this->rahulToken)
            ->postJson("/api/v1/customer/trips/{$hers->uuid}/route/calculate");

        $missing = $this->as($this->rahulToken)
            ->postJson('/api/v1/customer/trips/00000000-0000-0000-0000-000000000000/route/calculate');

        // A 403 for one and a 404 for the other is an oracle: it confirms which
        // ids are real.
        $this->assertSame($missing->status(), $forbidden->status());
        $this->assertSame($missing->json('error.code'), $forbidden->json('error.code'));
    }

    public function test_her_routes_never_appear_in_his_trip_list(): void
    {
        $this->herRoutedTrip();

        $his = Trip::factory()->ownedBy($this->rahul)->create();
        $this->as($this->rahulToken)
            ->postJson("/api/v1/customer/trips/{$his->uuid}/route/calculate")
            ->assertOk();

        $trips = $this->as($this->rahulToken)->getJson('/api/v1/customer/trips')->json('data');

        $this->assertCount(1, $trips);
        $this->assertSame($his->uuid, $trips[0]['id']);
    }

    public function test_the_database_refuses_two_selected_routes_on_one_trip(): void
    {
        $trip = Trip::factory()->ownedBy($this->rahul)->create();
        $this->as($this->rahulToken)
            ->postJson("/api/v1/customer/trips/{$trip->uuid}/route/calculate")
            ->assertOk();

        $unselected = TripRoute::query()->forTrip($trip)->where('is_selected', false)->firstOrFail();

        // The invariant lives in the schema, not only in a service somebody can
        // forget to call — a unique index over "the trip id, when selected".
        $this->expectException(QueryException::class);

        DB::table('trip_routes')->where('id', $unselected->id)->update(['is_selected' => true]);
    }

    public function test_deleting_a_trip_takes_its_routes_with_it(): void
    {
        $trip = Trip::factory()->ownedBy($this->rahul)->create();
        $this->as($this->rahulToken)
            ->postJson("/api/v1/customer/trips/{$trip->uuid}/route/calculate")
            ->assertOk();

        $this->assertSame(2, TripRoute::query()->forTrip($trip)->count());

        // A route has no existence away from its trip, and route geometry left
        // behind by an erasure is location data about somebody who has gone.
        $trip->delete();

        $this->assertSame(0, TripRoute::query()->where('trip_id', $trip->getKey())->count());
    }
}
