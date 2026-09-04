<?php

declare(strict_types=1);

namespace Tests\Feature;

use App\Models\Restaurant;
use App\Models\Trip;
use App\Models\User;
use App\Services\Discovery\RestaurantDetourService;
use App\Services\Discovery\RestaurantDiscoveryService;
use App\Services\Routing\RouteProvider;
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\Support\CustomerFactory;
use Tests\Support\RestaurantFixtures;
use Tests\TestCase;
use Tests\Unit\StubDetourProvider;

/**
 * Whether this stays affordable when the restaurant table is not tiny.
 *
 * Discovery has two ways of becoming ruinous: scanning every restaurant for
 * every trip, and asking a billed routing provider about restaurants three
 * states away. These are the tests that would notice either.
 */
final class DiscoveryPerformanceTest extends TestCase
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

    /**
     * A restaurant table with a realistic shape: a handful on the road, and a
     * great many everywhere else in India.
     */
    private function seedNationalDataset(int $onRoute, int $elsewhere): void
    {
        for ($i = 0; $i < $onRoute; $i++) {
            RestaurantFixtures::nearRoute(
                0.05 + 0.9 * ($i / max(1, $onRoute)),
                400 + $i * 20,
                "On Route {$i}",
            );
        }

        // Scattered across the subcontinent, far from the Delhi-Jaipur corridor.
        $rows = [];

        for ($i = 0; $i < $elsewhere; $i++) {
            $rows[] = [
                'uuid' => Str::uuid()->toString(),
                'name' => "Elsewhere {$i}",
                'latitude' => 8.0 + ($i % 200) * 0.075,
                'longitude' => 68.5 + (($i * 7) % 300) * 0.06,
                'formatted_address' => 'Somewhere else',
                'city' => 'Elsewhere',
                'country_code' => 'IN',
                'timezone' => 'Asia/Kolkata',
                'status' => 'APPROVED',
                'verification_status' => 'VERIFIED',
                'is_discoverable' => true,
                'is_accepting_orders' => true,
                'rating_count' => 0,
                'created_at' => now(),
                'updated_at' => now(),
            ];
        }

        foreach (array_chunk($rows, 500) as $chunk) {
            DB::table('restaurants')->insert($chunk);
        }
    }

    public function test_the_corridor_filter_does_the_work_not_the_routing_provider(): void
    {
        $this->seedNationalDataset(onRoute: 8, elsewhere: 2_000);

        $this->assertSame(2_008, Restaurant::query()->discoverable()->count());

        $result = $this->app->make(RestaurantDiscoveryService::class)
            ->discover($this->trip, CarbonImmutable::now());

        // Two thousand restaurants in the table; the bounding box hands back a
        // small fraction of them, the corridor narrows that to the eight that
        // are actually on the road, and only those cost a provider call.
        $this->assertLessThan(2_008, $result->candidateCount);
        $this->assertSame(8, $result->withinCorridorCount);
        $this->assertLessThanOrEqual(
            (int) config('foodonthego.discovery.max_detour_evaluations'),
            $this->provider->calls,
        );
        $this->assertLessThanOrEqual(8, $this->provider->calls);
    }

    public function test_the_query_count_does_not_grow_with_the_result_count(): void
    {
        $this->seedNationalDataset(onRoute: 12, elsewhere: 200);

        DB::enableQueryLog();

        $this->app->make(RestaurantDiscoveryService::class)
            ->discover($this->trip, CarbonImmutable::now());

        $withTwelve = count(DB::getQueryLog());

        // A fresh trip and cache, and three times as many restaurants on the
        // road. Without eager loading, cuisines, facilities and opening hours
        // would each add a query per restaurant and this would roughly triple.
        DB::flushQueryLog();
        Cache::flush();

        $secondTrip = RestaurantFixtures::tripWithSelectedRoute($this->rahul);
        $this->seedNationalDataset(onRoute: 24, elsewhere: 0);

        DB::flushQueryLog();

        $this->app->make(RestaurantDiscoveryService::class)
            ->discover($secondTrip, CarbonImmutable::now());

        $withThirtySix = count(DB::getQueryLog());

        DB::disableQueryLog();

        $this->assertLessThanOrEqual($withTwelve + 2, $withThirtySix);
    }

    public function test_a_discovery_takes_a_small_number_of_queries(): void
    {
        $this->seedNationalDataset(onRoute: 10, elsewhere: 500);

        DB::enableQueryLog();

        $this->app->make(RestaurantDiscoveryService::class)
            ->discover($this->trip, CarbonImmutable::now());

        $queries = DB::getQueryLog();
        DB::disableQueryLog();

        // The trip, its route, the corridor query, and one each for cuisines,
        // facilities and opening hours. A handful, not a handful per restaurant.
        $this->assertLessThan(12, count($queries), sprintf(
            "discovery ran %d queries:\n%s",
            count($queries),
            implode("\n", array_map(
                static fn (array $q): string => substr((string) $q['query'], 0, 120),
                $queries,
            )),
        ));
    }

    public function test_a_cached_discovery_asks_the_provider_nothing(): void
    {
        $this->seedNationalDataset(onRoute: 6, elsewhere: 100);

        $service = $this->app->make(RestaurantDiscoveryService::class);

        $service->discover($this->trip, CarbonImmutable::now());
        $afterFirst = $this->provider->calls;

        $service->discover($this->trip->refresh(), CarbonImmutable::now());

        $this->assertSame($afterFirst, $this->provider->calls);
    }

    public function test_the_candidate_cap_bounds_the_work(): void
    {
        config(['foodonthego.discovery.max_candidates' => 25]);
        $this->app->forgetInstance(RestaurantDiscoveryService::class);

        $this->seedNationalDataset(onRoute: 60, elsewhere: 0);

        $result = $this->app->make(RestaurantDiscoveryService::class)
            ->discover($this->trip, CarbonImmutable::now());

        // A bound on the work, not on the answer. Sixty restaurants on the road
        // is a configuration problem — the corridor is too wide for the dataset
        // — and the cap keeps one request from becoming an outage while it is
        // sorted out.
        $this->assertSame(25, $result->candidateCount);
    }
}
