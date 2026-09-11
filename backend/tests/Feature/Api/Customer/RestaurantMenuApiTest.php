<?php

declare(strict_types=1);

namespace Tests\Feature\Api\Customer;

use App\Enums\ApiErrorCode;
use App\Enums\MenuItemDietaryType;
use App\Enums\MenuItemStockStatus;
use App\Enums\RestaurantStatus;
use App\Models\MenuCategory;
use App\Models\MenuItem;
use App\Models\Restaurant;
use App\Models\Trip;
use App\Models\User;
use App\Services\Menu\MenuQuery;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Str;
use Tests\Support\CustomerFactory;
use Tests\Support\MenuFixtures;
use Tests\Support\RestaurantFixtures;
use Tests\TestCase;

/**
 * A restaurant's menu, as a client sees it.
 *
 * Three things this file exists to prove, all negative: an inactive category or
 * item cannot be reached by any route, an item belonging to one restaurant
 * cannot be read through another, and nothing an operator considers private
 * appears in a customer's payload.
 */
final class RestaurantMenuApiTest extends TestCase
{
    use RefreshDatabase;

    private User $rahul;

    private string $token;

    private Trip $trip;

    private Restaurant $restaurant;

    protected function setUp(): void
    {
        parent::setUp();

        Cache::flush();

        $this->rahul = CustomerFactory::rahul();
        $this->token = CustomerFactory::tokenFor($this->rahul);
        $this->trip = RestaurantFixtures::tripWithSelectedRoute($this->rahul);
        $this->restaurant = RestaurantFixtures::nearRoute(0.4, 800, 'Highway Spice Kitchen');
    }

    private function asRahul(): self
    {
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', 'Bearer '.$this->token);
    }

    private function url(?string $query = null, ?Restaurant $restaurant = null): string
    {
        $path = '/api/v1/customer/trips/'.$this->trip->uuid
            .'/restaurants/'.($restaurant ?? $this->restaurant)->uuid.'/menu';

        return $query === null ? $path : $path.'?'.$query;
    }

    private function itemUrl(string $itemUuid, ?Restaurant $restaurant = null): string
    {
        return $this->url(null, $restaurant).'/items/'.$itemUuid;
    }

    // --- the happy path ------------------------------------------------------

    public function test_a_customer_reads_a_restaurants_menu(): void
    {
        MenuFixtures::ordinaryMenu($this->restaurant);

        $this->asRahul()->getJson($this->url())
            ->assertOk()
            ->assertJsonPath('data.restaurant.name', 'Highway Spice Kitchen')
            ->assertJsonPath('data.restaurant.ordering.can_order', true)
            ->assertJsonPath('data.categories.0.name', 'Starters')
            ->assertJsonPath('data.categories.0.items.0.name', 'Paneer Tikka')
            ->assertJsonPath('data.meta.category_count', 3)
            ->assertJsonPath('data.meta.item_count', 6)
            ->assertJsonStructure(['data' => [
                'restaurant' => ['id', 'name', 'availability', 'ordering'],
                'categories' => [['id', 'name', 'description', 'items' => [[
                    'id', 'category_id', 'name', 'description',
                    'price' => ['amount_minor', 'currency'],
                    'image_url', 'thumbnail_url', 'preparation_minutes',
                    'dietary_type', 'stock_status', 'is_orderable',
                ]]]],
                'meta' => ['category_count', 'item_count', 'visible_item_count', 'generated_at'],
            ]]);
    }

    public function test_a_price_is_minor_units_and_a_currency_never_a_string(): void
    {
        MenuFixtures::ordinaryMenu($this->restaurant);

        $price = $this->asRahul()->getJson($this->url())
            ->assertOk()
            ->json('data.categories.0.items.0.price');

        // What a price looks like is a locale decision, and the server does not
        // know the customer's. It sends the number and the currency.
        $this->assertSame(24_900, $price['amount_minor']);
        $this->assertSame('INR', $price['currency']);
        $this->assertIsInt($price['amount_minor']);
    }

    public function test_a_free_item_is_zero_not_missing(): void
    {
        MenuFixtures::ordinaryMenu($this->restaurant);

        $water = $this->asRahul()->getJson($this->url())
            ->assertOk()
            ->json('data.categories.2.items.1');

        $this->assertSame('Table Water', $water['name']);
        $this->assertSame(0, $water['price']['amount_minor']);
    }

    public function test_categories_and_items_come_back_in_the_operators_order(): void
    {
        $second = MenuFixtures::category($this->restaurant, 'Zebra Course', 1);
        $first = MenuFixtures::category($this->restaurant, 'Aardvark Course', 0);

        MenuFixtures::item($second, 'Beta', 100, ['order' => 1]);
        MenuFixtures::item($second, 'Alpha', 100, ['order' => 0]);
        MenuFixtures::item($first, 'Only', 100);

        $data = $this->asRahul()->getJson($this->url())->assertOk()->json('data');

        // The operator's order, never alphabetical. A restaurant that puts
        // Breakfast first has a reason.
        $this->assertSame(
            ['Aardvark Course', 'Zebra Course'],
            array_column($data['categories'], 'name'),
        );
        $this->assertSame(
            ['Alpha', 'Beta'],
            array_column($data['categories'][1]['items'], 'name'),
        );
    }

    // --- what a customer may not see -----------------------------------------

    public function test_an_inactive_category_is_absent_and_so_are_its_items(): void
    {
        $live = MenuFixtures::category($this->restaurant, 'Starters', 0);
        MenuFixtures::item($live, 'Paneer Tikka');

        $withdrawn = MenuFixtures::category($this->restaurant, 'Desserts', 1, ['active' => false]);
        $hidden = MenuFixtures::item($withdrawn, 'Gulab Jamun');

        $body = $this->asRahul()->getJson($this->url())->assertOk()->content();

        $this->assertStringNotContainsString('Desserts', $body);
        $this->assertStringNotContainsString('Gulab Jamun', $body);

        // And the item does not leak through its own endpoint either. Taking a
        // category off the menu must take its items with it.
        $this->asRahul()->getJson($this->itemUrl($hidden->uuid))
            ->assertNotFound()
            ->assertJsonPath('error.code', ApiErrorCode::ItemNotFound->value);
    }

    public function test_an_inactive_item_is_absent(): void
    {
        $starters = MenuFixtures::category($this->restaurant, 'Starters', 0);
        MenuFixtures::item($starters, 'Paneer Tikka');
        $withdrawn = MenuFixtures::item($starters, 'Discontinued Kebab', 100, ['active' => false]);

        $body = $this->asRahul()->getJson($this->url())->assertOk()->content();

        $this->assertStringNotContainsString('Discontinued Kebab', $body);

        $this->asRahul()->getJson($this->itemUrl($withdrawn->uuid))->assertNotFound();
    }

    public function test_a_category_with_no_visible_items_is_omitted(): void
    {
        $full = MenuFixtures::category($this->restaurant, 'Starters', 0);
        MenuFixtures::item($full, 'Paneer Tikka');

        $empty = MenuFixtures::category($this->restaurant, 'Desserts', 1);
        MenuFixtures::item($empty, 'Withdrawn Sweet', 100, ['active' => false]);

        $categories = $this->asRahul()->getJson($this->url())
            ->assertOk()
            ->json('data.categories');

        // "Desserts — no items" is a row that answers a question nobody asked.
        $this->assertSame(['Starters'], array_column($categories, 'name'));
    }

    public function test_a_category_outside_its_serving_hours_is_absent(): void
    {
        $allDay = MenuFixtures::category($this->restaurant, 'Main Course', 1);
        MenuFixtures::item($allDay, 'Dal Makhani');

        // A window that has certainly passed or not yet come, whatever the hour
        // this test runs at: one minute wide, in the middle of the night.
        $breakfast = MenuFixtures::category($this->restaurant, 'Breakfast', 0, [
            'from' => '03:00:00',
            'until' => '03:01:00',
        ]);
        MenuFixtures::item($breakfast, 'Aloo Paratha');

        $names = array_column(
            $this->asRahul()->getJson($this->url())->assertOk()->json('data.categories'),
            'name',
        );

        $this->assertSame(['Main Course'], $names);
    }

    // --- cross-restaurant ----------------------------------------------------

    public function test_an_item_from_another_restaurant_cannot_be_read_here(): void
    {
        $mine = MenuFixtures::category($this->restaurant, 'Starters', 0);
        MenuFixtures::item($mine, 'Paneer Tikka');

        $other = RestaurantFixtures::nearRoute(0.5, 900, 'Rajasthan Highway Bites');
        $theirCategory = MenuFixtures::category($other, 'Snacks', 0);
        $theirItem = MenuFixtures::item($theirCategory, 'Pyaaz Kachori');

        // Both restaurants are on the route and both are eligible. The refusal
        // is about the item belonging to the other one.
        $this->asRahul()->getJson($this->itemUrl($theirItem->uuid))
            ->assertNotFound()
            ->assertJsonPath('error.code', ApiErrorCode::ItemNotFound->value);

        // And it reads perfectly well under its own restaurant.
        $this->asRahul()->getJson($this->itemUrl($theirItem->uuid, $other))
            ->assertOk()
            ->assertJsonPath('data.item.name', 'Pyaaz Kachori');
    }

    public function test_a_menu_never_contains_another_restaurants_items(): void
    {
        $mine = MenuFixtures::category($this->restaurant, 'Starters', 0);
        MenuFixtures::item($mine, 'Paneer Tikka');

        $other = RestaurantFixtures::nearRoute(0.5, 900, 'Rajasthan Highway Bites');
        MenuFixtures::item(
            MenuFixtures::category($other, 'Snacks', 0),
            'Pyaaz Kachori',
        );

        $body = $this->asRahul()->getJson($this->url())->assertOk()->content();

        $this->assertStringNotContainsString('Pyaaz Kachori', $body);
    }

    public function test_the_database_itself_refuses_a_cross_restaurant_item(): void
    {
        $other = RestaurantFixtures::nearRoute(0.5, 900, 'Rajasthan Highway Bites');
        $theirCategory = MenuFixtures::category($other, 'Snacks', 0);

        // Not a service check — a composite foreign key. A future operator
        // dashboard cannot make this mistake either.
        $this->expectException(QueryException::class);

        $item = new MenuItem;
        $item->forceFill([
            'uuid' => (string) Str::uuid(),
            'restaurant_id' => $this->restaurant->id,
            'menu_category_id' => $theirCategory->id,
            'name' => 'Impossible',
            'base_price_minor' => 100,
        ])->save();
    }

    // --- restaurant eligibility ----------------------------------------------

    public function test_a_suspended_restaurants_menu_cannot_be_opened(): void
    {
        MenuFixtures::ordinaryMenu($this->restaurant);

        $this->asRahul()->getJson($this->url())->assertOk();

        $this->restaurant->forceFill(['status' => RestaurantStatus::Suspended])->save();

        // The race the module has to survive: the menu was one tap away.
        $this->asRahul()->getJson($this->url())
            ->assertNotFound()
            ->assertJsonPath('error.code', ApiErrorCode::RestaurantUnavailable->value);
    }

    public function test_an_unverified_restaurants_menu_cannot_be_opened(): void
    {
        $pending = Restaurant::factory()->discoverable()->pendingVerification()->named('Pending')
            ->at(...RestaurantFixtures::offset(
                0.4, 800, RestaurantFixtures::ORIGIN, RestaurantFixtures::DESTINATION,
            ))
            ->create();

        MenuFixtures::item(MenuFixtures::category($pending, 'Starters', 0), 'Secret Dish');

        $response = $this->asRahul()->getJson($this->url(null, $pending))->assertNotFound();

        $this->assertStringNotContainsString('Secret Dish', $response->content());
    }

    public function test_an_unauthenticated_call_reaches_no_menu(): void
    {
        MenuFixtures::ordinaryMenu($this->restaurant);

        $this->getJson($this->url())->assertUnauthorized();
    }

    public function test_a_foreign_trip_is_not_found(): void
    {
        MenuFixtures::ordinaryMenu($this->restaurant);

        $ananya = CustomerFactory::ananya();
        $hers = RestaurantFixtures::tripWithSelectedRoute($ananya);

        $this->asRahul()->getJson(
            '/api/v1/customer/trips/'.$hers->uuid
            .'/restaurants/'.$this->restaurant->uuid.'/menu',
        )->assertNotFound();
    }

    public function test_a_trip_with_no_route_is_refused(): void
    {
        MenuFixtures::ordinaryMenu($this->restaurant);

        $bare = Trip::factory()->ownedBy($this->rahul)->create();

        $this->asRahul()->getJson(
            '/api/v1/customer/trips/'.$bare->uuid
            .'/restaurants/'.$this->restaurant->uuid.'/menu',
        )
            ->assertStatus(409)
            ->assertJsonPath('error.code', ApiErrorCode::RouteNotReady->value);
    }

    // --- availability --------------------------------------------------------

    public function test_a_sold_out_item_is_shown_and_marked(): void
    {
        $starters = MenuFixtures::category($this->restaurant, 'Starters', 0);
        MenuFixtures::item($starters, 'Tandoori Mushroom', 27_900, [
            'stock' => MenuItemStockStatus::SoldOut,
        ]);

        $item = $this->asRahul()->getJson($this->url())
            ->assertOk()
            ->json('data.categories.0.items.0');

        // Shown deliberately: a traveller deciding where to stop wants to know
        // the restaurant makes it at all.
        $this->assertSame('Tandoori Mushroom', $item['name']);
        $this->assertSame('SOLD_OUT', $item['stock_status']);
        $this->assertFalse($item['is_orderable']);
    }

    public function test_a_paused_restaurant_still_serves_its_menu(): void
    {
        MenuFixtures::ordinaryMenu($this->restaurant);

        $this->restaurant->forceFill(['is_accepting_orders' => false])->save();

        $this->asRahul()->getJson($this->url())
            ->assertOk()
            ->assertJsonPath('data.restaurant.ordering.state', 'OPEN_PAUSED')
            ->assertJsonPath('data.restaurant.ordering.can_order', false)
            // Browsing is still allowed: the pause may lift before the
            // traveller arrives.
            ->assertJsonPath('data.restaurant.ordering.can_browse_menu', true)
            ->assertJsonPath('data.meta.item_count', 6);
    }

    public function test_a_closed_restaurant_still_serves_its_menu(): void
    {
        // Pinned, like the availability tests it shares a fixture with. A
        // restaurant opening at 02:00 local is genuinely OPEN between 02:00 and
        // 03:00 IST — 20:30 to 21:30 UTC — and this assertion would fail there
        // because the code was right. 06:30 UTC is noon in Kolkata: hours from
        // either edge of the window and from either soon-threshold.
        Carbon::setTestNow('2026-09-07 06:30:00');
        $closed = RestaurantFixtures::nearRoute(0.45, 800, 'Shut Cafe', open: false);
        RestaurantFixtures::openDaily($closed, '02:00:00', '03:00:00');
        MenuFixtures::ordinaryMenu($closed);

        $this->asRahul()->getJson($this->url(null, $closed))
            ->assertOk()
            ->assertJsonPath('data.restaurant.ordering.state', 'CLOSED')
            ->assertJsonPath('data.restaurant.ordering.can_order', false)
            ->assertJsonPath('data.restaurant.ordering.can_browse_menu', true);
    }

    // --- optional metadata ---------------------------------------------------

    public function test_metadata_a_restaurant_did_not_give_is_null_not_invented(): void
    {
        $starters = MenuFixtures::category($this->restaurant, 'Starters', 0);
        MenuFixtures::item($starters, 'Papad', 4_900);

        $item = $this->asRahul()->getJson($this->url())
            ->assertOk()
            ->json('data.categories.0.items.0');

        $this->assertNull($item['description']);
        $this->assertNull($item['image_url']);
        $this->assertNull($item['preparation_minutes']);
        $this->assertNull($item['dietary_type']);
        $this->assertNull($item['spice_level']);
    }

    public function test_a_dietary_type_is_the_declared_one(): void
    {
        $starters = MenuFixtures::category($this->restaurant, 'Starters', 0);
        MenuFixtures::item($starters, 'Paneer Tikka', 24_900, [
            'dietary' => MenuItemDietaryType::Vegetarian,
        ]);
        MenuFixtures::item($starters, 'Chicken Kebab', 32_900, [
            'dietary' => MenuItemDietaryType::NonVegetarian,
            'order' => 1,
        ]);

        $items = $this->asRahul()->getJson($this->url())
            ->assertOk()
            ->json('data.categories.0.items');

        $this->assertSame(
            ['VEGETARIAN', 'NON_VEGETARIAN'],
            array_column($items, 'dietary_type'),
        );
    }

    public function test_an_absurd_preparation_time_is_withheld_rather_than_shown(): void
    {
        $starters = MenuFixtures::category($this->restaurant, 'Starters', 0);
        $item = MenuFixtures::item($starters, 'Slow Dish', 24_900, [
            'preparation_minutes' => 15,
        ]);

        // A legacy row somebody typed wrong. Not repeated to a customer.
        $item->forceFill(['preparation_minutes' => 9_000])->save();

        $this->assertNull(
            $this->asRahul()->getJson($this->url())
                ->assertOk()
                ->json('data.categories.0.items.0.preparation_minutes'),
        );
    }

    public function test_a_thumbnail_falls_back_to_the_full_image(): void
    {
        $starters = MenuFixtures::category($this->restaurant, 'Starters', 0);
        MenuFixtures::item($starters, 'Paneer Tikka', 24_900, [
            'image' => 'https://cdn.example.test/paneer.jpg',
        ]);

        $item = $this->asRahul()->getJson($this->url())
            ->assertOk()
            ->json('data.categories.0.items.0');

        $this->assertSame('https://cdn.example.test/paneer.jpg', $item['thumbnail_url']);
    }

    // --- search ---------------------------------------------------------------

    public function test_a_search_narrows_the_menu(): void
    {
        MenuFixtures::ordinaryMenu($this->restaurant);

        $data = $this->asRahul()->getJson($this->url('search=paneer'))
            ->assertOk()
            ->json('data');

        $names = [];
        foreach ($data['categories'] as $category) {
            $names = [...$names, ...array_column($category['items'], 'name')];
        }

        $this->assertSame(['Paneer Tikka', 'Paneer Butter Masala'], $names);
        $this->assertSame(2, $data['meta']['item_count']);
        $this->assertSame(6, $data['meta']['visible_item_count']);
    }

    public function test_a_search_for_a_category_keeps_all_of_it(): void
    {
        MenuFixtures::ordinaryMenu($this->restaurant);

        $data = $this->asRahul()->getJson($this->url('search=beverages'))
            ->assertOk()
            ->json('data');

        // Being shown one of two beverages, because the other does not have the
        // word "beverage" in its name, is worse than useless.
        $this->assertSame(2, $data['meta']['item_count']);
    }

    public function test_a_search_that_matches_nothing_is_its_own_state(): void
    {
        MenuFixtures::ordinaryMenu($this->restaurant);

        $this->asRahul()->getJson($this->url('search=sushi'))
            ->assertOk()
            ->assertJsonPath('data.categories', [])
            ->assertJsonPath('data.meta.item_count', 0)
            // Which is what lets the screen say "nothing matched" rather than
            // "this restaurant has no menu".
            ->assertJsonPath('data.meta.visible_item_count', 6)
            ->assertJsonPath('data.meta.search_empty', true)
            ->assertJsonPath('data.meta.menu_empty', false);
    }

    public function test_a_search_cannot_reach_a_withdrawn_item(): void
    {
        $starters = MenuFixtures::category($this->restaurant, 'Starters', 0);
        MenuFixtures::item($starters, 'Paneer Tikka');
        MenuFixtures::item($starters, 'Paneer Discontinued', 100, ['active' => false]);

        $body = $this->asRahul()->getJson($this->url('search=paneer'))
            ->assertOk()
            ->content();

        // Structural: the withdrawn item was never loaded, so there is nothing
        // for the search to find.
        $this->assertStringNotContainsString('Paneer Discontinued', $body);
    }

    public function test_a_search_ignores_case_and_accents(): void
    {
        $starters = MenuFixtures::category($this->restaurant, 'Starters', 0);
        MenuFixtures::item($starters, 'Café Special');

        $this->asRahul()->getJson($this->url('search=CAFE'))
            ->assertOk()
            ->assertJsonPath('data.meta.item_count', 1);
    }

    public function test_a_single_character_search_is_treated_as_no_search(): void
    {
        MenuFixtures::ordinaryMenu($this->restaurant);

        // A customer mid-keystroke. Refusing them would put an error on screen
        // between the first letter and the second.
        $this->asRahul()->getJson($this->url('search=p'))
            ->assertOk()
            ->assertJsonPath('data.meta.item_count', 6)
            ->assertJsonPath('data.meta.applied.search', null);
    }

    public function test_an_oversized_search_is_refused(): void
    {
        MenuFixtures::ordinaryMenu($this->restaurant);

        $this->asRahul()->getJson(
            $this->url('search='.str_repeat('a', MenuQuery::MAX_SEARCH_LENGTH + 1)),
        )
            ->assertStatus(422)
            ->assertJsonPath('error.code', ApiErrorCode::ValidationFailed->value);
    }

    public function test_an_injection_string_changes_nothing(): void
    {
        MenuFixtures::ordinaryMenu($this->restaurant);

        foreach ([
            "'; DROP TABLE menu_items; --",
            "' OR 1=1 --",
            '%',
            '_',
            '\\',
        ] as $payload) {
            $this->asRahul()->getJson($this->url('search='.urlencode($payload)))
                ->assertOk();
        }

        // The search never becomes SQL — it runs over items already in memory —
        // and the wildcards match literally rather than matching everything.
        $this->assertSame(6, MenuItem::query()->count());
    }

    // --- the empty menu -------------------------------------------------------

    public function test_a_punctuation_only_search_is_not_a_search(): void
    {
        MenuFixtures::ordinaryMenu($this->restaurant);

        foreach (['%%', '...', '--', '###', '@@'] as $probe) {
            $response = $this->asRahul()
                ->getJson($this->url('search='.urlencode($probe)))
                ->assertOk();

            // The matcher folds punctuation away, so such a term matches every
            // item. Reporting the whole menu as the result for "%%" is a claim
            // the customer would read as "these all match"; the menu comes back
            // unfiltered and says it was not searched.
            $this->assertNull($response->json('data.meta.applied.search'));
            $this->assertFalse($response->json('data.meta.search_empty'));
            $this->assertSame(6, $response->json('data.meta.item_count'));
        }
    }

    public function test_a_wildcard_is_an_ordinary_character(): void
    {
        MenuFixtures::ordinaryMenu($this->restaurant);

        // A SQL wildcard, folded away like any other punctuation rather than
        // expanded. "k" is in none of the three section names, so nothing here
        // comes back through the category-name rule — if "%" meant "anything"
        // this would return the whole menu.
        $response = $this->asRahul()
            ->getJson($this->url('search='.urlencode('%k')))
            ->assertOk();

        $names = collect($response->json('data.categories'))
            ->flatMap(static fn (array $category): array => $category['items'])
            ->pluck('name')
            ->all();

        $this->assertContains('Paneer Tikka', $names);
        // No "k" anywhere in it. A leaked wildcard would have swept it up.
        $this->assertNotContains('Table Water', $names);
    }

    public function test_a_restaurant_with_no_menu_says_so(): void
    {
        $this->asRahul()->getJson($this->url())
            ->assertOk()
            ->assertJsonPath('data.categories', [])
            ->assertJsonPath('data.meta.menu_empty', true)
            ->assertJsonPath('data.meta.search_empty', false);
    }

    // --- the item preview -----------------------------------------------------

    public function test_one_item_can_be_read_on_its_own(): void
    {
        $starters = MenuFixtures::category($this->restaurant, 'Starters', 0);
        $paneer = MenuFixtures::item($starters, 'Paneer Tikka', 24_900, [
            'description' => 'Cottage cheese in the tandoor.',
            'preparation_minutes' => 15,
            'dietary' => MenuItemDietaryType::Vegetarian,
        ]);

        $this->asRahul()->getJson($this->itemUrl($paneer->uuid))
            ->assertOk()
            ->assertJsonPath('data.item.name', 'Paneer Tikka')
            ->assertJsonPath('data.item.price.amount_minor', 24_900)
            ->assertJsonPath('data.item.dietary_type', 'VEGETARIAN')
            ->assertJsonPath('data.category.name', 'Starters')
            ->assertJsonPath('data.restaurant.ordering.can_order', true);
    }

    public function test_an_item_preview_reflects_a_price_that_changed(): void
    {
        $starters = MenuFixtures::category($this->restaurant, 'Starters', 0);
        $paneer = MenuFixtures::item($starters, 'Paneer Tikka', 24_900);

        $this->asRahul()->getJson($this->itemUrl($paneer->uuid))
            ->assertOk()
            ->assertJsonPath('data.item.price.amount_minor', 24_900);

        $paneer->forceFill(['base_price_minor' => 27_900])->save();

        // Fetched again rather than echoed from the list the customer opened it
        // from. A menu can be open for ten minutes.
        $this->asRahul()->getJson($this->itemUrl($paneer->uuid))
            ->assertOk()
            ->assertJsonPath('data.item.price.amount_minor', 27_900);
    }

    public function test_an_unknown_item_is_not_found(): void
    {
        $this->asRahul()->getJson($this->itemUrl('00000000-0000-4000-8000-000000000000'))
            ->assertNotFound()
            ->assertJsonPath('error.code', ApiErrorCode::ItemNotFound->value);
    }

    // --- privacy and read-only -------------------------------------------------

    public function test_the_response_carries_no_private_restaurant_data(): void
    {
        MenuFixtures::ordinaryMenu($this->restaurant);

        $this->restaurant->forceFill([
            'owner_name' => 'Meera Kulkarni',
            'owner_phone' => '+919812345678',
            'commission_rate' => 18.50,
            'internal_notes' => 'Late on settlements.',
        ])->save();

        $body = $this->asRahul()->getJson($this->url())->assertOk()->content();

        foreach ([
            'Meera Kulkarni', '+919812345678', '18.50', 'Late on settlements',
            'owner_name', 'owner_phone', 'commission_rate', 'internal_notes',
            'verification_status', 'is_discoverable',
            // Menu-side internals. None of these columns exists yet; the
            // assertion is here so that the day an operator dashboard adds one,
            // this test is what notices it reaching a customer.
            'cost_price', 'margin', 'supplier', 'recipe', 'stock_quantity',
            'restaurant_id', 'menu_category_id', 'is_active', 'display_order',
        ] as $secret) {
            $this->assertStringNotContainsString($secret, $body, "leaked: {$secret}");
        }
    }

    public function test_no_internal_database_key_is_exposed(): void
    {
        MenuFixtures::ordinaryMenu($this->restaurant);

        $item = $this->asRahul()->getJson($this->url())
            ->assertOk()
            ->json('data.categories.0.items.0');

        $this->assertMatchesRegularExpression('/^[0-9a-f-]{36}$/', $item['id']);
        $this->assertMatchesRegularExpression('/^[0-9a-f-]{36}$/', $item['category_id']);
    }

    public function test_markup_in_an_operators_own_text_comes_back_as_text(): void
    {
        $starters = MenuFixtures::category($this->restaurant, '<b>Starters</b>', 0);
        MenuFixtures::item($starters, '<script>alert(1)</script> Tikka', 24_900, [
            'description' => '<img src=x onerror="alert(1)">',
        ]);

        $item = $this->asRahul()->getJson($this->url())
            ->assertOk()
            ->json('data.categories.0.items.0');

        // Returned verbatim, as data. Flutter draws text and cannot execute it;
        // a future React surface must not hand this to dangerouslySetInnerHTML.
        // Silent mangling here would hide the problem from whoever finds it.
        $this->assertSame('<script>alert(1)</script> Tikka', $item['name']);
        $this->assertStringContainsString('onerror', $item['description']);
    }

    public function test_a_customer_has_no_way_to_change_a_menu(): void
    {
        MenuFixtures::ordinaryMenu($this->restaurant);

        $before = MenuItem::query()->orderBy('id')->first();

        foreach (['post', 'put', 'patch', 'delete'] as $method) {
            $response = $this->asRahul()->json(
                strtoupper($method),
                $this->url(),
                ['name' => 'Renamed', 'base_price_minor' => 1],
            );

            $this->assertContains($response->status(), [404, 405], "{$method} was accepted");
        }

        $after = MenuItem::query()->orderBy('id')->first();

        $this->assertSame($before->name, $after->name);
        $this->assertSame($before->base_price_minor, $after->base_price_minor);
    }

    public function test_reading_a_menu_does_not_change_it(): void
    {
        MenuFixtures::ordinaryMenu($this->restaurant);

        $before = MenuItem::query()->pluck('updated_at', 'id')->toArray();
        $categoriesBefore = MenuCategory::query()->pluck('updated_at', 'id')->toArray();

        $this->asRahul()->getJson($this->url())->assertOk();
        $this->asRahul()->getJson($this->url('search=paneer'))->assertOk();

        $this->assertEquals($before, MenuItem::query()->pluck('updated_at', 'id')->toArray());
        $this->assertEquals(
            $categoriesBefore,
            MenuCategory::query()->pluck('updated_at', 'id')->toArray(),
        );
    }
}
