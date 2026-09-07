<?php

declare(strict_types=1);

namespace Tests\Feature;

use App\Models\MenuCategory;
use App\Models\MenuItem;
use App\Models\Restaurant;
use App\Models\Trip;
use App\Models\User;
use App\Services\Discovery\RestaurantDetourService;
use App\Services\Discovery\RestaurantDiscoveryService;
use App\Services\Routing\RouteProvider;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\Support\CustomerFactory;
use Tests\Support\MenuFixtures;
use Tests\Support\RestaurantFixtures;
use Tests\Support\SettlesQueryCounts;
use Tests\TestCase;
use Tests\Unit\StubDetourProvider;

/**
 * What opening a menu costs.
 *
 * Two ways a menu endpoint becomes expensive, and one way it becomes
 * ruinous. The expensive ones are a query per category and a query per item;
 * the ruinous one is a billed routing call on a screen a customer opens every
 * time they change their mind. All three are asserted here rather than
 * reasoned about, because all three are the kind of regression that a later
 * change introduces silently and that no functional test notices.
 *
 * The large menu here is generated in the test. Production data is never used
 * for a load measurement — a fixture that grows is the point.
 */
final class MenuPerformanceTest extends TestCase
{
    use RefreshDatabase;
    use SettlesQueryCounts;

    private User $rahul;

    private string $token;

    private Trip $trip;

    private Restaurant $restaurant;

    private StubDetourProvider $provider;

    protected function setUp(): void
    {
        parent::setUp();

        Cache::flush();

        $this->rahul = CustomerFactory::rahul();
        $this->token = CustomerFactory::tokenFor($this->rahul);
        $this->trip = RestaurantFixtures::tripWithSelectedRoute($this->rahul);
        $this->restaurant = RestaurantFixtures::nearRoute(0.4, 800, 'Highway Spice Kitchen');

        // A counting provider in place of the real one. Nothing in this module
        // should reach it; the count is how that is proved.
        $this->provider = new StubDetourProvider;
        $this->app->instance(RouteProvider::class, $this->provider);
        $this->app->forgetInstance(RestaurantDetourService::class);
        $this->app->forgetInstance(RestaurantDiscoveryService::class);
    }

    private function asRahul(): self
    {
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', 'Bearer '.$this->token);
    }

    private function menuUrl(?string $query = null): string
    {
        $path = '/api/v1/customer/trips/'.$this->trip->uuid
            .'/restaurants/'.$this->restaurant->uuid.'/menu';

        return $query === null ? $path : $path.'?'.$query;
    }

    /** The list the customer arrives through, which is what warms discovery. */
    private function openTheList(): void
    {
        $this->asRahul()
            ->getJson('/api/v1/customer/trips/'.$this->trip->uuid.'/restaurants')
            ->assertOk();
    }

    /** @return array{0: int, 1: float} queries, milliseconds */
    private function costOfOpeningTheMenu(?string $query = null): array
    {
        DB::flushQueryLog();
        DB::enableQueryLog();

        $start = hrtime(true);

        $this->asRahul()->getJson($this->menuUrl($query))->assertOk();

        $ms = (hrtime(true) - $start) / 1e6;
        $queries = count(DB::getQueryLog());

        DB::disableQueryLog();

        return [$queries, $ms];
    }

    /**
     * A menu of an arbitrary size, built in bulk.
     *
     * Inserted directly rather than through the fixtures: five hundred models
     * saved one at a time would make this test slower than the thing it
     * measures.
     */
    private function seedLargeMenu(int $categories, int $itemsPerCategory): void
    {
        $now = now();

        foreach (range(1, $categories) as $c) {
            $categoryId = DB::table('menu_categories')->insertGetId([
                'uuid' => (string) Str::uuid(),
                'restaurant_id' => $this->restaurant->id,
                'name' => "Section {$c}",
                'description' => "Everything in section {$c}.",
                'display_order' => $c,
                'is_active' => true,
                'created_at' => $now,
                'updated_at' => $now,
            ]);

            $rows = [];

            foreach (range(1, $itemsPerCategory) as $i) {
                $rows[] = [
                    'uuid' => (string) Str::uuid(),
                    'restaurant_id' => $this->restaurant->id,
                    'menu_category_id' => $categoryId,
                    'name' => "Section {$c} Dish {$i}",
                    'description' => 'A dish the kitchen makes.',
                    'base_price_minor' => 10_000 + $i * 100,
                    'currency' => 'INR',
                    'preparation_minutes' => 15,
                    'is_active' => true,
                    'stock_status' => 'IN_STOCK',
                    'display_order' => $i,
                    'created_at' => $now,
                    'updated_at' => $now,
                ];
            }

            DB::table('menu_items')->insert($rows);
        }
    }

    // --- N+1 -----------------------------------------------------------------

    public function test_the_query_count_does_not_grow_with_the_number_of_items(): void
    {
        $starters = MenuFixtures::category($this->restaurant, 'Starters', 0);
        MenuFixtures::item($starters, 'Paneer Tikka');

        $this->openTheList();

        $small = $this->queriesTouching(fn () => $this->costOfOpeningTheMenu(), ['menu_categories', 'menu_items']);

        foreach (range(1, 60) as $n) {
            MenuFixtures::item($starters, "Dish {$n}", 20_000 + $n, ['order' => $n]);
        }

        $large = $this->queriesTouching(fn () => $this->costOfOpeningTheMenu(), ['menu_categories', 'menu_items']);

        // Sixty more dishes are sixty more rows in the same query. If this ever
        // fails, something is reading a relation off an item in a loop.
        $this->assertSame($small, $large);
    }

    public function test_the_query_count_does_not_grow_with_the_number_of_categories(): void
    {
        MenuFixtures::ordinaryMenu($this->restaurant);

        $this->openTheList();

        $three = $this->queriesTouching(fn () => $this->costOfOpeningTheMenu(), ['menu_categories', 'menu_items']);

        $this->seedLargeMenu(categories: 17, itemsPerCategory: 4);

        $twenty = $this->queriesTouching(fn () => $this->costOfOpeningTheMenu(), ['menu_categories', 'menu_items']);

        $this->assertSame($three, $twenty);
    }

    public function test_the_whole_menu_is_two_queries_however_large_it_is(): void
    {
        $this->seedLargeMenu(categories: 20, itemsPerCategory: 25);

        $this->openTheList();
        $this->costOfOpeningTheMenu();

        DB::flushQueryLog();
        DB::enableQueryLog();

        $this->asRahul()->getJson($this->menuUrl())->assertOk();

        $log = DB::getQueryLog();
        DB::disableQueryLog();

        $menuQueries = array_values(array_filter(
            $log,
            static fn (array $entry): bool => str_contains((string) $entry['query'], 'menu_categories')
                || str_contains((string) $entry['query'], 'menu_items'),
        ));

        // One for the categories, one for all of their items. Not twenty-one,
        // and certainly not five hundred and twenty.
        $this->assertCount(2, $menuQueries);
    }

    // --- a five hundred item menu -------------------------------------------

    public function test_a_twenty_category_five_hundred_item_menu_is_served_whole(): void
    {
        $this->seedLargeMenu(categories: 20, itemsPerCategory: 25);

        $this->openTheList();
        $this->costOfOpeningTheMenu();

        [$queries, $ms] = $this->costOfOpeningTheMenu();

        $response = $this->asRahul()->getJson($this->menuUrl());
        $response->assertOk();

        $body = $response->json('data');

        $this->assertCount(20, $body['categories']);
        $this->assertSame(500, $body['meta']['item_count']);
        $this->assertSame(500, $body['meta']['visible_item_count']);

        $rendered = array_sum(array_map(
            static fn (array $category): int => count($category['items']),
            $body['categories'],
        ));

        // Every item is present. A menu is not paginated: a customer scrolling
        // a long menu should not discover that the second half needs a second
        // request they have no signal to make.
        $this->assertSame(500, $rendered);

        // Seventeen at the time of writing, of which two are the menu: the
        // rest are the token, the trip, its selected route and the cached
        // corridor read the eligibility check goes through. The budget is a
        // ceiling rather than a target — it is set where a single per-category
        // query (twenty more) or a per-item one (five hundred more) fails it,
        // and where ordinary drift does not.
        $this->assertLessThanOrEqual(20, $queries);
        $this->assertLessThan(1_500.0, $ms);
    }

    public function test_searching_a_five_hundred_item_menu_costs_no_more(): void
    {
        $this->seedLargeMenu(categories: 20, itemsPerCategory: 25);

        $this->openTheList();

        $whole = $this->queriesTouching(fn () => $this->costOfOpeningTheMenu(), ['menu_categories', 'menu_items']);
        $searched = $this->queriesTouching(
            fn () => $this->costOfOpeningTheMenu('search=Dish+7'),
            ['menu_categories', 'menu_items'],
        );
        [, $ms] = $this->costOfOpeningTheMenu('search=Dish+7');

        // The search narrows in memory over rows already fetched, so it costs
        // the same two queries rather than a third.
        $this->assertSame($whole, $searched);
        $this->assertLessThan(1_500.0, $ms);
    }

    // --- cost control --------------------------------------------------------

    public function test_opening_a_menu_asks_the_routing_provider_nothing(): void
    {
        MenuFixtures::ordinaryMenu($this->restaurant);

        $this->openTheList();

        $afterTheList = $this->provider->calls;

        $this->asRahul()->getJson($this->menuUrl())->assertOk();
        $this->asRahul()->getJson($this->menuUrl('search=paneer'))->assertOk();
        $this->asRahul()->getJson($this->menuUrl())->assertOk();

        // The mandatory one. A menu is opened, searched, and backed out of
        // dozens of times in a single journey; a billed call on any of those
        // would make the screen cost more than the order.
        $this->assertSame($afterTheList, $this->provider->calls);
    }

    public function test_opening_an_item_asks_the_routing_provider_nothing(): void
    {
        $categories = MenuFixtures::ordinaryMenu($this->restaurant);
        $item = $categories['starters']->items()->firstOrFail();

        $this->openTheList();

        $afterTheList = $this->provider->calls;

        foreach (range(1, 5) as $ignored) {
            $this->asRahul()->getJson($this->menuUrl().'/items/'.$item->uuid)->assertOk();
        }

        $this->assertSame($afterTheList, $this->provider->calls);
    }

    public function test_a_menu_stores_no_route_and_recalculates_nothing(): void
    {
        MenuFixtures::ordinaryMenu($this->restaurant);

        $this->openTheList();

        $routesBefore = DB::table('trip_routes')->count();

        $this->asRahul()->getJson($this->menuUrl())->assertOk();

        // No new route row, and none rewritten: the menu screen reads the trip,
        // it does not re-plan it.
        $this->assertSame($routesBefore, DB::table('trip_routes')->count());
    }

    public function test_opening_the_same_menu_repeatedly_costs_the_same(): void
    {
        MenuFixtures::ordinaryMenu($this->restaurant);

        $this->openTheList();
        $this->settledQueryCount(fn (): array => $this->costOfOpeningTheMenu());

        $counts = [];

        foreach (range(1, 4) as $ignored) {
            [$queries] = $this->costOfOpeningTheMenu();
            $counts[] = $queries;
        }

        // Backing out of a menu and opening it again is what a customer
        // comparing two restaurants actually does.
        $this->assertSame([$counts[0]], array_values(array_unique($counts)));
    }

    // --- payload -------------------------------------------------------------

    public function test_a_large_menu_payload_stays_within_reason(): void
    {
        $this->seedLargeMenu(categories: 20, itemsPerCategory: 25);

        $this->openTheList();

        $body = $this->asRahul()->getJson($this->menuUrl())->assertOk()->getContent();

        $bytes = strlen((string) $body);

        // Five hundred items in well under a megabyte. This is the assertion
        // that would notice a future field carrying a whole nested object per
        // item, on a screen customers open over mobile data at a petrol pump.
        $this->assertLessThan(600_000, $bytes);
        $this->assertGreaterThan(50_000, $bytes);
    }

    public function test_the_item_count_matches_what_the_database_holds(): void
    {
        $this->seedLargeMenu(categories: 20, itemsPerCategory: 25);

        $this->openTheList();

        $body = $this->asRahul()->getJson($this->menuUrl())->assertOk()->json('data');

        $this->assertSame(
            MenuItem::query()->where('restaurant_id', $this->restaurant->id)->count(),
            $body['meta']['visible_item_count'],
        );

        $this->assertSame(
            MenuCategory::query()->where('restaurant_id', $this->restaurant->id)->count(),
            $body['meta']['category_count'],
        );
    }
}
