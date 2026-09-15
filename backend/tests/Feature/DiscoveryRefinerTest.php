<?php

declare(strict_types=1);

namespace Tests\Feature;

use App\Enums\RestaurantStatus;
use App\Enums\RestaurantVerificationStatus;
use App\Models\Restaurant;
use App\Models\Trip;
use App\Models\User;
use App\Services\Discovery\DiscoveryQuery;
use App\Services\Discovery\DiscoveryRefiner;
use App\Services\Discovery\RefinedDiscovery;
use App\Services\Discovery\RestaurantDetourService;
use App\Services\Discovery\RestaurantDiscoveryService;
use App\Services\Routing\RouteProvider;
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Tests\Support\CustomerFactory;
use Tests\Support\RestaurantFixtures;
use Tests\TestCase;
use Tests\Unit\StubDetourProvider;

/**
 * Search, filters and sorting, over a real discovery of real rows.
 *
 * A feature test rather than a unit test because the thing being verified is the
 * *composition*: that filtering runs after eligibility, over the whole eligible
 * set, and cannot reach past it.
 */
final class DiscoveryRefinerTest extends TestCase
{
    use RefreshDatabase;

    private User $rahul;

    private Trip $trip;

    private StubDetourProvider $provider;

    protected function setUp(): void
    {
        parent::setUp();

        Cache::flush();

        $this->rahul = CustomerFactory::rahul();
        $this->trip = RestaurantFixtures::tripWithSelectedRoute($this->rahul);

        $this->provider = new StubDetourProvider;
        $this->app->instance(RouteProvider::class, $this->provider);
        $this->app->forgetInstance(RestaurantDetourService::class);
        $this->app->forgetInstance(RestaurantDiscoveryService::class);
    }

    /** @return list<string> */
    private function names(array $params = []): array
    {
        $discovered = $this->app->make(RestaurantDiscoveryService::class)
            ->discover($this->trip->refresh(), CarbonImmutable::parse('2026-09-07T12:00:00Z'));

        $refined = $this->app->make(DiscoveryRefiner::class)->refine(
            $discovered,
            DiscoveryQuery::fromRequest(Request::create('/', 'GET', $params)),
        );

        return array_map(
            static fn ($d): string => $d->restaurant->name,
            $refined->restaurants,
        );
    }

    private function refine(array $params = []): RefinedDiscovery
    {
        $discovered = $this->app->make(RestaurantDiscoveryService::class)
            ->discover($this->trip->refresh(), CarbonImmutable::parse('2026-09-07T12:00:00Z'));

        return $this->app->make(DiscoveryRefiner::class)->refine(
            $discovered,
            DiscoveryQuery::fromRequest(Request::create('/', 'GET', $params)),
        );
    }

    /** The worked example: three eligible restaurants with distinct metadata. */
    private function seedThree(): void
    {
        $a = RestaurantFixtures::nearRoute(
            0.20, 600, 'Highway Spice Kitchen',
            cuisines: ['North Indian', 'Vegetarian'],
            facilities: ['Parking', 'Restroom'],
        );
        $a->forceFill(['price_level' => 2])->save();

        $b = RestaurantFixtures::nearRoute(
            0.45, 900, 'Rajasthan Highway Bites',
            cuisines: ['Fast Food'],
            facilities: ['Parking'],
        );
        $b->forceFill(['price_level' => 1])->save();

        $c = RestaurantFixtures::nearRoute(
            0.70, 1_200, 'Route Cafe',
            cuisines: ['Cafe'],
            facilities: ['Restroom'],
        );
        $c->forceFill(['price_level' => 3])->save();
    }

    // --- the guarantee that matters most -------------------------------------

    public function test_a_search_cannot_resurrect_a_restaurant_eligibility_removed(): void
    {
        $this->seedThree();

        Restaurant::factory()->discoverable()->suspended()->named('Suspended Dhaba')
            ->at(...RestaurantFixtures::offset(
                0.3, 700, RestaurantFixtures::ORIGIN, RestaurantFixtures::DESTINATION,
            ))
            ->create();

        // Searching a suspended restaurant by its exact name. Mandatory: the row
        // was gone before the refiner was called, so there is nothing here to
        // find — not a check that could be forgotten, a property of where this
        // code sits in the pipeline.
        $this->assertSame([], $this->names(['search' => 'Suspended Dhaba']));
    }

    public function test_no_filter_combination_can_reach_an_ineligible_restaurant(): void
    {
        $this->seedThree();

        foreach ([
            ['status' => RestaurantStatus::Suspended],
            ['status' => RestaurantStatus::Disabled],
            ['verification_status' => RestaurantVerificationStatus::Pending],
            ['is_discoverable' => false],
        ] as $i => $state) {
            Restaurant::factory()->discoverable()->named("Hidden {$i}")
                ->at(...RestaurantFixtures::offset(
                    0.3 + $i * 0.02, 700, RestaurantFixtures::ORIGIN, RestaurantFixtures::DESTINATION,
                ))
                ->create($state);
        }

        foreach ([
            ['search' => 'Hidden'],
            ['cuisines' => 'north_indian'],
            ['facilities' => 'parking'],
            ['availability' => 'open_now'],
            ['max_detour_seconds' => '900'],
            ['sort' => 'lowest_detour'],
        ] as $params) {
            foreach ($this->names($params) as $name) {
                $this->assertStringNotContainsString('Hidden', $name);
            }
        }
    }

    // --- search --------------------------------------------------------------

    public function test_a_name_search_finds_one_restaurant(): void
    {
        $this->seedThree();

        $this->assertSame(['Highway Spice Kitchen'], $this->names(['search' => 'Highway Spice']));
    }

    public function test_a_cuisine_search_finds_by_metadata(): void
    {
        $this->seedThree();

        $this->assertSame(['Highway Spice Kitchen'], $this->names(['search' => 'Vegetarian']));
    }

    public function test_a_search_that_matches_nothing_is_a_filtered_empty(): void
    {
        $this->seedThree();

        $refined = $this->refine(['search' => 'Sushi Palace XYZ']);

        // Distinguishable from "this route has nothing on it", which needs
        // different words and a different button.
        $this->assertSame(0, $refined->total);
        $this->assertSame(3, $refined->eligibleTotal);
        $this->assertTrue($refined->isFilteredEmpty());
    }

    public function test_an_exact_name_match_leads_the_results(): void
    {
        $this->seedThree();

        // "Highway" is in two names. The one whose name starts with it wins,
        // even though the other is closer to the road.
        $this->assertSame('Highway Spice Kitchen', $this->names(['search' => 'Highway'])[0]);
    }

    // --- filters -------------------------------------------------------------

    public function test_a_cuisine_filter_narrows_to_that_cuisine(): void
    {
        $this->seedThree();

        $this->assertSame(['Highway Spice Kitchen'], $this->names(['cuisines' => 'north_indian']));
    }

    public function test_cuisines_are_an_or_within_the_group(): void
    {
        $this->seedThree();

        $this->assertEqualsCanonicalizing(
            ['Highway Spice Kitchen', 'Route Cafe'],
            $this->names(['cuisines' => 'north_indian,cafe']),
        );
    }

    public function test_facilities_are_an_and_within_the_group(): void
    {
        $this->seedThree();

        // Somebody ticking two facilities is stating two requirements, not
        // offering a choice. Only the restaurant with both survives.
        $this->assertSame(
            ['Highway Spice Kitchen'],
            $this->names(['facilities' => 'parking,restroom']),
        );

        $this->assertEqualsCanonicalizing(
            ['Highway Spice Kitchen', 'Rajasthan Highway Bites'],
            $this->names(['facilities' => 'parking']),
        );
    }

    public function test_groups_are_an_and_across_each_other(): void
    {
        $this->seedThree();

        // North Indian **and** parking: only one restaurant is both.
        $this->assertSame(
            ['Highway Spice Kitchen'],
            $this->names(['cuisines' => 'north_indian', 'facilities' => 'parking']),
        );

        // A combination nothing satisfies.
        $this->assertSame(
            [],
            $this->names(['cuisines' => 'cafe', 'facilities' => 'parking']),
        );
    }

    public function test_a_price_filter_uses_the_declared_level(): void
    {
        $this->seedThree();

        $this->assertSame(['Rajasthan Highway Bites'], $this->names(['price_levels' => '1']));
        $this->assertEqualsCanonicalizing(
            ['Rajasthan Highway Bites', 'Route Cafe'],
            $this->names(['price_levels' => '1,3']),
        );
    }

    public function test_a_restaurant_with_no_declared_price_does_not_match_a_price_filter(): void
    {
        RestaurantFixtures::nearRoute(0.3, 600, 'Unpriced Dhaba')
            ->forceFill(['price_level' => null])->save();

        // It is not cheap. It is unknown, and an unknown does not satisfy a
        // request for a specific level.
        $this->assertSame([], $this->names(['price_levels' => '1,2,3,4']));
        $this->assertSame(['Unpriced Dhaba'], $this->names([]));
    }

    public function test_open_now_and_accepting_orders_are_different_questions(): void
    {
        RestaurantFixtures::nearRoute(0.2, 600, 'Open And Cooking');

        $paused = RestaurantFixtures::nearRoute(0.4, 600, 'Open But Paused');
        $paused->forceFill(['is_accepting_orders' => false])->save();

        $shut = RestaurantFixtures::nearRoute(0.6, 600, 'Shut', open: false);
        RestaurantFixtures::openDaily($shut, '02:00:00', '03:00:00');

        // The distinction this module must never collapse. A paused restaurant
        // is open by the clock and cannot take an order.
        $this->assertEqualsCanonicalizing(
            ['Open And Cooking', 'Open But Paused'],
            $this->names(['availability' => 'open_now']),
        );

        $this->assertSame(
            ['Open And Cooking'],
            $this->names(['availability' => 'accepting_orders']),
        );
    }

    public function test_a_detour_filter_compares_seconds_not_words(): void
    {
        $this->seedThree();

        $this->provider->extraDurationSeconds = 240;

        $this->assertCount(3, $this->names(['max_detour_seconds' => '300']));
        $this->assertSame([], $this->names(['max_detour_seconds' => '120']));
    }

    public function test_an_unknown_detour_does_not_satisfy_a_detour_limit(): void
    {
        config(['foodonthego.discovery.max_detour_evaluations' => 1]);
        $this->app->forgetInstance(RestaurantDetourService::class);
        $this->app->forgetInstance(RestaurantDiscoveryService::class);

        RestaurantFixtures::nearRoute(0.2, 300, 'Measured');
        RestaurantFixtures::nearRoute(0.5, 4_000, 'Unmeasured');

        // We cannot assert an unknown is under ten minutes, and guessing in the
        // customer's favour is how somebody ends up twenty minutes off route.
        $this->assertSame(['Measured'], $this->names(['max_detour_seconds' => '900']));

        // Without the filter it is still offered, with its detour absent.
        $this->assertCount(2, $this->names([]));
    }

    public function test_a_distance_ahead_filter_uses_route_distance(): void
    {
        $this->seedThree();

        $route = $this->trip->refresh()->routes()->first();
        $half = (int) ($route->distance_meters / 2);

        $near = $this->refine(['max_distance_ahead_meters' => (string) $half]);

        foreach ($near->restaurants as $found) {
            $this->assertLessThanOrEqual($half, $found->projection->alongRouteMetres);
        }

        $this->assertLessThan($near->eligibleTotal, $near->total);
    }

    public function test_a_rating_filter_matches_nothing_while_nothing_is_rated(): void
    {
        $this->seedThree();

        // The honest answer. An unrated restaurant has not earned four stars; it
        // has earned nothing yet.
        $this->assertSame([], $this->names(['min_rating' => '4']));
    }

    public function test_search_and_filters_are_combined_not_alternatives(): void
    {
        $this->seedThree();

        // "Highway" matches two restaurants; only one of them has a restroom.
        $this->assertSame(
            ['Highway Spice Kitchen'],
            $this->names(['search' => 'Highway', 'facilities' => 'restroom']),
        );
    }

    // --- sorting -------------------------------------------------------------

    public function test_lowest_detour_sorts_ascending(): void
    {
        $this->seedThree();

        $refined = $this->refine(['sort' => 'lowest_detour']);

        $previous = -1;

        foreach ($refined->restaurants as $found) {
            $seconds = $found->detour?->extraDurationSeconds ?? PHP_INT_MAX;
            $this->assertGreaterThanOrEqual($previous, $seconds);
            $previous = $seconds;
        }
    }

    public function test_soonest_along_route_sorts_ascending(): void
    {
        $this->seedThree();

        $this->assertSame(
            ['Highway Spice Kitchen', 'Rajasthan Highway Bites', 'Route Cafe'],
            $this->names(['sort' => 'soonest_along_route']),
        );
    }

    public function test_price_low_to_high_sorts_ascending(): void
    {
        $this->seedThree();

        $this->assertSame(
            ['Rajasthan Highway Bites', 'Highway Spice Kitchen', 'Route Cafe'],
            $this->names(['sort' => 'price_low_to_high']),
        );
    }

    public function test_a_backtracking_stop_is_never_first_in_any_sort(): void
    {
        $this->seedThree();
        RestaurantFixtures::nearRoute(-0.01, 500, 'Behind You');

        // Every sort, including the ones where the primary key cannot separate
        // them. A price sort over restaurants that all cost the same is decided
        // entirely by tie-breakers, and that is where this went wrong once.
        foreach (['recommended', 'lowest_detour', 'soonest_along_route', 'price_low_to_high'] as $sort) {
            $names = $this->names(['sort' => $sort]);

            $this->assertNotSame('Behind You', $names[0], "backtracking led the {$sort} sort");
        }
    }

    public function test_sorting_is_stable_across_identical_requests(): void
    {
        // Four restaurants with nothing to tell them apart but their uuid. A
        // list that reorders itself between requests duplicates one row and
        // hides another as the customer pages through it.
        foreach (range(1, 4) as $i) {
            RestaurantFixtures::nearRoute(0.3, 600, "Identical {$i}");
        }

        $first = $this->names(['sort' => 'lowest_detour']);
        $second = $this->names(['sort' => 'lowest_detour']);

        $this->assertSame($first, $second);
    }

    // --- pagination ----------------------------------------------------------

    public function test_pagination_pages_the_filtered_answer(): void
    {
        $this->seedThree();

        $page1 = $this->refine(['per_page' => '2', 'page' => '1']);
        $page2 = $this->refine(['per_page' => '2', 'page' => '2']);

        $this->assertCount(2, $page1->restaurants);
        $this->assertCount(1, $page2->restaurants);
        $this->assertSame(3, $page1->total);
        $this->assertTrue($page1->hasMore());
        $this->assertFalse($page2->hasMore());
        $this->assertSame(2, $page1->lastPage());
    }

    public function test_a_page_beyond_the_end_is_empty_rather_than_an_error(): void
    {
        $this->seedThree();

        $refined = $this->refine(['per_page' => '2', 'page' => '9']);

        $this->assertSame([], $refined->restaurants);
        $this->assertSame(3, $refined->total);
    }

    public function test_filtering_sees_the_whole_eligible_set_not_a_page_of_it(): void
    {
        // The reason Module 07's result limit moved. Thirty restaurants on the
        // road, one of them with a restroom, and it is the twenty-ninth by
        // relevance: a filter applied to a truncated set would never find it.
        foreach (range(1, 30) as $i) {
            RestaurantFixtures::nearRoute(
                0.02 * $i,
                400 + $i * 100,
                "Stop {$i}",
                facilities: $i === 29 ? ['Restroom'] : ['Parking'],
            );
        }

        $this->assertSame(['Stop 29'], $this->names(['facilities' => 'restroom']));
    }

    // --- facets --------------------------------------------------------------

    public function test_the_facets_describe_this_route(): void
    {
        $this->seedThree();

        $facets = $this->refine([])->facets;

        $cuisines = array_column($facets['cuisines'], 'count', 'slug');

        $this->assertSame(1, $cuisines['north_indian']);
        $this->assertSame(1, $cuisines['cafe']);
        // Offering a filter for something no restaurant on this road has is a
        // control that can only empty the screen.
        $this->assertArrayNotHasKey('ev_charging', $cuisines);

        $facilities = array_column($facets['facilities'], 'count', 'slug');
        $this->assertSame(2, $facilities['parking']);

        // No restaurant has a rating, so the client renders no rating control.
        $this->assertFalse($facets['rating_available']);
    }

    public function test_facets_are_counted_before_filters_so_options_do_not_collapse(): void
    {
        $this->seedThree();

        // A customer who has already chosen North Indian still needs to see how
        // many restaurants have parking, or every other option reads as zero.
        $facets = $this->refine(['cuisines' => 'north_indian'])->facets;

        $this->assertSame(2, array_column($facets['facilities'], 'count', 'slug')['parking']);
    }

    public function test_an_unavailable_sort_is_advertised_as_unavailable(): void
    {
        $this->seedThree();

        $sorts = array_column($this->refine([])->facets['sorts'], null, 'value');

        $this->assertFalse($sorts['highest_rated']['available']);
        $this->assertNotNull($sorts['highest_rated']['unavailable_reason']);
        $this->assertTrue($sorts['lowest_detour']['available']);
    }

    // --- cost ----------------------------------------------------------------

    public function test_changing_a_filter_never_calls_the_routing_provider(): void
    {
        $this->seedThree();

        $this->names([]);
        $afterFirst = $this->provider->calls;

        $this->assertGreaterThan(0, $afterFirst);

        // The module's central cost guarantee. A customer toggling cuisines,
        // facilities, prices and sorts is refining an answer already paid for.
        foreach ([
            ['cuisines' => 'north_indian'],
            ['facilities' => 'parking'],
            ['price_levels' => '1'],
            ['availability' => 'accepting_orders'],
            ['sort' => 'lowest_detour'],
            ['search' => 'highway'],
            ['max_detour_seconds' => '600'],
            ['page' => '2', 'per_page' => '1'],
        ] as $params) {
            $this->names($params);
        }

        $this->assertSame($afterFirst, $this->provider->calls);
    }
}
