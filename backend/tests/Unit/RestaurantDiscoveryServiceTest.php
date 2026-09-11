<?php

declare(strict_types=1);

namespace Tests\Unit;

use App\Enums\RestaurantAvailability;
use App\Enums\RestaurantStatus;
use App\Exceptions\ApiException;
use App\Models\Restaurant;
use App\Models\Trip;
use App\Models\User;
use App\Services\Discovery\DiscoveryResult;
use App\Services\Discovery\RestaurantDetourService;
use App\Services\Discovery\RestaurantDiscoveryService;
use App\Services\Routing\RouteBounds;
use App\Services\Routing\RouteFailureKind;
use App\Services\Routing\RouteOption;
use App\Services\Routing\RouteProvider;
use App\Services\Routing\RouteProviderException;
use App\Services\Routing\RouteRequest;
use App\Services\Routing\RouteResult;
use App\Support\Geo\Coordinate;
use App\Support\Geo\Distance;
use App\Support\Route\PolylineCodec;
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Cache;
use Tests\Support\CustomerFactory;
use Tests\Support\RestaurantFixtures;
use Tests\TestCase;

/**
 * The engine, end to end, with the provider under the test's control.
 *
 * The detour provider is a stub here on purpose, and not because a real one is
 * unavailable. A test that asserts "a restaurant costing nineteen minutes is
 * excluded" has to be able to *make* one cost nineteen minutes; with a real
 * provider it would be asserting against whatever the road network happens to do
 * this week, which is not a test of this module.
 */
final class RestaurantDiscoveryServiceTest extends TestCase
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

    private function discover(): DiscoveryResult
    {
        return $this->app->make(RestaurantDiscoveryService::class)
            ->discover($this->trip->refresh(), CarbonImmutable::parse('2026-09-07T12:00:00Z'));
    }

    /** @return list<string> */
    private function names(DiscoveryResult $result): array
    {
        return array_map(
            static fn ($d): string => $d->restaurant->name,
            $result->restaurants,
        );
    }

    public function test_a_restaurant_beside_the_route_is_discovered(): void
    {
        RestaurantFixtures::nearRoute(0.4, 800, 'Beside The Road');

        $result = $this->discover();

        $this->assertSame(['Beside The Road'], $this->names($result));
        $this->assertEqualsWithDelta(
            800.0,
            $result->restaurants[0]->projection->proximityMetres,
            60.0,
        );
    }

    public function test_a_restaurant_outside_the_corridor_is_rejected_without_a_provider_call(): void
    {
        RestaurantFixtures::nearRoute(0.5, 40_000, 'Far Away Kitchen');

        $result = $this->discover();

        $this->assertSame([], $this->names($result));
        // The whole reason the search has two stages. A restaurant forty
        // kilometres off the road must never cost a billed call to reject.
        $this->assertSame(0, $this->provider->calls);
    }

    public function test_a_geometrically_close_restaurant_with_a_long_detour_is_excluded(): void
    {
        // The case the product turns on: 400 m from the road, and eighteen
        // minutes' driving because the nearest junction is somewhere else.
        // Proximity says "stop here"; the road network says otherwise.
        RestaurantFixtures::nearRoute(0.35, 400, 'Wrong Side Of The Barrier');

        $this->provider->extraDistanceMetres = 22_000;
        $this->provider->extraDurationSeconds = 1_080;

        $result = $this->discover();

        $this->assertSame([], $this->names($result));
        // It was evaluated — that is the point. It was rejected on what it costs
        // to reach, not on how far away it looks.
        $this->assertSame(1, $this->provider->calls);
        $this->assertSame(1, $result->withinCorridorCount);
    }

    public function test_a_restaurant_further_off_with_a_short_detour_survives(): void
    {
        RestaurantFixtures::nearRoute(0.35, 2_500, 'Beside The Junction');

        $this->provider->extraDistanceMetres = 3_000;
        $this->provider->extraDurationSeconds = 240;

        $result = $this->discover();

        $this->assertSame(['Beside The Junction'], $this->names($result));
        $this->assertSame(240, $result->restaurants[0]->detour->extraDurationSeconds);
    }

    public function test_ineligible_restaurants_never_appear(): void
    {
        RestaurantFixtures::nearRoute(0.30, 700, 'Good One');

        Restaurant::factory()->discoverable()->suspended()->named('Suspended Dhaba')
            ->at(...RestaurantFixtures::offset(0.32, 700, RestaurantFixtures::ORIGIN, RestaurantFixtures::DESTINATION))
            ->create();

        Restaurant::factory()->discoverable()->pendingVerification()->named('Pending Restaurant')
            ->at(...RestaurantFixtures::offset(0.34, 700, RestaurantFixtures::ORIGIN, RestaurantFixtures::DESTINATION))
            ->create();

        Restaurant::factory()->discoverable()->disabled()->named('Disabled Diner')
            ->at(...RestaurantFixtures::offset(0.36, 700, RestaurantFixtures::ORIGIN, RestaurantFixtures::DESTINATION))
            ->create();

        $this->assertSame(['Good One'], $this->names($this->discover()));
    }

    public function test_results_are_ordered_along_the_journey(): void
    {
        RestaurantFixtures::nearRoute(0.70, 500, 'Third');
        RestaurantFixtures::nearRoute(0.20, 500, 'First');
        RestaurantFixtures::nearRoute(0.45, 500, 'Second');

        // A traveller reads the list as a sequence of chances to stop.
        $this->assertSame(['First', 'Second', 'Third'], $this->names($this->discover()));
    }

    public function test_a_restaurant_behind_the_origin_is_flagged_and_sorted_last(): void
    {
        RestaurantFixtures::nearRoute(-0.01, 500, 'Behind You');
        RestaurantFixtures::nearRoute(0.60, 500, 'Ahead Of You');

        $result = $this->discover();

        // Still offered — the customer may be standing beside it — but never
        // offered as the next stop on a journey they have not started.
        $this->assertSame(['Ahead Of You', 'Behind You'], $this->names($result));
        $this->assertTrue($result->restaurants[1]->requiresBacktracking);
        $this->assertFalse($result->restaurants[0]->requiresBacktracking);
    }

    public function test_distance_ahead_and_time_ahead_agree_with_the_route(): void
    {
        RestaurantFixtures::nearRoute(0.50, 400, 'Halfway House');

        $result = $this->discover();
        $found = $result->restaurants[0];

        $route = $this->trip->refresh()->routes()->first();

        $this->assertEqualsWithDelta(
            $route->distance_meters / 2,
            $found->projection->alongRouteMetres,
            $route->distance_meters * 0.02,
        );

        $this->assertEqualsWithDelta(
            $route->duration_seconds / 2,
            $found->timeAheadSeconds,
            $route->duration_seconds * 0.02,
        );
    }

    public function test_a_closed_restaurant_is_returned_and_marked_closed(): void
    {
        $restaurant = RestaurantFixtures::nearRoute(0.4, 600, 'Closed Route Cafe', open: false);
        RestaurantFixtures::openDaily($restaurant, '02:00:00', '03:00:00');

        $result = $this->discover();

        // Hiding it would tell a traveller there is nothing on this road, which
        // is a different and wronger thing than "there is somewhere, and it is
        // shut".
        $this->assertSame(['Closed Route Cafe'], $this->names($result));
        $this->assertSame(RestaurantAvailability::Closed, $result->restaurants[0]->availability);
        $this->assertTrue($result->isClosedOnly());
    }

    public function test_a_paused_restaurant_is_returned_and_never_marked_open(): void
    {
        $restaurant = RestaurantFixtures::nearRoute(0.4, 600, 'Paused Grill');
        $restaurant->forceFill(['is_accepting_orders' => false])->save();

        $result = $this->discover();

        $this->assertSame(
            RestaurantAvailability::NotAcceptingOrders,
            $result->restaurants[0]->availability,
        );
        $this->assertFalse($result->restaurants[0]->toApiArray()['is_accepting_orders']);
    }

    public function test_closed_only_is_distinct_from_empty(): void
    {
        $empty = $this->discover();
        $this->assertTrue($empty->isEmpty());
        $this->assertFalse($empty->isClosedOnly());

        $restaurant = RestaurantFixtures::nearRoute(0.4, 600, 'Shut', open: false);
        RestaurantFixtures::openDaily($restaurant, '02:00:00', '03:00:00');
        Cache::flush();

        $closed = $this->discover();
        $this->assertFalse($closed->isEmpty());
        $this->assertTrue($closed->isClosedOnly());
    }

    public function test_a_provider_failure_yields_a_null_detour_rather_than_a_guess(): void
    {
        RestaurantFixtures::nearRoute(0.4, 700, 'Unknown Detour');

        $this->provider->failWith = RouteFailureKind::Unavailable;

        $result = $this->discover();

        // The restaurant survives with the figures that were never in doubt, and
        // the one that could not be established is null. Not zero, and not the
        // straight-line distance doubled and called a detour.
        $this->assertSame(['Unknown Detour'], $this->names($result));
        $this->assertNull($result->restaurants[0]->detour);
        $this->assertNull($result->restaurants[0]->toApiArray()['route']['detour_duration_seconds']);
        $this->assertGreaterThan(0, $result->restaurants[0]->projection->proximityMetres);
    }

    public function test_one_provider_failure_stops_the_rest(): void
    {
        foreach (range(1, 6) as $i) {
            RestaurantFixtures::nearRoute(0.1 * $i, 600, "Stop {$i}");
        }

        $this->provider->failWith = RouteFailureKind::Timeout;

        $this->discover();

        // The sixth timeout tells us nothing the first did not, and each one is
        // twelve seconds a customer spends watching a spinner.
        $this->assertSame(1, $this->provider->calls);
    }

    public function test_the_detour_budget_caps_provider_calls(): void
    {
        config(['foodonthego.discovery.max_detour_evaluations' => 3]);
        $this->app->forgetInstance(RestaurantDetourService::class);
        $this->app->forgetInstance(RestaurantDiscoveryService::class);

        foreach (range(1, 8) as $i) {
            RestaurantFixtures::nearRoute(0.1 * $i, 600 + $i, "Stop {$i}");
        }

        $result = $this->discover();

        $this->assertSame(3, $this->provider->calls);
        // Every candidate is still returned; three of them know what stopping
        // costs and five do not.
        $this->assertCount(8, $result->restaurants);
    }

    public function test_the_budget_is_spent_on_the_closest_candidates(): void
    {
        config(['foodonthego.discovery.max_detour_evaluations' => 1]);
        $this->app->forgetInstance(RestaurantDetourService::class);
        $this->app->forgetInstance(RestaurantDiscoveryService::class);

        RestaurantFixtures::nearRoute(0.3, 4_500, 'Distant');
        RestaurantFixtures::nearRoute(0.6, 300, 'Right Beside It');

        $result = $this->discover();

        $byName = [];

        foreach ($result->restaurants as $found) {
            $byName[$found->restaurant->name] = $found->detour;
        }

        $this->assertNotNull($byName['Right Beside It']);
        $this->assertNull($byName['Distant']);
    }

    public function test_a_second_search_reuses_the_first(): void
    {
        RestaurantFixtures::nearRoute(0.4, 700, 'Cached Kitchen');

        $first = $this->discover();
        $callsAfterFirst = $this->provider->calls;

        $second = $this->discover();

        $this->assertFalse($first->fromCache);
        $this->assertTrue($second->fromCache);
        $this->assertSame($this->names($first), $this->names($second));
        // The corridor work is not repeated. The detour is not re-requested
        // either, because it is cached against the route.
        $this->assertSame($callsAfterFirst, $this->provider->calls);
    }

    public function test_suspending_a_restaurant_removes_it_from_a_warm_cache(): void
    {
        $restaurant = RestaurantFixtures::nearRoute(0.4, 700, 'About To Be Suspended');
        RestaurantFixtures::nearRoute(0.6, 700, 'Still Fine');

        $this->assertCount(2, $this->discover()->restaurants);

        $restaurant->forceFill(['status' => RestaurantStatus::Suspended])->save();

        // Mandatory. A cache that can keep a suspended restaurant visible for
        // five minutes is a cache that recommends a business the platform has
        // stopped.
        $this->assertSame(['Still Fine'], $this->names($this->discover()));
    }

    public function test_changing_the_selected_route_changes_the_results(): void
    {
        RestaurantFixtures::nearRoute(0.4, 700, 'On The Old Route');

        $this->assertCount(1, $this->discover()->restaurants);

        // A different journey entirely: Delhi to Agra. The restaurant beside the
        // Jaipur road is nowhere near it.
        $this->trip->forceFill([
            'destination_latitude' => 27.1767,
            'destination_longitude' => 78.0081,
        ])->save();

        $newTrip = RestaurantFixtures::tripWithSelectedRoute(
            $this->rahul,
            destination: [27.1767, 78.0081],
        );

        $this->trip = $newTrip;

        $this->assertSame([], $this->names($this->discover()));
    }

    public function test_a_trip_with_no_selected_route_is_refused(): void
    {
        $bare = Trip::factory()->ownedBy($this->rahul)->create();
        $this->trip = $bare;

        $this->expectException(ApiException::class);

        $this->discover();
    }

    public function test_the_corridor_reduces_the_candidate_set(): void
    {
        // Evidence for the performance claim rather than an assertion about it.
        foreach (range(1, 20) as $i) {
            RestaurantFixtures::nearRoute(0.05 * $i, 500, "Near {$i}");
        }

        foreach (range(1, 40) as $i) {
            // Inside the route's bounding box, well outside the corridor.
            RestaurantFixtures::nearRoute(0.02 * $i, 20_000 + $i * 100, "Off {$i}");
        }

        $result = $this->discover();

        $this->assertGreaterThan($result->withinCorridorCount, $result->candidateCount);
        $this->assertSame(20, $result->withinCorridorCount);
    }

    public function test_a_restaurant_cannot_be_returned_twice(): void
    {
        RestaurantFixtures::nearRoute(0.4, 700, 'Only Once');

        $names = $this->names($this->discover());

        $this->assertSame($names, array_unique($names));
    }

    public function test_discovery_returns_every_eligible_restaurant_not_a_page_of_them(): void
    {
        // Changed in Module 08, and the reason matters. Discovery used to cut
        // itself to the result limit here, which was right while the endpoint
        // returned it directly. The moment filtering was layered on top it
        // became wrong: a "Parking" filter applied to the top 25 by relevance
        // silently hides the twenty-sixth restaurant, which may be the only one
        // with a car park.
        //
        // The limit is now pagination's, applied after the filters. This service
        // returns the whole eligible set.
        config(['foodonthego.discovery.result_limit' => 5]);
        $this->app->forgetInstance(RestaurantDiscoveryService::class);

        foreach (range(1, 12) as $i) {
            RestaurantFixtures::nearRoute(0.05 * $i, 500, "Stop {$i}");
        }

        $this->assertCount(12, $this->discover()->restaurants);
    }
}

/**
 * A routing provider whose answers the test chooses.
 *
 * Mutable rather than replaced mid-test, for the reason Module 06 recorded:
 * Laravel caches a resolved controller on the route object, so swapping a
 * container binding between requests changes what `make()` returns and not what
 * an already-constructed service is holding.
 */
final class StubDetourProvider implements RouteProvider
{
    public int $calls = 0;

    public int $extraDistanceMetres = 1_200;

    public int $extraDurationSeconds = 180;

    public ?RouteFailureKind $failWith = null;

    public function name(): string
    {
        return 'stub';
    }

    public function calculate(RouteRequest $request): RouteResult
    {
        $this->calls++;

        if ($this->failWith !== null) {
            throw new RouteProviderException($this->failWith, 'stubbed failure');
        }

        // The base route this is compared against. Rebuilt from the request so
        // the stub does not need to know what the trip stored.
        $base = Distance::haversineMetres(
            new Coordinate($request->originLatitude, $request->originLongitude),
            new Coordinate($request->destinationLatitude, $request->destinationLongitude),
        );

        return new RouteResult([new RouteOption(
            index: 0,
            distanceMeters: (int) round($base) + $this->extraDistanceMetres,
            durationSeconds: 14_000 + $this->extraDurationSeconds,
            trafficDurationSeconds: null,
            encodedPolyline: PolylineCodec::encode([
                [$request->originLatitude, $request->originLongitude],
                [$request->destinationLatitude, $request->destinationLongitude],
            ]),
            bounds: new RouteBounds(
                north: max($request->originLatitude, $request->destinationLatitude),
                south: min($request->originLatitude, $request->destinationLatitude),
                east: max($request->originLongitude, $request->destinationLongitude),
                west: min($request->originLongitude, $request->destinationLongitude),
            ),
            summary: 'stub',
        )], $this->name());
    }
}
