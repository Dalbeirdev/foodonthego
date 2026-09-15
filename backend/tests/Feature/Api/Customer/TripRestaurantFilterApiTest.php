<?php

declare(strict_types=1);

namespace Tests\Feature\Api\Customer;

use App\Enums\ApiErrorCode;
use App\Models\Restaurant;
use App\Models\Trip;
use App\Models\User;
use App\Services\Discovery\DiscoveryQuery;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Cache;
use Tests\Feature\DiscoveryRefinerTest;
use Tests\Support\CustomerFactory;
use Tests\Support\RestaurantFixtures;
use Tests\TestCase;

/**
 * Search, filters, sorting and pagination over the wire.
 *
 * {@see DiscoveryRefinerTest} proves the refinement itself
 * against constructed results. This file proves the layer above it: that a
 * query string becomes the query the refiner was given, that a malformed one is
 * refused before anything expensive runs, and — the requirement the module
 * turns on — that nothing a customer can type in a filter reaches a restaurant
 * Module 07 already decided they may not see.
 */
final class TripRestaurantFilterApiTest extends TestCase
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

    /** @param array<string, string|int> $query */
    private function url(array $query = [], ?Trip $trip = null): string
    {
        $path = '/api/v1/customer/trips/'.($trip ?? $this->trip)->uuid.'/restaurants';

        return $query === [] ? $path : $path.'?'.http_build_query($query);
    }

    /**
     * Four restaurants along the road, deliberately unalike.
     *
     * @return array<string, Restaurant>
     */
    private function corridor(): array
    {
        return [
            'spice' => RestaurantFixtures::nearRoute(
                0.20, 900, 'Highway Spice Kitchen',
                cuisines: ['North Indian'],
                facilities: ['Parking', 'Restroom'],
            ),
            'brew' => RestaurantFixtures::nearRoute(
                0.40, 1_200, 'Roadside Brew Cafe',
                cuisines: ['Cafe', 'Bakery'],
                facilities: ['Restroom'],
            ),
            'thali' => RestaurantFixtures::nearRoute(
                0.60, 700, 'Rajasthan Thali House',
                cuisines: ['North Indian', 'Vegetarian'],
                facilities: ['Parking'],
            ),
            'night' => RestaurantFixtures::nearRoute(
                0.80, 1_500, 'Midnight Dosa Point', open: false,
                cuisines: ['South Indian'],
                facilities: ['Parking', 'Restroom'],
            ),
        ];
    }

    /**
     * @param  array<string, string|int>  $query
     * @return list<string>
     */
    private function names(array $query): array
    {
        $response = $this->asRahul()->getJson($this->url($query))->assertOk();

        return array_column($response->json('data.restaurants'), 'name');
    }

    /** @param array<string, string|int> $query */
    private function assertRejects(array $query, string $field): void
    {
        $this->asRahul()->getJson($this->url($query))
            ->assertStatus(422)
            ->assertJsonPath('error.code', ApiErrorCode::ValidationFailed->value)
            ->assertJsonPath('error.details.fields.'.$field.'.0', fn (mixed $m): bool => is_string($m));
    }

    // --- search --------------------------------------------------------------

    public function test_a_search_narrows_the_route_to_what_was_asked_for(): void
    {
        $this->corridor();

        $this->assertSame(['Highway Spice Kitchen'], $this->names(['search' => 'spice']));
    }

    public function test_a_search_matches_a_cuisine_as_well_as_a_name(): void
    {
        $this->corridor();

        $found = $this->names(['search' => 'south indian']);

        $this->assertSame(['Midnight Dosa Point'], $found);
    }

    public function test_a_search_that_matches_nothing_is_an_empty_page_not_an_error(): void
    {
        $this->corridor();

        $this->asRahul()->getJson($this->url(['search' => 'sushi']))
            ->assertOk()
            ->assertJsonPath('data.restaurants', [])
            ->assertJsonPath('data.meta.total', 0)
            // The screen must be able to say "your search found nothing" rather
            // than "there is nothing on this road", which is a different fact.
            ->assertJsonPath('data.meta.eligible_total', 4)
            ->assertJsonPath('data.meta.filtered_empty', true);
    }

    public function test_a_single_character_search_is_treated_as_no_search(): void
    {
        $this->corridor();

        // A customer mid-keystroke. Refusing them with a 422 would put an error
        // on the screen between the first letter and the second.
        $this->asRahul()->getJson($this->url(['search' => 'a']))
            ->assertOk()
            ->assertJsonPath('data.meta.total', 4)
            ->assertJsonPath('data.meta.applied.search', null);
    }

    public function test_an_oversized_search_is_refused(): void
    {
        $this->assertRejects(
            ['search' => str_repeat('a', DiscoveryQuery::MAX_SEARCH_LENGTH + 1)],
            'search',
        );
    }

    /**
     * Mandatory: no search term can reach a restaurant Module 07 removed.
     */
    public function test_searching_for_a_suspended_restaurant_finds_nothing(): void
    {
        RestaurantFixtures::nearRoute(0.4, 800, 'Good One');

        Restaurant::factory()->discoverable()->suspended()->named('Suspended Dhaba')
            ->at(...RestaurantFixtures::offset(
                0.42, 800, RestaurantFixtures::ORIGIN, RestaurantFixtures::DESTINATION,
            ))
            ->create();

        $this->asRahul()->getJson($this->url(['search' => 'Suspended Dhaba']))
            ->assertOk()
            ->assertJsonPath('data.restaurants', [])
            ->assertJsonPath('data.meta.total', 0);
    }

    public function test_no_filter_combination_reaches_an_unverified_restaurant(): void
    {
        RestaurantFixtures::nearRoute(0.4, 800, 'Good One');

        $pending = Restaurant::factory()->discoverable()->pendingVerification()
            ->named('Pending Restaurant')
            ->at(...RestaurantFixtures::offset(
                0.42, 800, RestaurantFixtures::ORIGIN, RestaurantFixtures::DESTINATION,
            ))
            ->create();
        $pending->cuisines()->create(['cuisine' => 'North Indian', 'position' => 0]);
        $pending->facilities()->create(['facility' => 'Parking', 'position' => 0]);
        RestaurantFixtures::openAllWeek($pending);

        foreach ([
            ['search' => 'pending'],
            ['cuisines' => 'north_indian'],
            ['facilities' => 'parking'],
            ['price_levels' => '1,2,3,4'],
            ['availability' => 'open_now'],
            ['sort' => 'lowest_detour'],
            ['search' => 'restaurant', 'cuisines' => 'north_indian', 'facilities' => 'parking'],
        ] as $query) {
            $this->assertNotContains(
                'Pending Restaurant',
                $this->names($query),
                'reached by: '.http_build_query($query),
            );
        }
    }

    // --- filters -------------------------------------------------------------

    public function test_a_cuisine_filter_uses_the_slug_not_the_label(): void
    {
        $this->corridor();

        $this->assertSame(
            ['Highway Spice Kitchen', 'Rajasthan Thali House'],
            $this->names(['cuisines' => 'north_indian', 'sort' => 'soonest_along_route']),
        );
    }

    public function test_several_cuisines_are_an_or(): void
    {
        $this->corridor();

        $found = $this->names(['cuisines' => 'cafe,south_indian', 'sort' => 'soonest_along_route']);

        $this->assertSame(['Roadside Brew Cafe', 'Midnight Dosa Point'], $found);
    }

    public function test_several_facilities_are_an_and(): void
    {
        $this->corridor();

        // "Parking and a restroom" means both, not either: a customer filtering
        // for both and stopping somewhere with one has been misled.
        $found = $this->names(['facilities' => 'parking,restroom', 'sort' => 'soonest_along_route']);

        $this->assertSame(['Highway Spice Kitchen', 'Midnight Dosa Point'], $found);
    }

    public function test_filters_of_different_kinds_are_an_and(): void
    {
        $this->corridor();

        $this->assertSame(
            ['Highway Spice Kitchen'],
            $this->names(['cuisines' => 'north_indian', 'facilities' => 'parking,restroom']),
        );
    }

    public function test_open_now_and_accepting_orders_are_different_questions(): void
    {
        $restaurants = $this->corridor();
        RestaurantFixtures::openDaily($restaurants['night'], '02:00:00', '03:00:00');

        $open = $this->names(['availability' => 'open_now']);
        $ordering = $this->names(['availability' => 'accepting_orders']);

        $this->assertNotContains('Midnight Dosa Point', $open);
        $this->assertNotContains('Midnight Dosa Point', $ordering);
        $this->assertContains('Highway Spice Kitchen', $open);
        $this->assertContains('Highway Spice Kitchen', $ordering);
    }

    public function test_a_price_filter_keeps_only_the_levels_asked_for(): void
    {
        $restaurants = $this->corridor();
        $restaurants['brew']->forceFill(['price_level' => 1])->save();
        $restaurants['thali']->forceFill(['price_level' => 3])->save();

        $this->assertSame(['Roadside Brew Cafe'], $this->names(['price_levels' => '1']));
        $this->assertSame(
            ['Roadside Brew Cafe', 'Rajasthan Thali House'],
            $this->names(['price_levels' => '3,1', 'sort' => 'soonest_along_route']),
        );
    }

    public function test_a_detour_limit_is_expressed_in_seconds(): void
    {
        $this->corridor();

        // Every stand-in detour along this straight line is small, so the
        // corridor's own ceiling keeps all four while a one-second limit keeps
        // none. It is the comparison being checked, not a particular road.
        $ceiling = (int) config('foodonthego.discovery.max_detour_duration_seconds');

        $this->assertCount(4, $this->names(['max_detour_seconds' => $ceiling]));
        $this->assertSame([], $this->names(['max_detour_seconds' => 1]));
    }

    public function test_a_distance_ahead_limit_cuts_the_far_end_of_the_route(): void
    {
        $this->corridor();

        $near = $this->names(['max_distance_ahead_meters' => 120_000, 'sort' => 'soonest_along_route']);

        $this->assertContains('Highway Spice Kitchen', $near);
        $this->assertNotContains('Midnight Dosa Point', $near);
    }

    public function test_a_rating_filter_matches_nothing_while_nothing_is_rated(): void
    {
        $this->corridor();

        // Honest rather than convenient: with no reviews module, the truthful
        // answer to "at least 4 stars" is none of them.
        $this->asRahul()->getJson($this->url(['min_rating' => '4']))
            ->assertOk()
            ->assertJsonPath('data.meta.total', 0)
            ->assertJsonPath('data.filters.rating_available', false);
    }

    public function test_the_facets_describe_this_route(): void
    {
        $this->corridor();

        $filters = $this->asRahul()->getJson($this->url())->assertOk()->json('data.filters');

        $this->assertSame(
            ['bakery', 'cafe', 'north_indian', 'south_indian', 'vegetarian'],
            array_column($filters['cuisines'], 'slug'),
        );
        $this->assertSame(
            ['parking', 'restroom'],
            array_column($filters['facilities'], 'slug'),
        );
        $this->assertSame(2, $filters['cuisines'][2]['count']);
        $this->assertSame('North Indian', $filters['cuisines'][2]['label']);
    }

    public function test_an_unavailable_sort_is_advertised_rather_than_hidden(): void
    {
        $this->corridor();

        $sorts = $this->asRahul()->getJson($this->url())->assertOk()->json('data.filters.sorts');

        $rated = collect($sorts)->firstWhere('value', 'highest_rated');

        $this->assertFalse($rated['available']);
        $this->assertIsString($rated['unavailable_reason']);
    }

    // --- sorting -------------------------------------------------------------

    public function test_each_supported_sort_is_accepted(): void
    {
        $this->corridor();

        foreach (['recommended', 'lowest_detour', 'soonest_along_route', 'price_low_to_high'] as $sort) {
            $this->asRahul()->getJson($this->url(['sort' => $sort]))
                ->assertOk()
                ->assertJsonPath('data.meta.applied.sort', $sort);
        }
    }

    public function test_journey_order_is_journey_order(): void
    {
        $this->corridor();

        $this->assertSame(
            [
                'Highway Spice Kitchen',
                'Roadside Brew Cafe',
                'Rajasthan Thali House',
                'Midnight Dosa Point',
            ],
            $this->names(['sort' => 'soonest_along_route']),
        );
    }

    public function test_a_stop_behind_the_customer_is_never_first(): void
    {
        $this->corridor();
        RestaurantFixtures::nearRoute(-0.012, 600, 'Behind You Diner');

        foreach (['recommended', 'lowest_detour', 'soonest_along_route', 'price_low_to_high'] as $sort) {
            $found = $this->names(['sort' => $sort]);

            $this->assertSame('Behind You Diner', end($found), "sorted wrong by {$sort}");
        }
    }

    public function test_a_sort_that_is_not_on_the_list_is_refused(): void
    {
        $this->assertRejects(['sort' => 'commission_rate desc'], 'sort');
    }

    public function test_a_sort_that_exists_but_cannot_work_yet_is_refused(): void
    {
        // Not silently downgraded to recommended: a client asking to sort by a
        // rating nothing has needs to know it did not happen.
        $this->assertRejects(['sort' => 'highest_rated'], 'sort');
    }

    // --- pagination ----------------------------------------------------------

    public function test_a_page_carries_its_own_position(): void
    {
        foreach (range(1, 7) as $n) {
            RestaurantFixtures::nearRoute(0.1 + $n * 0.05, 800, "Stop {$n}");
        }

        $this->asRahul()->getJson($this->url(['per_page' => 3, 'sort' => 'soonest_along_route']))
            ->assertOk()
            ->assertJsonPath('data.meta.returned', 3)
            ->assertJsonPath('data.meta.total', 7)
            ->assertJsonPath('data.meta.page', 1)
            ->assertJsonPath('data.meta.last_page', 3)
            ->assertJsonPath('data.meta.has_more', true)
            ->assertJsonPath('data.restaurants.0.name', 'Stop 1');

        $this->asRahul()->getJson($this->url(['per_page' => 3, 'page' => 3, 'sort' => 'soonest_along_route']))
            ->assertOk()
            ->assertJsonPath('data.meta.returned', 1)
            ->assertJsonPath('data.meta.has_more', false)
            ->assertJsonPath('data.restaurants.0.name', 'Stop 7');
    }

    public function test_a_page_past_the_end_is_empty_rather_than_an_error(): void
    {
        $this->corridor();

        $this->asRahul()->getJson($this->url(['page' => 99]))
            ->assertOk()
            ->assertJsonPath('data.restaurants', [])
            ->assertJsonPath('data.meta.total', 4);
    }

    /**
     * Filtering happens over the whole eligible set, not over the first page.
     */
    public function test_a_filter_sees_restaurants_beyond_the_first_page(): void
    {
        foreach (range(1, 29) as $n) {
            RestaurantFixtures::nearRoute(
                0.02 + $n * 0.03, 800, "Stop {$n}",
                facilities: $n === 29 ? ['Charging'] : ['Parking'],
            );
        }

        // Stop 29 is last in journey order and outside any first page. A filter
        // applied to a page rather than to the route would never find it.
        $this->assertSame(['Stop 29'], $this->names(['facilities' => 'charging']));
    }

    // --- validation ----------------------------------------------------------

    public function test_a_malformed_filter_is_refused_by_name(): void
    {
        foreach ([
            ['cuisines' => 'North Indian'],
            ['facilities' => 'parking; DROP TABLE restaurants'],
            ['price_levels' => '9'],
            ['availability' => 'whenever'],
            ['max_detour_seconds' => '-500'],
            ['max_detour_seconds' => 'soon'],
            ['max_distance_ahead_meters' => '0'],
            ['min_rating' => '9'],
            ['min_rating' => 'good'],
            ['per_page' => '0'],
            ['per_page' => (string) (DiscoveryQuery::MAX_PER_PAGE + 1)],
            ['per_page' => 'lots'],
        ] as $query) {
            $this->assertRejects($query, array_key_first($query));
        }
    }

    public function test_a_filter_group_cannot_carry_an_unbounded_number_of_values(): void
    {
        $this->assertRejects(
            ['cuisines' => implode(',', array_map(
                static fn (int $n): string => 'c'.$n,
                range(1, DiscoveryQuery::MAX_FILTER_VALUES + 1),
            ))],
            'cuisines',
        );
    }

    public function test_an_injection_string_is_refused_and_changes_nothing(): void
    {
        $this->corridor();

        foreach ([
            "' OR 1=1 --",
            'north_indian\' UNION SELECT owner_phone FROM restaurants --',
            '1); DROP TABLE restaurants; --',
        ] as $payload) {
            // Refused at the shape, long before anything is built from it.
            $this->asRahul()->getJson($this->url(['cuisines' => $payload]))->assertStatus(422);
        }

        // A search is free text, so it is not refused — it simply matches by
        // value and never becomes SQL.
        $this->asRahul()->getJson($this->url(['search' => "'; DROP TABLE restaurants; --"]))
            ->assertOk()
            ->assertJsonPath('data.meta.total', 0);

        $this->assertSame(4, Restaurant::query()->count());
    }

    public function test_the_server_reports_the_query_it_actually_used(): void
    {
        $this->corridor();

        $applied = $this->asRahul()
            ->getJson($this->url(['facilities' => ' restroom , parking ', 'search' => '  Highway   Spice  ']))
            ->assertOk()
            ->json('data.meta.applied');

        // Normalised and ordered, so a client can see what the server made of
        // its request instead of assuming.
        $this->assertSame(['parking', 'restroom'], $applied['facilities']);
        $this->assertSame('Highway Spice', $applied['search']);
    }

    // --- ownership, state and cost ------------------------------------------

    public function test_filters_do_not_open_a_door_into_somebody_elses_trip(): void
    {
        $priya = CustomerFactory::ananya();
        $hers = RestaurantFixtures::tripWithSelectedRoute($priya);
        RestaurantFixtures::nearRoute(0.4, 800, 'Highway Spice Kitchen');

        $this->asRahul()->getJson($this->url(['search' => 'spice'], $hers))
            ->assertNotFound();
    }

    public function test_a_route_that_is_not_ready_is_refused_before_the_filters_matter(): void
    {
        $bare = Trip::factory()->ownedBy($this->rahul)->create();

        $this->asRahul()->getJson($this->url(['cuisines' => 'north_indian'], $bare))
            ->assertStatus(409)
            ->assertJsonPath('error.code', ApiErrorCode::RouteNotReady->value);
    }

    public function test_an_invalid_filter_is_refused_without_searching_the_corridor(): void
    {
        $this->corridor();

        $this->asRahul()->getJson($this->url(['sort' => 'nonsense']))->assertStatus(422);

        // Nothing was cached, because nothing was computed: the request was
        // refused before the expensive half of the endpoint ran.
        $this->asRahul()->getJson($this->url())
            ->assertOk()
            ->assertJsonPath('data.meta.from_cache', false);
    }

    /**
     * The module's central cost guarantee, at the edge.
     */
    public function test_changing_a_filter_reuses_the_expensive_work(): void
    {
        $this->corridor();

        $this->asRahul()->getJson($this->url())
            ->assertOk()
            ->assertJsonPath('data.meta.from_cache', false);

        foreach ([
            ['cuisines' => 'north_indian'],
            ['facilities' => 'parking'],
            ['availability' => 'open_now'],
            ['sort' => 'lowest_detour'],
            ['search' => 'brew'],
            ['page' => 2, 'per_page' => 2],
        ] as $query) {
            $this->asRahul()->getJson($this->url($query))
                ->assertOk()
                ->assertJsonPath('data.meta.from_cache', true);
        }
    }

    public function test_two_customers_filters_do_not_reach_each_others_results(): void
    {
        $this->corridor();

        $priya = CustomerFactory::ananya();
        $herToken = CustomerFactory::tokenFor($priya);
        $herTrip = RestaurantFixtures::tripWithSelectedRoute(
            $priya,
            origin: [19.0760, 72.8777],
            destination: [18.5204, 73.8567],
        );

        $this->assertSame(['Highway Spice Kitchen'], $this->names(['search' => 'spice']));

        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        // A different road entirely. A cache keyed on the filters rather than on
        // the route would answer this with Rahul's corridor.
        $this->withHeader('Authorization', 'Bearer '.$herToken)
            ->getJson('/api/v1/customer/trips/'.$herTrip->uuid.'/restaurants?search=spice')
            ->assertOk()
            ->assertJsonPath('data.restaurants', []);
    }

    public function test_a_filtered_call_is_rate_limited_like_any_other(): void
    {
        config(['foodonthego.rate_limits.discovery' => 3]);
        $this->corridor();

        foreach (range(1, 3) as $n) {
            $this->asRahul()->getJson($this->url(['page' => $n]))->assertOk();
        }

        // Cheap to serve is not free to serve, and a filter is not a way around
        // the budget on the most expensive endpoint in the application.
        $this->asRahul()->getJson($this->url(['search' => 'spice']))->assertStatus(429);
    }

    public function test_a_filtered_response_carries_no_private_restaurant_data(): void
    {
        $spice = $this->corridor()['spice'];

        $spice->forceFill([
            'owner_phone' => '+919812345678',
            'commission_rate' => 18.50,
            'internal_notes' => 'Late on settlements. Watch.',
        ])->save();

        $body = $this->asRahul()
            ->getJson($this->url(['search' => 'spice', 'facilities' => 'parking']))
            ->assertOk()
            ->content();

        foreach (['+919812345678', 'Late on settlements', 'commission_rate', 'internal_notes'] as $secret) {
            $this->assertStringNotContainsString($secret, $body, "leaked: {$secret}");
        }
    }
}
