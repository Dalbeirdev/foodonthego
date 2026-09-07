<?php

declare(strict_types=1);

namespace Tests\Feature\Api\Customer;

use App\Enums\ApiErrorCode;
use App\Enums\RestaurantStatus;
use App\Enums\RouteStatus;
use App\Models\Restaurant;
use App\Models\Trip;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Cache;
use Tests\Support\CustomerFactory;
use Tests\Support\RestaurantFixtures;
use Tests\TestCase;

/**
 * The discovery endpoint as a client sees it.
 */
final class TripRestaurantApiTest extends TestCase
{
    use RefreshDatabase;

    private User $rahul;

    private string $token;

    private Trip $trip;

    protected function setUp(): void
    {
        parent::setUp();

        Cache::flush();

        $this->rahul = CustomerFactory::rahul();
        $this->token = CustomerFactory::tokenFor($this->rahul);
        $this->trip = RestaurantFixtures::tripWithSelectedRoute($this->rahul);
    }

    private function asRahul(): self
    {
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', 'Bearer '.$this->token);
    }

    private function url(?Trip $trip = null): string
    {
        return '/api/v1/customer/trips/'.($trip ?? $this->trip)->uuid.'/restaurants';
    }

    public function test_a_customer_gets_the_restaurants_on_their_route(): void
    {
        RestaurantFixtures::nearRoute(0.4, 800, 'Highway Spice Kitchen');

        $this->asRahul()->getJson($this->url())
            ->assertOk()
            ->assertJsonPath('data.restaurants.0.name', 'Highway Spice Kitchen')
            ->assertJsonPath('data.route.route_id', $this->trip->routes()->first()->uuid)
            ->assertJsonStructure(['data' => [
                'route' => ['route_id', 'distance_meters', 'duration_seconds', 'provider'],
                'restaurants' => [['id', 'name', 'location', 'cuisines', 'facilities', 'availability', 'route' => [
                    'proximity_meters',
                    'detour_distance_meters',
                    'detour_duration_seconds',
                    'distance_ahead_meters',
                    'time_ahead_seconds',
                    'requires_backtracking',
                ]]],
                'meta' => ['returned', 'candidates_considered', 'closed_only', 'from_cache'],
            ]]);
    }

    public function test_an_unauthenticated_call_reaches_no_restaurants(): void
    {
        $this->getJson($this->url())->assertUnauthorized();
    }

    public function test_a_trip_with_no_route_is_refused_with_its_own_code(): void
    {
        $bare = Trip::factory()->ownedBy($this->rahul)->create();

        $this->asRahul()->getJson($this->url($bare))
            ->assertStatus(409)
            ->assertJsonPath('error.code', ApiErrorCode::RouteNotReady->value);
    }

    public function test_a_trip_whose_endpoints_moved_is_refused_rather_than_searched(): void
    {
        RestaurantFixtures::nearRoute(0.4, 800, 'Beside The Old Road');

        // The customer edits the destination. The stored route now describes a
        // journey nobody is taking, and searching along it would recommend
        // restaurants on a road they are not driving.
        $this->trip->forceFill([
            'destination_latitude' => 19.0760,
            'destination_longitude' => 72.8777,
        ])->save();

        $this->asRahul()->getJson($this->url())
            ->assertStatus(409)
            ->assertJsonPath('error.code', ApiErrorCode::RouteNotReady->value);
    }

    public function test_a_route_that_is_not_ready_is_refused(): void
    {
        $this->trip->forceFill(['route_status' => RouteStatus::Failed])->save();

        $this->asRahul()->getJson($this->url())->assertStatus(409);
    }

    public function test_an_empty_result_is_a_success_not_an_error(): void
    {
        // Nothing on this road yet is a state the app renders, not a failure it
        // reports.
        $this->asRahul()->getJson($this->url())
            ->assertOk()
            ->assertJsonPath('data.restaurants', [])
            ->assertJsonPath('data.meta.returned', 0)
            ->assertJsonPath('data.meta.closed_only', false);
    }

    public function test_a_closed_only_result_says_so(): void
    {
        // The clock is pinned, and it has to be. This test used to run at
        // whatever time CI happened to start, and a restaurant opening at 02:00
        // local reads OPENING_SOON — correctly — for the half hour before that.
        // CI started at 20:02 UTC, which is 01:32 in Asia/Kolkata, 27 minutes
        // before the doors: the assertion failed and the code was right.
        //
        // 06:30 UTC is noon in Kolkata: hours from either edge of a 02:00–03:00
        // window, with no threshold anywhere near it.
        Carbon::setTestNow('2026-09-07 06:30:00');

        $restaurant = RestaurantFixtures::nearRoute(0.4, 800, 'Shut Cafe', open: false);
        RestaurantFixtures::openDaily($restaurant, '02:00:00', '03:00:00');

        $this->asRahul()->getJson($this->url())
            ->assertOk()
            ->assertJsonPath('data.meta.closed_only', true)
            ->assertJsonPath('data.restaurants.0.availability', 'CLOSED');
    }

    public function test_a_restaurant_about_to_open_says_opening_soon(): void
    {
        // The instant that broke the test above, kept as coverage rather than
        // thrown away. A shut restaurant half an hour from opening is not the
        // same news as one shut for the night, and a customer deciding where to
        // stop needs the difference.
        Carbon::setTestNow('2026-09-07 20:02:25');

        $restaurant = RestaurantFixtures::nearRoute(0.4, 800, 'Shut Cafe', open: false);
        RestaurantFixtures::openDaily($restaurant, '02:00:00', '03:00:00');

        $this->asRahul()->getJson($this->url())
            ->assertOk()
            // Still nothing they can order from, so the banner stands.
            ->assertJsonPath('data.meta.closed_only', true)
            ->assertJsonPath('data.restaurants.0.availability', 'OPENING_SOON');
    }

    public function test_a_suspended_restaurant_is_never_returned(): void
    {
        RestaurantFixtures::nearRoute(0.4, 800, 'Good One');

        Restaurant::factory()->discoverable()->suspended()->named('Suspended Dhaba')
            ->at(...RestaurantFixtures::offset(
                0.42, 800, RestaurantFixtures::ORIGIN, RestaurantFixtures::DESTINATION,
            ))
            ->create();

        $response = $this->asRahul()->getJson($this->url())->assertOk();

        $this->assertSame(['Good One'], array_column($response->json('data.restaurants'), 'name'));
        $response->assertJsonMissing(['name' => 'Suspended Dhaba']);
    }

    public function test_the_response_carries_no_private_restaurant_data(): void
    {
        $restaurant = RestaurantFixtures::nearRoute(0.4, 800, 'Highway Spice Kitchen');

        $restaurant->forceFill([
            'owner_name' => 'Meera Kulkarni',
            'owner_phone' => '+919812345678',
            'owner_email' => 'owner@example.test',
            'tax_identifier' => '07AABCU9603R1ZM',
            'bank_account_reference' => 'HDFC-XXXX-4412',
            'commission_rate' => 18.50,
            'internal_notes' => 'Late on settlements. Watch.',
        ])->save();

        $body = $this->asRahul()->getJson($this->url())->assertOk()->content();

        // Asserted against the raw body rather than against parsed keys: a leak
        // nested three levels down inside a relation would still be a leak, and
        // a structural assertion would not see it.
        foreach ([
            'Meera Kulkarni',
            '+919812345678',
            'owner@example.test',
            '07AABCU9603R1ZM',
            'HDFC-XXXX-4412',
            '18.50',
            'Late on settlements',
            'owner_name',
            'owner_phone',
            'tax_identifier',
            'bank_account_reference',
            'commission_rate',
            'internal_notes',
        ] as $secret) {
            $this->assertStringNotContainsString($secret, $body, "leaked: {$secret}");
        }
    }

    public function test_no_internal_database_key_is_exposed(): void
    {
        RestaurantFixtures::nearRoute(0.4, 800, 'Highway Spice Kitchen');

        $restaurant = $this->asRahul()->getJson($this->url())
            ->assertOk()
            ->json('data.restaurants.0');

        // The uuid, not the sequential id: a numeric key is an invitation to
        // enumerate the partner list.
        $this->assertMatchesRegularExpression(
            '/^[0-9a-f-]{36}$/',
            $restaurant['id'],
        );
        $this->assertArrayNotHasKey('restaurant_id', $restaurant);
    }

    public function test_a_rating_that_does_not_exist_is_null_rather_than_invented(): void
    {
        RestaurantFixtures::nearRoute(0.4, 800, 'Unrated Kitchen');

        $restaurant = $this->asRahul()->getJson($this->url())
            ->assertOk()
            ->json('data.restaurants.0');

        // There is no reviews module. A hopeful 4.5 here would be a fabrication
        // a customer would act on.
        $this->assertNull($restaurant['rating']);
        $this->assertNull($restaurant['review_count']);
    }

    public function test_cuisines_and_facilities_come_back_as_declared(): void
    {
        RestaurantFixtures::nearRoute(
            0.4,
            800,
            'Highway Spice Kitchen',
            cuisines: ['North Indian', 'Vegetarian'],
            facilities: ['Parking', 'Restroom'],
        );

        $restaurant = $this->asRahul()->getJson($this->url())
            ->assertOk()
            ->json('data.restaurants.0');

        // In the order the operator declared them.
        $this->assertSame(['North Indian', 'Vegetarian'], $restaurant['cuisines']);
        $this->assertSame(['Parking', 'Restroom'], $restaurant['facilities']);
    }

    public function test_the_second_call_is_served_from_cache(): void
    {
        RestaurantFixtures::nearRoute(0.4, 800, 'Highway Spice Kitchen');

        $this->asRahul()->getJson($this->url())
            ->assertOk()
            ->assertJsonPath('data.meta.from_cache', false);

        $this->asRahul()->getJson($this->url())
            ->assertOk()
            ->assertJsonPath('data.meta.from_cache', true);
    }

    public function test_measurements_are_numbers_not_formatted_strings(): void
    {
        RestaurantFixtures::nearRoute(0.4, 800, 'Highway Spice Kitchen');

        $route = $this->asRahul()->getJson($this->url())
            ->assertOk()
            ->json('data.restaurants.0.route');

        // Metres and seconds, so a client can format them for its own locale —
        // and so "1.8 km" is never something the server decided.
        $this->assertIsInt($route['proximity_meters']);
        $this->assertIsInt($route['distance_ahead_meters']);
        $this->assertIsInt($route['time_ahead_seconds']);
    }

    public function test_the_meta_block_reports_what_the_search_cost(): void
    {
        RestaurantFixtures::nearRoute(0.4, 800, 'Near');
        RestaurantFixtures::nearRoute(0.5, 45_000, 'Far');

        $meta = $this->asRahul()->getJson($this->url())->assertOk()->json('data.meta');

        $this->assertSame(1, $meta['returned']);
        $this->assertGreaterThanOrEqual(1, $meta['candidates_considered']);
        // The corridor the client was actually searched with, so an empty screen
        // can say "within 5 km of your route" rather than guessing.
        $this->assertSame(
            (int) config('foodonthego.discovery.corridor_metres'),
            $meta['corridor_meters'],
        );
    }

    public function test_the_endpoint_is_rate_limited(): void
    {
        config(['foodonthego.rate_limits.discovery' => 3]);

        for ($i = 0; $i < 3; $i++) {
            $this->asRahul()->getJson($this->url())->assertOk();
        }

        // The most expensive endpoint in the application. Without this, a
        // looping client spends the routing budget.
        $this->asRahul()->getJson($this->url())->assertStatus(429);
    }

    public function test_a_restaurant_status_change_is_reflected_immediately(): void
    {
        $restaurant = RestaurantFixtures::nearRoute(0.4, 800, 'Now You See Me');

        $this->asRahul()->getJson($this->url())
            ->assertOk()
            ->assertJsonPath('data.meta.returned', 1);

        $restaurant->forceFill(['status' => RestaurantStatus::Suspended])->save();

        // Mandatory: a warm cache must not keep a suspended restaurant visible.
        $this->asRahul()->getJson($this->url())
            ->assertOk()
            ->assertJsonPath('data.meta.returned', 0);
    }
}
