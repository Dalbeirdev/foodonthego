<?php

declare(strict_types=1);

namespace Tests\Feature\Api\Customer;

use App\Enums\ApiErrorCode;
use App\Enums\CartStatus;
use App\Enums\MenuItemStockStatus;
use App\Enums\RestaurantStatus;
use App\Models\Cart;
use App\Models\CartItem;
use App\Models\MenuItem;
use App\Models\Restaurant;
use App\Models\Trip;
use App\Models\User;
use App\Services\Discovery\RestaurantDetourService;
use App\Services\Discovery\RestaurantDiscoveryService;
use App\Services\Routing\RouteProvider;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Cache;
use Tests\Support\CustomerFactory;
use Tests\Support\MenuFixtures;
use Tests\Support\RestaurantFixtures;
use Tests\TestCase;
use Tests\Unit\StubDetourProvider;

/**
 * Asking a cart whether it still means what it said.
 *
 * Two things are under test throughout, and the second matters more than the
 * first. One: does it notice. Two: **does it leave the cart alone.** Almost
 * every test below re-reads the rows afterwards and asserts nothing moved,
 * because an endpoint that quietly corrected a price would pass a test that
 * only checked it had noticed.
 */
final class CartRevalidationApiTest extends TestCase
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

        // A stub in place of the routing provider, so "how many route calls did
        // that cost" is a number this test can read rather than a promise.
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

    private function item(): MenuItem
    {
        /** @var MenuItem $item */
        $item = $this->menu['item'];

        return $item;
    }

    private function url(): string
    {
        return '/api/v1/customer/trips/'.$this->trip->uuid.'/cart/revalidate';
    }

    /** A Large Paneer Tikka, mild. 329.00. */
    private function addLine(array $overrides = []): string
    {
        return (string) $this->asRahul()
            ->postJson(
                '/api/v1/customer/trips/'.$this->trip->uuid
                    .'/restaurants/'.$this->restaurant->uuid.'/cart/items',
                [
                    'item_id' => $this->item()->uuid,
                    'variant_id' => $this->menu['large']->uuid,
                    'modifier_groups' => [[
                        'group_id' => $this->menu['spice']->uuid,
                        'option_ids' => [$this->menu['mild']->uuid],
                    ]],
                    'quantity' => 1,
                    ...$overrides,
                ],
            )
            ->assertCreated()
            ->json('data.cart_item_id');
    }

    /** The cart's rows, exactly as stored. */
    private function storedLine(): CartItem
    {
        return CartItem::query()->sole();
    }

    // --- nothing has moved ---------------------------------------------------

    public function test_an_untouched_cart_revalidates_clean(): void
    {
        $this->addLine(['quantity' => 2]);

        $response = $this->asRahul()->getJson($this->url())->assertOk();

        $this->assertTrue($response->json('data.revalidation.can_proceed'));
        $this->assertTrue($response->json('data.revalidation.unchanged'));
        $this->assertTrue($response->json('data.revalidation.restaurant_accepting_orders'));

        // Every line reported, not only the ones with something wrong. A screen
        // that lists only problems leaves the customer wondering whether the
        // rest was checked.
        $this->assertCount(1, $response->json('data.revalidation.lines'));
        $this->assertNull($response->json('data.revalidation.lines.0.finding'));
        $this->assertFalse($response->json('data.revalidation.lines.0.blocks_ordering'));
        $this->assertSame('Paneer Tikka', $response->json('data.revalidation.lines.0.name'));
        $this->assertSame('Large', $response->json('data.revalidation.lines.0.variant_name'));
        $this->assertSame(2, $response->json('data.revalidation.lines.0.quantity'));

        $this->assertSame(32_900, $response->json('data.revalidation.lines.0.price_when_added.amount_minor'));
        $this->assertSame(32_900, $response->json('data.revalidation.lines.0.price_now.amount_minor'));

        // And the cart itself comes back alongside, so one request draws the
        // whole screen.
        $this->assertSame(65_800, $response->json('data.cart.totals.total.amount_minor'));
        $this->assertSame(65_800, $response->json('data.revalidation.totals_if_accepted.total.amount_minor'));
    }

    public function test_a_journey_with_no_cart_is_told_so(): void
    {
        $response = $this->asRahul()->getJson($this->url())->assertNotFound();

        $this->assertSame(ApiErrorCode::CartNotFound->value, $response->json('error.code'));
    }

    public function test_another_customers_journey_is_not_found(): void
    {
        $ananya = CustomerFactory::ananya();
        $hers = RestaurantFixtures::tripWithSelectedRoute($ananya);

        $this->asRahul()
            ->getJson('/api/v1/customer/trips/'.$hers->uuid.'/cart/revalidate')
            ->assertNotFound();
    }

    // --- prices --------------------------------------------------------------

    public function test_a_price_rise_is_reported_with_both_figures_and_nothing_is_charged(): void
    {
        $this->addLine();

        $this->menu['large']->forceFill(['price_minor' => 39_900])->save();

        $response = $this->asRahul()->getJson($this->url())->assertOk();

        $this->assertSame('PRICE_INCREASED', $response->json('data.revalidation.lines.0.finding'));
        $this->assertSame(32_900, $response->json('data.revalidation.lines.0.price_when_added.amount_minor'));
        $this->assertSame(39_900, $response->json('data.revalidation.lines.0.price_now.amount_minor'));

        // A price change does not stop the customer ordering. They look at it
        // and decide, which is the difference between this and a missing dish.
        $this->assertFalse($response->json('data.revalidation.lines.0.blocks_ordering'));
        $this->assertTrue($response->json('data.revalidation.can_proceed'));
        $this->assertFalse($response->json('data.revalidation.unchanged'));

        // What it would cost if they accept. Offered, not applied.
        $this->assertSame(39_900, $response->json('data.revalidation.totals_if_accepted.total.amount_minor'));

        // Nothing was written. This is the assertion the endpoint exists for.
        $this->assertSame(32_900, (int) $this->storedLine()->unit_price_minor);
        $this->assertSame(32_900, (int) $this->storedLine()->line_total_minor);
        $this->assertSame(32_900, $response->json('data.cart.totals.total.amount_minor'));
    }

    public function test_a_price_drop_is_reported_too(): void
    {
        $this->addLine();

        $this->menu['large']->forceFill(['price_minor' => 29_900])->save();

        $response = $this->asRahul()->getJson($this->url())->assertOk();

        // Reported rather than silently applied. A customer should see a
        // reduction, not absorb it — and a cart that changed its own total on a
        // read would be doing the thing this endpoint refuses to do, in the
        // direction that happens to be pleasant.
        $this->assertSame('PRICE_DECREASED', $response->json('data.revalidation.lines.0.finding'));
        $this->assertSame(29_900, $response->json('data.revalidation.lines.0.price_now.amount_minor'));
        $this->assertTrue($response->json('data.revalidation.can_proceed'));

        $this->assertSame(32_900, (int) $this->storedLine()->unit_price_minor);
    }

    public function test_a_modifiers_price_change_moves_the_line(): void
    {
        $this->addLine([
            'modifier_groups' => [
                [
                    'group_id' => $this->menu['spice']->uuid,
                    'option_ids' => [$this->menu['mild']->uuid],
                ],
                [
                    'group_id' => $this->menu['extras']->uuid,
                    'option_ids' => [$this->menu['cheese']->uuid],
                ],
            ],
        ]);

        // 329 + 40 when added; the cheese goes up by ten rupees.
        $this->assertSame(36_900, (int) $this->storedLine()->unit_price_minor);

        $this->menu['cheese']->forceFill(['price_delta_minor' => 5_000])->save();

        $response = $this->asRahul()->getJson($this->url())->assertOk();

        $this->assertSame('PRICE_INCREASED', $response->json('data.revalidation.lines.0.finding'));
        $this->assertSame(37_900, $response->json('data.revalidation.lines.0.price_now.amount_minor'));
    }

    public function test_each_line_is_judged_on_its_own(): void
    {
        $this->addLine();
        $this->addLine([
            'variant_id' => $this->menu['regular']->uuid,
            'special_instructions' => 'No onion',
        ]);

        $this->menu['large']->forceFill(['price_minor' => 39_900])->save();

        $lines = $this->asRahul()->getJson($this->url())->assertOk()->json('data.revalidation.lines');

        $this->assertCount(2, $lines);

        $byVariant = collect($lines)->keyBy('variant_name');

        $this->assertSame('PRICE_INCREASED', $byVariant['Large']['finding']);
        $this->assertNull($byVariant['Regular']['finding']);
    }

    // --- things that are gone ------------------------------------------------

    public function test_a_sold_out_dish_blocks_ordering_and_is_not_priced(): void
    {
        $this->addLine();

        $this->item()->forceFill(['stock_status' => MenuItemStockStatus::SoldOut])->save();

        $response = $this->asRahul()->getJson($this->url())->assertOk();

        $this->assertSame('ITEM_UNAVAILABLE', $response->json('data.revalidation.lines.0.finding'));
        $this->assertTrue($response->json('data.revalidation.lines.0.blocks_ordering'));
        $this->assertFalse($response->json('data.revalidation.can_proceed'));

        // Null, not zero. A dish that cannot be bought does not cost nothing.
        $this->assertNull($response->json('data.revalidation.lines.0.price_now'));

        // And no total is offered. A figure worked out around a missing dish
        // describes a cart nobody has.
        $this->assertNull($response->json('data.revalidation.totals_if_accepted'));

        // The line is still there. The customer removes it; we do not.
        $this->assertSame(1, CartItem::query()->count());
        $this->assertSame(CartStatus::Active, Cart::query()->sole()->status);
    }

    public function test_a_withdrawn_dish_blocks_ordering(): void
    {
        $this->addLine();

        $this->item()->forceFill(['is_active' => false])->save();

        $response = $this->asRahul()->getJson($this->url())->assertOk();

        $this->assertSame('ITEM_UNAVAILABLE', $response->json('data.revalidation.lines.0.finding'));
        $this->assertFalse($response->json('data.revalidation.can_proceed'));
        $this->assertSame(1, CartItem::query()->count());
    }

    public function test_a_size_that_has_gone_is_named_as_a_variant_problem(): void
    {
        $this->addLine();

        $this->menu['large']->forceFill(['is_active' => false])->save();

        $response = $this->asRahul()->getJson($this->url())->assertOk();

        // Not "the dish is unavailable". The dish is fine; the size is not, and
        // the customer's fix is to reopen it and choose another.
        $this->assertSame('VARIANT_UNAVAILABLE', $response->json('data.revalidation.lines.0.finding'));
        $this->assertTrue($response->json('data.revalidation.lines.0.blocks_ordering'));
        $this->assertNull($response->json('data.revalidation.totals_if_accepted'));
    }

    public function test_an_option_that_has_gone_is_named_as_a_modifier_problem(): void
    {
        $this->addLine();

        $this->menu['mild']->forceFill(['is_active' => false])->save();

        $response = $this->asRahul()->getJson($this->url())->assertOk();

        $this->assertSame('MODIFIER_UNAVAILABLE', $response->json('data.revalidation.lines.0.finding'));
        $this->assertTrue($response->json('data.revalidation.lines.0.blocks_ordering'));

        // The coarse finding is what a screen branches on; the source code is
        // what lets it say something specific.
        $this->assertNotNull($response->json('data.revalidation.lines.0.source_code'));
        $this->assertNotNull($response->json('data.revalidation.lines.0.message'));
    }

    public function test_one_broken_line_does_not_hide_the_others(): void
    {
        $this->addLine();
        $this->addLine([
            'variant_id' => $this->menu['regular']->uuid,
            'special_instructions' => 'No onion',
        ]);

        $this->menu['large']->forceFill(['is_active' => false])->save();
        $this->menu['regular']->forceFill(['price_minor' => 27_900])->save();

        $lines = $this->asRahul()->getJson($this->url())->assertOk()->json('data.revalidation.lines');

        // A customer who has to fix two things wants to be told about two
        // things, not the first one twice.
        $this->assertCount(2, $lines);

        $findings = array_column($lines, 'finding');

        $this->assertContains('VARIANT_UNAVAILABLE', $findings);
        $this->assertContains('PRICE_INCREASED', $findings);
    }

    // --- the kitchen ---------------------------------------------------------

    public function test_a_paused_kitchen_stops_the_order_without_touching_the_cart(): void
    {
        $this->addLine();

        $this->restaurant->forceFill(['is_accepting_orders' => false])->save();

        $response = $this->asRahul()->getJson($this->url())->assertOk();

        $this->assertFalse($response->json('data.revalidation.restaurant_accepting_orders'));
        $this->assertFalse($response->json('data.revalidation.can_proceed'));
        $this->assertFalse($response->json('data.revalidation.unchanged'));

        // The lines are fine — it is the counter that is shut. The cart is
        // untouched and waiting.
        $this->assertNull($response->json('data.revalidation.lines.0.finding'));
        $this->assertSame(1, CartItem::query()->count());
        $this->assertSame(CartStatus::Active, Cart::query()->sole()->status);
    }

    public function test_a_suspended_restaurant_stops_the_order(): void
    {
        $this->addLine();

        $this->restaurant->forceFill(['status' => RestaurantStatus::Suspended])->save();

        $response = $this->asRahul()->getJson($this->url())->assertOk();

        // A refusal from the eligibility path is an answer, not an error. An
        // error page would tell the customer nothing about the four fixable
        // problems that might also be on the screen.
        $this->assertFalse($response->json('data.revalidation.can_proceed'));
        $this->assertSame(1, CartItem::query()->count());
    }

    // --- the rule that matters -----------------------------------------------

    public function test_revalidation_writes_nothing_at_all(): void
    {
        $this->addLine(['quantity' => 3]);

        $before = $this->storedLine()->only([
            'quantity', 'unit_price_minor', 'line_total_minor',
            'item_name_snapshot', 'variant_name_snapshot', 'configuration_hash',
        ]);
        $cartBefore = Cart::query()->sole()->only(['status', 'currency', 'restaurant_id']);

        // Everything moves at once: the dish costs more, an option costs more,
        // and the kitchen has paused.
        $this->menu['large']->forceFill(['price_minor' => 44_900])->save();
        $this->menu['cheese']->forceFill(['price_delta_minor' => 9_900])->save();
        $this->restaurant->forceFill(['is_accepting_orders' => false])->save();

        $this->asRahul()->getJson($this->url())->assertOk();
        $this->asRahul()->getJson($this->url())->assertOk();

        // Twice, because an endpoint that corrected on the second call would
        // pass a test that only called it once.
        $this->assertSame($before, $this->storedLine()->only(array_keys($before)));
        $this->assertSame($cartBefore, Cart::query()->sole()->only(array_keys($cartBefore)));
    }

    public function test_revalidating_calls_no_routing_provider(): void
    {
        $this->addLine();

        // The restaurant's ordering state comes from Module 07's cached
        // discovery result, exactly as adding to the cart does. Looking at your
        // own cart must not spend a route or detour call.
        $before = $this->provider->calls;

        $this->asRahul()->getJson($this->url())->assertOk();
        $this->asRahul()->getJson($this->url())->assertOk();

        $this->assertSame($before, $this->provider->calls);

        // Negative control for the counter itself, in the same test: a cold
        // discovery does call the provider. Without this, "the number did not
        // move" would be satisfied by a counter that never moves.
        Cache::flush();
        $this->asRahul()
            ->getJson('/api/v1/customer/trips/'.$this->trip->uuid.'/restaurants')
            ->assertOk();

        $this->assertGreaterThan($before, $this->provider->calls);
    }
}
