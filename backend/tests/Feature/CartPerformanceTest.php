<?php

declare(strict_types=1);

namespace Tests\Feature;

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
use Tests\Support\CustomerFactory;
use Tests\Support\MenuFixtures;
use Tests\Support\RestaurantFixtures;
use Tests\TestCase;
use Tests\Unit\StubDetourProvider;

/**
 * What configuring a dish and adding it costs.
 *
 * Two ways this gets expensive — a query per modifier group, a query per
 * option — and one way it gets ruinous: a billed routing call on a screen a
 * customer opens for every dish they consider. All three are asserted rather
 * than reasoned about.
 */
final class CartPerformanceTest extends TestCase
{
    use RefreshDatabase;

    private User $rahul;

    private string $token;

    private Trip $trip;

    private Restaurant $restaurant;

    /** @var array<string, mixed> */
    private array $menu;

    private StubDetourProvider $provider;

    protected function setUp(): void
    {
        parent::setUp();

        Cache::flush();

        $this->rahul = CustomerFactory::rahul();
        $this->token = CustomerFactory::tokenFor($this->rahul);
        $this->trip = RestaurantFixtures::tripWithSelectedRoute($this->rahul);
        $this->restaurant = RestaurantFixtures::nearRoute(0.4, 800, 'Highway Spice Kitchen');
        $this->menu = MenuFixtures::configurableItem($this->restaurant);

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

    private function itemUrl(): string
    {
        return '/api/v1/customer/trips/'.$this->trip->uuid
            .'/restaurants/'.$this->restaurant->uuid
            .'/menu/items/'.$this->menu['item']->uuid;
    }

    private function cartUrl(): string
    {
        return '/api/v1/customer/trips/'.$this->trip->uuid
            .'/restaurants/'.$this->restaurant->uuid.'/cart/items';
    }

    private function openTheList(): void
    {
        $this->asRahul()
            ->getJson('/api/v1/customer/trips/'.$this->trip->uuid.'/restaurants')
            ->assertOk();
    }

    /** @return array{0: int, 1: float} queries, milliseconds */
    private function costOfOpeningTheItem(): array
    {
        DB::flushQueryLog();
        DB::enableQueryLog();

        $start = hrtime(true);

        $this->asRahul()->getJson($this->itemUrl())->assertOk();

        $ms = (hrtime(true) - $start) / 1e6;
        $queries = count(DB::getQueryLog());

        DB::disableQueryLog();

        return [$queries, $ms];
    }

    /**
     * A dish with an arbitrary number of questions and answers.
     *
     * @return list<string> the option uuids that satisfy every required group
     */
    private function seedLargeCustomization(MenuItem $item, int $groups, int $optionsPerGroup): array
    {
        $required = [];

        foreach (range(1, $groups) as $g) {
            // Half the groups required, half optional — a screen that only ever
            // meets one kind is a screen whose other branch nobody has scrolled.
            $isRequired = $g % 2 === 1;

            $group = MenuFixtures::group(
                $this->restaurant,
                "Group {$g}",
                $isRequired ? 1 : 0,
                $isRequired ? 1 : 3,
                ['order' => 10 + $g],
            );

            foreach (range(1, $optionsPerGroup) as $o) {
                $option = MenuFixtures::option($group, "Group {$g} option {$o}", $o * 500, ['order' => $o]);

                if ($isRequired && $o === 1) {
                    $required[] = $option->uuid;
                }
            }

            MenuFixtures::attach($item, $group, 10 + $g);
        }

        return $required;
    }

    // --- N+1 -----------------------------------------------------------------

    public function test_the_query_count_does_not_grow_with_the_number_of_options(): void
    {
        $this->openTheList();

        // One un-measured open first: the first request of a session warms the
        // token lookup and the rate limiter's bucket, and counting those makes
        // a comparison of two requests wrong by exactly one.
        $this->costOfOpeningTheItem();

        [$small] = $this->costOfOpeningTheItem();

        $this->seedLargeCustomization($this->menu['item'], groups: 1, optionsPerGroup: 40);

        [$large] = $this->costOfOpeningTheItem();

        // Forty more options are forty more rows in the same query.
        $this->assertSame($small, $large);
    }

    public function test_the_query_count_does_not_grow_with_the_number_of_groups(): void
    {
        $this->openTheList();
        $this->costOfOpeningTheItem();

        [$two] = $this->costOfOpeningTheItem();

        $this->seedLargeCustomization($this->menu['item'], groups: 8, optionsPerGroup: 5);

        [$ten] = $this->costOfOpeningTheItem();

        $this->assertSame($two, $ten);
    }

    public function test_the_customization_is_three_queries_however_large_it_is(): void
    {
        $this->seedLargeCustomization($this->menu['item'], groups: 8, optionsPerGroup: 10);

        $this->openTheList();
        $this->costOfOpeningTheItem();

        DB::flushQueryLog();
        DB::enableQueryLog();

        $this->asRahul()->getJson($this->itemUrl())->assertOk();

        $log = DB::getQueryLog();
        DB::disableQueryLog();

        $customization = array_values(array_filter(
            $log,
            static fn (array $entry): bool => str_contains((string) $entry['query'], 'menu_item_variants')
                || str_contains((string) $entry['query'], 'menu_modifier_groups')
                || str_contains((string) $entry['query'], 'menu_modifier_options'),
        ));

        // One for the sizes, one for the groups, one for all of their options.
        // Not one per group, and certainly not one per option.
        $this->assertCount(3, $customization);
    }

    public function test_a_large_customization_is_served_whole(): void
    {
        $required = $this->seedLargeCustomization($this->menu['item'], groups: 8, optionsPerGroup: 10);

        $this->openTheList();
        $this->costOfOpeningTheItem();

        [$queries, $ms] = $this->costOfOpeningTheItem();

        $body = $this->asRahul()->getJson($this->itemUrl())->assertOk()->json('data.customization');

        // Two original groups plus eight.
        $this->assertCount(10, $body['modifier_groups']);

        $options = array_sum(array_map(
            static fn (array $group): int => count($group['options']),
            $body['modifier_groups'],
        ));

        // 3 spice + 2 extras + 80.
        $this->assertSame(85, $options);

        $this->assertLessThanOrEqual(20, $queries);
        $this->assertLessThan(1_500.0, $ms);

        // And the whole thing can still be added, required groups and all.
        $this->asRahul()
            ->postJson($this->cartUrl(), [
                'item_id' => $this->menu['item']->uuid,
                'variant_id' => $this->menu['large']->uuid,
                'modifier_option_ids' => [$this->menu['mild']->uuid, ...$required],
                'quantity' => 1,
            ])
            ->assertCreated();
    }

    public function test_adding_to_a_cart_reads_no_more_for_a_larger_customization(): void
    {
        $required = $this->seedLargeCustomization($this->menu['item'], groups: 8, optionsPerGroup: 10);

        $this->openTheList();

        $body = fn (array $options, string $note): array => [
            'item_id' => $this->menu['item']->uuid,
            'variant_id' => $this->menu['large']->uuid,
            'modifier_option_ids' => $options,
            'quantity' => 1,
            'special_instructions' => $note,
        ];

        // One add first, to warm the token lookup and the rate limiter's
        // bucket. It answers every required group too — a half-configured
        // warm-up would be refused and nothing below would run.
        $this->asRahul()
            ->postJson($this->cartUrl(), $body([$this->menu['mild']->uuid, ...$required], 'warm'))
            ->assertCreated();

        $measure = function (array $options, string $note): array {
            DB::flushQueryLog();
            DB::enableQueryLog();

            $this->asRahul()->postJson($this->cartUrl(), $options)->assertCreated();

            $log = DB::getQueryLog();
            DB::disableQueryLog();

            $reads = array_filter(
                $log,
                static fn (array $q): bool => str_starts_with(strtolower(trim((string) $q['query'])), 'select'),
            );

            return [count($log), count($reads)];
        };

        // The same dish with one option, and with five.
        [, $fewReads] = $measure($body([$this->menu['mild']->uuid, ...$required], 'a'), 'a');
        [, $manyReads] = $measure(
            $body([$this->menu['mild']->uuid, $this->menu['cheese']->uuid, ...$required], 'b'),
            'b',
        );

        // **Reads** are what an N+1 would grow. The inserts grow by exactly one
        // per option, which is a row being written rather than a query being
        // repeated, so they are counted separately and deliberately excluded.
        $this->assertSame($fewReads, $manyReads);
    }

    // --- cost control --------------------------------------------------------

    public function test_opening_an_item_asks_the_routing_provider_nothing(): void
    {
        $this->openTheList();

        $before = $this->provider->calls;

        foreach (range(1, 5) as $ignored) {
            $this->asRahul()->getJson($this->itemUrl())->assertOk();
        }

        $this->assertSame($before, $this->provider->calls);
    }

    public function test_adding_to_a_cart_asks_the_routing_provider_nothing(): void
    {
        $this->openTheList();

        $before = $this->provider->calls;

        foreach (range(1, 5) as $n) {
            $this->asRahul()
                ->postJson($this->cartUrl(), [
                    'item_id' => $this->menu['item']->uuid,
                    'variant_id' => $this->menu['large']->uuid,
                    'modifier_option_ids' => [$this->menu['mild']->uuid],
                    'quantity' => 1,
                    'special_instructions' => "note {$n}",
                ])
                ->assertCreated();
        }

        // The mandatory one. A customer configuring three dishes at a petrol
        // pump must not spend anything doing it.
        $this->assertSame($before, $this->provider->calls);
    }

    public function test_reading_the_cart_badge_asks_the_routing_provider_nothing(): void
    {
        $this->openTheList();

        $before = $this->provider->calls;

        foreach (range(1, 5) as $ignored) {
            $this->asRahul()
                ->getJson('/api/v1/customer/trips/'.$this->trip->uuid.'/cart')
                ->assertOk();
        }

        $this->assertSame($before, $this->provider->calls);
    }

    public function test_adding_to_a_cart_changes_no_menu_data(): void
    {
        $this->openTheList();

        $items = DB::table('menu_items')->pluck('updated_at', 'id')->toArray();
        $variants = DB::table('menu_item_variants')->pluck('updated_at', 'id')->toArray();
        $options = DB::table('menu_modifier_options')->pluck('updated_at', 'id')->toArray();

        $this->asRahul()
            ->postJson($this->cartUrl(), [
                'item_id' => $this->menu['item']->uuid,
                'variant_id' => $this->menu['large']->uuid,
                'modifier_option_ids' => [$this->menu['mild']->uuid],
                'quantity' => 2,
            ])
            ->assertCreated();

        // A cart is a customer's private list. Filling one must not touch the
        // restaurant's menu.
        $this->assertSame($items, DB::table('menu_items')->pluck('updated_at', 'id')->toArray());
        $this->assertSame($variants, DB::table('menu_item_variants')->pluck('updated_at', 'id')->toArray());
        $this->assertSame($options, DB::table('menu_modifier_options')->pluck('updated_at', 'id')->toArray());
    }
}
