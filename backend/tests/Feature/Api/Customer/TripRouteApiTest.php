<?php

declare(strict_types=1);

namespace Tests\Feature\Api\Customer;

use App\Enums\RouteStatus;
use App\Models\Trip;
use App\Models\TripRoute;
use App\Models\User;
use App\Services\Routing\RouteCalculationService;
use App\Services\Routing\RouteFailureKind;
use App\Services\Routing\RouteProvider;
use App\Support\Route\PolylineCodec;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Support\CustomerFactory;
use Tests\TestCase;
use Tests\Unit\RecordingRouteProvider;

/**
 * The route endpoints as a client sees them.
 *
 * The three things this file exists to prove: that a customer cannot supply a
 * distance, a duration, a polyline or a selection and have the server believe
 * it; that opening a screen does not spend money; and that a trip is never left
 * saying READY over nothing.
 */
final class TripRouteApiTest extends TestCase
{
    use RefreshDatabase;

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

    /** Swaps the routing provider, and the service that captured it. */
    private function useProvider(RouteProvider $provider): RouteProvider
    {
        $this->app->instance(RouteProvider::class, $provider);
        $this->app->forgetInstance(RouteCalculationService::class);

        return $provider;
    }

    private function trip(): Trip
    {
        return Trip::factory()->ownedBy($this->rahul)->create();
    }

    private function calculateUrl(Trip $trip): string
    {
        return "/api/v1/customer/trips/{$trip->uuid}/route/calculate";
    }

    // --- calculating --------------------------------------------------------

    public function test_a_route_is_calculated_and_returned_with_its_trip(): void
    {
        $this->useProvider(new RecordingRouteProvider);
        $trip = $this->trip();

        $this->asRahul()->postJson($this->calculateUrl($trip))
            ->assertOk()
            ->assertJsonPath('data.trip.route_status', 'READY')
            ->assertJsonPath('data.routes.0.distance_meters', 278_000)
            ->assertJsonPath('data.routes.0.duration_seconds', 16_200)
            ->assertJsonPath('data.routes.0.traffic_duration_seconds', 17_100)
            ->assertJsonPath('data.routes.0.traffic_delay_seconds', 900)
            ->assertJsonPath('data.routes.0.is_selected', true)
            ->assertJsonPath('data.routes.0.is_recommended', true);
    }

    public function test_distance_and_duration_travel_as_numbers_not_words(): void
    {
        $this->useProvider(new RecordingRouteProvider);

        $route = $this->asRahul()->postJson($this->calculateUrl($this->trip()))->json('data.routes.0');

        // A client handed "278 km" cannot show miles, cannot sum two legs and
        // cannot re-render in another language.
        $this->assertIsInt($route['distance_meters']);
        $this->assertIsInt($route['duration_seconds']);
        $this->assertArrayNotHasKey('distance_text', $route);
    }

    public function test_the_geometry_that_comes_back_actually_decodes(): void
    {
        $this->useProvider(new RecordingRouteProvider);

        $route = $this->asRahul()->postJson($this->calculateUrl($this->trip()))->json('data.routes.0');

        $points = PolylineCodec::decode($route['encoded_polyline']);

        // Asserting the string is present proves nothing. A client is about to
        // draw this.
        $this->assertGreaterThan(1, count($points));
        $this->assertEqualsWithDelta(28.5494, $points[0][0], 0.01);
    }

    public function test_a_route_carries_the_bounds_a_camera_and_a_corridor_need(): void
    {
        $this->useProvider(new RecordingRouteProvider);

        $bounds = $this->asRahul()->postJson($this->calculateUrl($this->trip()))->json('data.routes.0.bounds');

        $this->assertSame(['north', 'south', 'east', 'west'], array_keys($bounds));
    }

    public function test_alternatives_are_returned_in_provider_order(): void
    {
        $this->useProvider(new RecordingRouteProvider(alternatives: 3));

        $routes = $this->asRahul()->postJson($this->calculateUrl($this->trip()))->json('data.routes');

        $this->assertCount(3, $routes);
        $this->assertSame([0, 1, 2], array_column($routes, 'provider_route_index'));
        $this->assertSame([true, false, false], array_column($routes, 'is_selected'));
    }

    public function test_a_second_calculation_does_not_call_the_provider_again(): void
    {
        $provider = $this->useProvider(new RecordingRouteProvider);
        $trip = $this->trip();

        $this->asRahul()->postJson($this->calculateUrl($trip))->assertOk();
        $this->asRahul()->postJson($this->calculateUrl($trip))->assertOk();

        // The largest cost risk in this module: a screen that recalculates on
        // every open.
        $this->assertSame(1, $provider->calls);
    }

    public function test_rapid_repeated_calculation_leaves_one_route_set(): void
    {
        $provider = $this->useProvider(new RecordingRouteProvider(alternatives: 3));
        $trip = $this->trip();

        for ($i = 0; $i < 6; $i++) {
            $this->asRahul()->postJson($this->calculateUrl($trip))->assertOk();
        }

        $this->assertSame(1, $provider->calls);
        $this->assertSame(3, TripRoute::query()->forTrip($trip)->count());
        $this->assertSame(1, TripRoute::query()->forTrip($trip)->where('is_selected', true)->count());
    }

    public function test_a_refresh_asks_again(): void
    {
        $provider = $this->useProvider(new RecordingRouteProvider);
        $trip = $this->trip();

        $this->asRahul()->postJson($this->calculateUrl($trip))->assertOk();
        $this->asRahul()->postJson($this->calculateUrl($trip).'?refresh=1')->assertOk();

        $this->assertSame(2, $provider->calls);
    }

    // --- listing ------------------------------------------------------------

    public function test_listing_routes_never_calls_the_provider(): void
    {
        $provider = $this->useProvider(new RecordingRouteProvider);
        $trip = $this->trip();

        $this->asRahul()->getJson("/api/v1/customer/trips/{$trip->uuid}/routes")
            ->assertOk()
            ->assertJsonPath('data.trip.route_status', 'NOT_CALCULATED')
            ->assertJsonCount(0, 'data.routes');

        // A GET that can spend money is a GET that spends money on every rebuild.
        $this->assertSame(0, $provider->calls);
    }

    public function test_listing_returns_what_was_calculated(): void
    {
        $this->useProvider(new RecordingRouteProvider(alternatives: 2));
        $trip = $this->trip();

        $this->asRahul()->postJson($this->calculateUrl($trip))->assertOk();

        $this->asRahul()->getJson("/api/v1/customer/trips/{$trip->uuid}/routes")
            ->assertOk()
            ->assertJsonCount(2, 'data.routes');
    }

    // --- selecting ----------------------------------------------------------

    public function test_an_alternative_can_be_selected(): void
    {
        $this->useProvider(new RecordingRouteProvider(alternatives: 3));
        $trip = $this->trip();

        $routes = $this->asRahul()->postJson($this->calculateUrl($trip))->json('data.routes');
        $second = $routes[1]['route_id'];

        $updated = $this->asRahul()
            ->postJson("/api/v1/customer/trips/{$trip->uuid}/routes/{$second}/select")
            ->assertOk()
            ->json('data.routes');

        $this->assertSame([false, true, false], array_column($updated, 'is_selected'));
    }

    public function test_exactly_one_route_is_ever_selected(): void
    {
        $this->useProvider(new RecordingRouteProvider(alternatives: 3));
        $trip = $this->trip();

        $routes = $this->asRahul()->postJson($this->calculateUrl($trip))->json('data.routes');

        // Switch back and forth: the final state must have exactly one.
        foreach ([1, 2, 0, 2, 1] as $index) {
            $this->asRahul()
                ->postJson("/api/v1/customer/trips/{$trip->uuid}/routes/{$routes[$index]['route_id']}/select")
                ->assertOk();
        }

        $this->assertSame(1, TripRoute::query()->forTrip($trip)->where('is_selected', true)->count());
        $this->assertSame(
            $routes[1]['route_id'],
            TripRoute::query()->forTrip($trip)->where('is_selected', true)->first()->uuid,
        );
    }

    public function test_selecting_the_already_selected_route_is_not_an_error(): void
    {
        $this->useProvider(new RecordingRouteProvider(alternatives: 2));
        $trip = $this->trip();

        $routes = $this->asRahul()->postJson($this->calculateUrl($trip))->json('data.routes');

        // What a double tap looks like.
        $this->asRahul()
            ->postJson("/api/v1/customer/trips/{$trip->uuid}/routes/{$routes[0]['route_id']}/select")
            ->assertOk();

        $this->assertSame(1, TripRoute::query()->forTrip($trip)->where('is_selected', true)->count());
    }

    public function test_selecting_a_route_that_does_not_exist_is_a_404(): void
    {
        $this->useProvider(new RecordingRouteProvider);
        $trip = $this->trip();
        $this->asRahul()->postJson($this->calculateUrl($trip))->assertOk();

        $this->asRahul()
            ->postJson("/api/v1/customer/trips/{$trip->uuid}/routes/00000000-0000-0000-0000-000000000000/select")
            ->assertNotFound()
            ->assertJsonPath('error.code', 'ROUTE_NOT_FOUND');
    }

    public function test_selecting_before_anything_is_calculated_is_refused(): void
    {
        $this->useProvider(new RecordingRouteProvider);
        $trip = $this->trip();

        $this->asRahul()
            ->postJson("/api/v1/customer/trips/{$trip->uuid}/routes/00000000-0000-0000-0000-000000000000/select")
            ->assertNotFound();
    }

    // --- what a client may not send -----------------------------------------

    public function test_a_client_cannot_dictate_a_distance_a_duration_or_a_polyline(): void
    {
        $this->useProvider(new RecordingRouteProvider);
        $trip = $this->trip();

        $this->asRahul()->postJson($this->calculateUrl($trip), [
            // Everything a caller might hope to seed, sent together.
            'distance_meters' => 1,
            'duration_seconds' => 1,
            'traffic_duration_seconds' => 1,
            'encoded_polyline' => 'tamper',
            'is_selected' => true,
            'is_recommended' => false,
            'provider' => 'attacker',
            'route_status' => 'READY',
            'summary' => 'via my house',
        ])->assertOk();

        $route = TripRoute::query()->forTrip($trip)->firstOrFail();

        // Every value came from the provider, by way of the backend.
        $this->assertSame(278_000, $route->distance_meters);
        $this->assertSame(16_200, $route->duration_seconds);
        $this->assertSame('recording', $route->provider);
        $this->assertSame('NH 48', $route->summary);
        $this->assertNotSame('tamper', $route->encoded_polyline);
    }

    public function test_a_client_cannot_declare_a_trip_routed(): void
    {
        $this->useProvider(new RecordingRouteProvider)->findsNothing = true;
        $trip = $this->trip();

        $this->asRahul()->postJson($this->calculateUrl($trip), [
            'route_status' => 'READY',
            'status' => 'READY',
        ])->assertStatus(422)->assertJsonPath('error.code', 'ROUTE_NO_ROUTE_FOUND');

        // The provider said there is no route. A body that says otherwise
        // changes nothing.
        $this->assertSame(RouteStatus::NoRoute, $trip->refresh()->route_status);
    }

    public function test_a_client_cannot_select_a_route_by_sending_a_flag(): void
    {
        $this->useProvider(new RecordingRouteProvider(alternatives: 2));
        $trip = $this->trip();

        $routes = $this->asRahul()->postJson($this->calculateUrl($trip))->json('data.routes');

        $this->asRahul()->postJson("/api/v1/customer/trips/{$trip->uuid}/routes/{$routes[1]['route_id']}/select", [
            'is_selected' => false,
            'trip_id' => 99999,
        ])->assertOk();

        // The path said which route. The body said nothing that mattered.
        $selected = TripRoute::query()->forTrip($trip)->where('is_selected', true)->firstOrFail();
        $this->assertSame($routes[1]['route_id'], $selected->uuid);
    }

    // --- failures reach the client as codes ---------------------------------

    public function test_no_route_reaches_the_client_as_its_own_code(): void
    {
        $this->useProvider(new RecordingRouteProvider)->findsNothing = true;

        $this->asRahul()->postJson($this->calculateUrl($this->trip()))
            ->assertStatus(422)
            ->assertJsonPath('error.code', 'ROUTE_NO_ROUTE_FOUND');
    }

    public function test_a_provider_failure_says_nothing_about_our_quota_or_our_key(): void
    {
        $this->useProvider(new RecordingRouteProvider)->failWith = RouteFailureKind::RateLimited;

        $response = $this->asRahul()->postJson($this->calculateUrl($this->trip()))
            ->assertStatus(429)
            ->assertJsonPath('error.code', 'ROUTE_PROVIDER_RATE_LIMITED');

        $body = (string) $response->getContent();
        $this->assertStringNotContainsString('quota', $body);
        $this->assertStringNotContainsString('AIza', $body);
        $this->assertStringNotContainsString('fotg-123', $body);
    }

    public function test_a_timeout_reaches_the_client_as_a_timeout(): void
    {
        $this->useProvider(new RecordingRouteProvider)->failWith = RouteFailureKind::Timeout;

        $this->asRahul()->postJson($this->calculateUrl($this->trip()))
            ->assertStatus(504)
            ->assertJsonPath('error.code', 'ROUTE_TIMEOUT');
    }

    public function test_recovery_after_a_failure_produces_a_ready_route(): void
    {
        $trip = $this->trip();

        // The provider is switched rather than replaced: Laravel caches a
        // resolved controller on the Route object, and routes outlive one
        // request inside a test process — so a second `$app->instance()` here
        // would change what the container returns and not what the controller
        // already holds, and this test would pass against nothing.
        $provider = $this->useProvider(new RecordingRouteProvider);

        $provider->failWith = RouteFailureKind::Unavailable;
        $this->asRahul()->postJson($this->calculateUrl($trip))->assertStatus(503);
        $this->assertSame(RouteStatus::Failed, $trip->refresh()->route_status);

        $provider->failWith = null;
        $this->asRahul()->postJson($this->calculateUrl($trip))
            ->assertOk()
            ->assertJsonPath('data.trip.route_status', 'READY')
            ->assertJsonPath('data.routes.0.distance_meters', 278_000);
    }

    // --- authentication -----------------------------------------------------

    public function test_every_route_endpoint_needs_a_token(): void
    {
        $this->useProvider(new RecordingRouteProvider);
        $trip = $this->trip();
        $this->flushHeaders();

        $this->getJson("/api/v1/customer/trips/{$trip->uuid}/routes")->assertUnauthorized();
        $this->postJson($this->calculateUrl($trip))->assertUnauthorized();
        $this->postJson("/api/v1/customer/trips/{$trip->uuid}/routes/x/select")->assertUnauthorized();
    }

    // --- the trip payload ---------------------------------------------------

    public function test_a_trip_carries_its_selected_route_summary_once_calculated(): void
    {
        $this->useProvider(new RecordingRouteProvider);
        $trip = $this->trip();

        $this->asRahul()->getJson("/api/v1/customer/trips/{$trip->uuid}")
            ->assertOk()
            ->assertJsonPath('data.selected_route', null);

        $this->asRahul()->postJson($this->calculateUrl($trip))->assertOk();

        $this->asRahul()->getJson("/api/v1/customer/trips/{$trip->uuid}")
            ->assertOk()
            ->assertJsonPath('data.selected_route.distance_meters', 278_000)
            ->assertJsonPath('data.selected_route.duration_seconds', 16_200);
    }

    public function test_a_trip_summary_carries_no_geometry(): void
    {
        $this->useProvider(new RecordingRouteProvider);
        $trip = $this->trip();
        $this->asRahul()->postJson($this->calculateUrl($trip))->assertOk();

        $summary = $this->asRahul()->getJson("/api/v1/customer/trips/{$trip->uuid}")->json('data.selected_route');

        // Ten journeys in a list must not be ten polylines.
        $this->assertArrayNotHasKey('encoded_polyline', $summary);
    }

    public function test_a_trip_whose_endpoints_moved_reports_no_route_summary(): void
    {
        $this->useProvider(new RecordingRouteProvider);
        $trip = $this->trip();
        $this->asRahul()->postJson($this->calculateUrl($trip))->assertOk();

        Trip::query()->whereKey($trip->getKey())->update(['destination_latitude' => 30.7412]);

        // The most convincing wrong number this product could show is a real
        // distance for a journey nobody is taking.
        $this->asRahul()->getJson("/api/v1/customer/trips/{$trip->uuid}")
            ->assertOk()
            ->assertJsonPath('data.selected_route', null);
    }
}
