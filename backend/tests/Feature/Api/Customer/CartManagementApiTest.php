<?php

declare(strict_types=1);

namespace Tests\Feature\Api\Customer;

use App\Enums\ApiErrorCode;
use App\Enums\CartStatus;
use App\Models\Cart;
use App\Models\CartItem;
use App\Models\CartItemModifier;
use App\Models\MenuItem;
use App\Models\Restaurant;
use App\Models\Trip;
use App\Models\User;
use Illuminate\Database\Events\QueryExecuted;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use PHPUnit\Framework\Attributes\DataProvider;
use Tests\Support\CustomerFactory;
use Tests\Support\MenuFixtures;
use Tests\Support\RestaurantFixtures;
use Tests\TestCase;

/**
 * Reading a cart, correcting it and emptying it, over HTTP.
 *
 * Module 11's file asks whether a client can decide a price when *adding*.
 * This one asks the same question of every other operation, because a cart that
 * refuses a tampered price on the way in and accepts one on a quantity change
 * has not refused anything.
 *
 * The other theme is that closing is not deleting. Several tests below check a
 * row is still there after the customer has been told it is gone.
 */
final class CartManagementApiTest extends TestCase
{
    use RefreshDatabase;

    private User $rahul;

    private string $token;

    private Trip $trip;

    private Restaurant $restaurant;

    /** @var array<string, mixed> */
    private array $menu;

    private bool $listening = false;

    private int $queries = 0;

    protected function setUp(): void
    {
        parent::setUp();

        Cache::flush();

        $this->rahul = CustomerFactory::rahul();
        $this->token = CustomerFactory::tokenFor($this->rahul);
        $this->trip = RestaurantFixtures::tripWithSelectedRoute($this->rahul);
        $this->restaurant = RestaurantFixtures::nearRoute(0.4, 800, 'Highway Spice Kitchen');
        $this->menu = MenuFixtures::configurableItem($this->restaurant);
    }

    // --- plumbing ------------------------------------------------------------

    private function asRahul(): self
    {
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', 'Bearer '.$this->token);
    }

    private function as(User $customer): self
    {
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', 'Bearer '.CustomerFactory::tokenFor($customer));
    }

    private function addUrl(?Trip $trip = null): string
    {
        return '/api/v1/customer/trips/'.($trip ?? $this->trip)->uuid
            .'/restaurants/'.$this->restaurant->uuid.'/cart/items';
    }

    private function cartUrl(?Trip $trip = null): string
    {
        return '/api/v1/customer/trips/'.($trip ?? $this->trip)->uuid.'/cart';
    }

    private function lineUrl(string $lineUuid, ?Trip $trip = null): string
    {
        return $this->cartUrl($trip).'/items/'.$lineUuid;
    }

    private function item(): MenuItem
    {
        /** @var MenuItem $item */
        $item = $this->menu['item'];

        return $item;
    }

    /**
     * One line in the cart: a Large Paneer Tikka, mild. 329.00.
     *
     * Added through the real endpoint rather than by writing rows, so every
     * test below starts from a cart the application actually produced.
     */
    private function addLine(array $overrides = []): string
    {
        $response = $this->asRahul()
            ->postJson($this->addUrl(), [
                'item_id' => $this->item()->uuid,
                'variant_id' => $this->menu['large']->uuid,
                'modifier_groups' => [
                    [
                        'group_id' => $this->menu['spice']->uuid,
                        'option_ids' => [$this->menu['mild']->uuid],
                    ],
                ],
                'quantity' => 1,
                ...$overrides,
            ])
            ->assertCreated();

        return (string) $response->json('data.cart_item_id');
    }

    /** A second, different line: Regular, hot, with a note. 249.00. */
    private function addSecondLine(): string
    {
        return $this->addLine([
            'variant_id' => $this->menu['regular']->uuid,
            'modifier_groups' => [
                [
                    'group_id' => $this->menu['spice']->uuid,
                    'option_ids' => [$this->menu['hot']->uuid],
                ],
            ],
            'special_instructions' => 'No onion',
        ]);
    }

    // --- reading the cart ----------------------------------------------------

    public function test_the_cart_reads_back_with_its_lines_options_and_totals(): void
    {
        $this->addLine(['quantity' => 2]);

        $response = $this->asRahul()->getJson($this->cartUrl())->assertOk();

        $this->assertSame('ACTIVE', $response->json('data.cart.status'));
        $this->assertSame($this->restaurant->uuid, $response->json('data.cart.restaurant_id'));
        $this->assertSame('Highway Spice Kitchen', $response->json('data.cart.restaurant_name'));
        $this->assertSame($this->trip->uuid, $response->json('data.cart.trip_id'));
        $this->assertSame('INR', $response->json('data.cart.currency'));

        $this->assertCount(1, $response->json('data.cart.items'));
        $this->assertSame('Paneer Tikka', $response->json('data.cart.items.0.name'));
        $this->assertSame('Large', $response->json('data.cart.items.0.variant_name'));
        $this->assertSame(2, $response->json('data.cart.items.0.quantity'));
        $this->assertSame(32_900, $response->json('data.cart.items.0.unit_price.amount_minor'));
        $this->assertSame(65_800, $response->json('data.cart.items.0.line_total.amount_minor'));

        // The options are on the line, with their snapshots and their deltas.
        $this->assertSame('Spice level', $response->json('data.cart.items.0.modifiers.0.group_name'));
        $this->assertSame('Mild', $response->json('data.cart.items.0.modifiers.0.option_name'));

        // Every figure in the breakdown, not just the one at the bottom. A
        // customer who cannot see what the extra rupees are for assumes the
        // worst.
        $this->assertSame(65_800, $response->json('data.cart.totals.subtotal.amount_minor'));
        $this->assertSame(65_800, $response->json('data.cart.totals.total.amount_minor'));
        $this->assertSame('INR', $response->json('data.cart.totals.total.currency'));
        $this->assertNotNull($response->json('data.cart.totals.tax'));
        $this->assertNotNull($response->json('data.cart.totals.packaging_fee'));
        $this->assertNotNull($response->json('data.cart.totals.platform_fee'));

        $this->assertSame(2, $response->json('data.item_count'));
        $this->assertSame(1, $response->json('data.line_count'));
    }

    public function test_the_badge_fields_module_11_shipped_are_still_where_they_were(): void
    {
        // The cart screen extended this endpoint's shape. A client that ships
        // today reads exactly these four things, and a tidier response is not
        // worth breaking it.
        $this->addLine();

        $response = $this->asRahul()->getJson($this->cartUrl())->assertOk();

        $this->assertIsString($response->json('data.cart.id'));
        $this->assertSame($this->restaurant->uuid, $response->json('data.cart.restaurant_id'));
        $this->assertSame('Highway Spice Kitchen', $response->json('data.cart.restaurant_name'));
        $this->assertSame(32_900, $response->json('data.cart.subtotal.amount_minor'));
        $this->assertSame('INR', $response->json('data.cart.subtotal.currency'));
    }

    public function test_a_journey_with_nothing_on_it_reads_as_no_cart(): void
    {
        $response = $this->asRahul()->getJson($this->cartUrl())->assertOk();

        $this->assertNull($response->json('data.cart'));
        $this->assertSame(0, $response->json('data.item_count'));
        $this->assertSame(0, $response->json('data.line_count'));
    }

    public function test_another_customers_journey_is_not_found(): void
    {
        $ananya = CustomerFactory::ananya();
        $hers = RestaurantFixtures::tripWithSelectedRoute($ananya);

        $this->asRahul()->getJson($this->cartUrl($hers))->assertNotFound();
        $this->asRahul()->deleteJson($this->cartUrl($hers))->assertNotFound();
    }

    // --- changing a quantity -------------------------------------------------

    public function test_a_quantity_change_is_priced_by_the_server(): void
    {
        $line = $this->addLine();

        $response = $this->asRahul()
            ->patchJson($this->lineUrl($line), ['quantity' => 3])
            ->assertOk();

        $this->assertSame(3, $response->json('data.cart.items.0.quantity'));
        $this->assertSame(32_900, $response->json('data.cart.items.0.unit_price.amount_minor'));
        $this->assertSame(98_700, $response->json('data.cart.items.0.line_total.amount_minor'));
        $this->assertSame(98_700, $response->json('data.cart.totals.subtotal.amount_minor'));
        $this->assertSame(3, $response->json('data.item_count'));

        $stored = CartItem::query()->sole();

        $this->assertSame(3, (int) $stored->quantity);
        $this->assertSame(98_700, (int) $stored->line_total_minor);
    }

    public function test_a_price_sent_with_a_quantity_change_is_ignored(): void
    {
        $line = $this->addLine();

        $response = $this->asRahul()
            ->patchJson($this->lineUrl($line), [
                'quantity' => 2,

                // Every name a hopeful attacker might try. None of them is a
                // field this endpoint reads, which is the point: there is
                // nothing to sanitise because there is nothing to send.
                'unit_price_minor' => 1,
                'unit_price' => ['amount_minor' => 1, 'currency' => 'INR'],
                'line_total_minor' => 1,
                'subtotal' => 1,
                'discount' => 99_999,
                'tax' => 0,
                'final_total' => 1,
                'currency' => 'JPY',
            ])
            ->assertOk();

        $this->assertSame(32_900, $response->json('data.cart.items.0.unit_price.amount_minor'));
        $this->assertSame(65_800, $response->json('data.cart.items.0.line_total.amount_minor'));
        $this->assertSame(65_800, $response->json('data.cart.totals.total.amount_minor'));
        $this->assertSame('INR', $response->json('data.cart.currency'));
    }

    public function test_a_quantity_change_reprices_from_the_menu_rather_than_scaling_the_snapshot(): void
    {
        $line = $this->addLine();

        // The kitchen drops the price of the Large after the customer added it.
        $this->menu['large']->forceFill(['price_minor' => 30_000])->save();

        $response = $this->asRahul()
            ->patchJson($this->lineUrl($line), ['quantity' => 2])
            ->assertOk();

        // 60 000, not 65 800. Scaling the stored 32 900 would charge the
        // customer for a reduction they were given.
        $this->assertSame(30_000, $response->json('data.cart.items.0.unit_price.amount_minor'));
        $this->assertSame(60_000, $response->json('data.cart.items.0.line_total.amount_minor'));
        $this->assertSame(60_000, (int) CartItem::query()->sole()->line_total_minor);
    }

    public function test_a_dish_that_has_gone_up_is_reported_rather_than_charged(): void
    {
        $line = $this->addLine();

        $this->menu['large']->forceFill(['price_minor' => 39_900])->save();

        $response = $this->asRahul()
            ->patchJson($this->lineUrl($line), ['quantity' => 2])
            ->assertStatus(409);

        $this->assertSame(ApiErrorCode::PriceUpdated->value, $response->json('error.code'));
        $this->assertSame(32_900, $response->json('error.details.quoted_unit_price.amount_minor'));
        $this->assertSame(39_900, $response->json('error.details.current_unit_price.amount_minor'));

        // And nothing moved. The customer agrees to the new figure before it is
        // charged, or the cart stays as it was.
        $stored = CartItem::query()->sole();

        $this->assertSame(1, (int) $stored->quantity);
        $this->assertSame(32_900, (int) $stored->unit_price_minor);
    }

    public function test_a_quantity_of_zero_is_refused_and_the_line_survives(): void
    {
        $line = $this->addLine();

        $response = $this->asRahul()
            ->patchJson($this->lineUrl($line), ['quantity' => 0])
            ->assertStatus(422);

        $this->assertSame(ApiErrorCode::QuantityInvalid->value, $response->json('error.code'));

        // Zero is not "remove". An off-by-one in a stepper must not destroy
        // what the customer chose.
        $this->assertSame(1, (int) CartItem::query()->sole()->quantity);
    }

    public function test_a_quantity_above_the_ceiling_is_refused(): void
    {
        $line = $this->addLine();

        $max = (int) config('foodonthego.cart.max_quantity_per_line');

        $response = $this->asRahul()
            ->patchJson($this->lineUrl($line), ['quantity' => $max + 1])
            ->assertStatus(422);

        $this->assertSame(ApiErrorCode::QuantityLimitExceeded->value, $response->json('error.code'));
        $this->assertSame($max, $response->json('error.details.max_quantity'));
        $this->assertSame(1, (int) CartItem::query()->sole()->quantity);
    }

    /**
     * @return array<string, array{mixed}>
     */
    public static function unreadableQuantities(): array
    {
        return [
            'a fraction' => [2.5],
            'a word' => ['two'],
            'a boolean' => [true],
            'nothing at all' => [null],
            'an array' => [[2]],
        ];
    }

    #[DataProvider('unreadableQuantities')]
    public function test_a_quantity_that_is_not_a_whole_number_is_refused(mixed $quantity): void
    {
        $line = $this->addLine();

        $response = $this->asRahul()
            ->patchJson($this->lineUrl($line), ['quantity' => $quantity])
            ->assertStatus(422);

        $this->assertSame(ApiErrorCode::QuantityInvalid->value, $response->json('error.code'));
        $this->assertSame(1, (int) CartItem::query()->sole()->quantity);
    }

    public function test_a_line_id_that_is_not_in_this_cart_is_not_found(): void
    {
        $this->addLine();

        $response = $this->asRahul()
            ->patchJson($this->lineUrl((string) Str::uuid()), ['quantity' => 2])
            ->assertNotFound();

        $this->assertSame(ApiErrorCode::ItemNotFound->value, $response->json('error.code'));
    }

    public function test_another_customers_line_cannot_be_touched_through_your_own_journey(): void
    {
        $mine = $this->addLine();

        $ananya = CustomerFactory::ananya();
        $herTrip = RestaurantFixtures::tripWithSelectedRoute($ananya);

        $hers = (string) $this->as($ananya)
            ->postJson($this->addUrl($herTrip), [
                'item_id' => $this->item()->uuid,
                'variant_id' => $this->menu['large']->uuid,
                'modifier_groups' => [[
                    'group_id' => $this->menu['spice']->uuid,
                    'option_ids' => [$this->menu['mild']->uuid],
                ]],
                'quantity' => 1,
            ])
            ->assertCreated()
            ->json('data.cart_item_id');

        $this->assertNotSame($mine, $hers);

        // Her line id, my journey. Not found rather than forbidden: an answer
        // that differed would let somebody enumerate other people's carts one
        // id at a time.
        $this->asRahul()->patchJson($this->lineUrl($hers), ['quantity' => 5])->assertNotFound();
        $this->asRahul()->deleteJson($this->lineUrl($hers))->assertNotFound();

        $this->assertSame(1, (int) CartItem::query()->where('uuid', $hers)->sole()->quantity);
    }

    // --- removing a line -----------------------------------------------------

    public function test_removing_one_line_leaves_the_others(): void
    {
        $first = $this->addLine();
        $this->addSecondLine();

        $response = $this->asRahul()->deleteJson($this->lineUrl($first))->assertOk();

        $this->assertSame(1, $response->json('data.line_count'));
        $this->assertSame('Regular', $response->json('data.cart.items.0.variant_name'));
        $this->assertSame(24_900, $response->json('data.cart.totals.subtotal.amount_minor'));

        $this->assertSame(0, CartItem::query()->where('uuid', $first)->count());
        $this->assertSame(1, CartItem::query()->count());
    }

    public function test_the_options_go_with_the_line(): void
    {
        $line = $this->addLine();

        $this->assertSame(1, CartItemModifier::query()->count());

        $this->asRahul()->deleteJson($this->lineUrl($line))->assertOk();

        // Not left behind pointing at nothing. The foreign key is what
        // guarantees it, and this is the test that says so.
        $this->assertSame(0, CartItemModifier::query()->count());
    }

    public function test_removing_the_last_line_closes_the_cart_without_deleting_it(): void
    {
        $line = $this->addLine();
        $cartId = (int) Cart::query()->sole()->id;

        $response = $this->asRahul()->deleteJson($this->lineUrl($line))->assertOk();

        // An empty cart is the absence of a cart, and is reported as one.
        $this->assertNull($response->json('data.cart'));
        $this->assertSame(0, $response->json('data.item_count'));

        $cart = Cart::query()->findOrFail($cartId);

        $this->assertSame(CartStatus::Closed, $cart->status);
        $this->assertSame(0, CartItem::query()->count());
    }

    // --- emptying ------------------------------------------------------------

    public function test_emptying_a_cart_closes_it_and_removes_its_lines(): void
    {
        $this->addLine();
        $this->addSecondLine();

        $cartId = (int) Cart::query()->sole()->id;

        $response = $this->asRahul()->deleteJson($this->cartUrl())->assertOk();

        $this->assertNull($response->json('data.cart'));
        $this->assertSame(0, $response->json('data.line_count'));

        $this->assertSame(CartStatus::Closed, Cart::query()->findOrFail($cartId)->status);
        $this->assertSame(0, CartItem::query()->count());

        // Closed, not deleted. Module 13's orders will point at this row.
        $this->assertSame(1, Cart::query()->count());
    }

    public function test_emptying_a_cart_that_is_already_empty_succeeds(): void
    {
        $this->asRahul()->deleteJson($this->cartUrl())->assertOk();

        $response = $this->asRahul()->deleteJson($this->cartUrl())->assertOk();

        // A customer who taps twice, or a client that retries a request whose
        // response was lost, has got what they asked for both times.
        $this->assertNull($response->json('data.cart'));
        $this->assertSame(0, Cart::query()->count());
    }

    public function test_a_journey_can_be_used_again_after_its_cart_is_emptied(): void
    {
        $this->addLine();
        $this->asRahul()->deleteJson($this->cartUrl())->assertOk();

        // The one-active-cart-per-journey slot is free, so this is an ordinary
        // add rather than a CART_TRIP_CONFLICT. An empty cart left ACTIVE would
        // have blocked it — KI-014 by a different route.
        $this->addLine();

        $this->assertSame(1, Cart::query()->where('status', CartStatus::Active)->count());
        $this->assertSame(2, Cart::query()->count());
        $this->assertSame(32_900, $this->asRahul()->getJson($this->cartUrl())
            ->json('data.cart.totals.total.amount_minor'));
    }

    public function test_an_empty_cart_blocks_nothing_on_another_journey(): void
    {
        $this->addLine();
        $line = (string) Cart::query()->sole()->items()->sole()->uuid;

        $this->asRahul()->deleteJson($this->lineUrl($line))->assertOk();

        $second = RestaurantFixtures::tripWithSelectedRoute($this->rahul);

        $this->asRahul()
            ->postJson($this->addUrl($second), [
                'item_id' => $this->item()->uuid,
                'variant_id' => $this->menu['large']->uuid,
                'modifier_groups' => [[
                    'group_id' => $this->menu['spice']->uuid,
                    'option_ids' => [$this->menu['mild']->uuid],
                ]],
                'quantity' => 1,
            ])
            ->assertCreated();
    }

    // --- totals --------------------------------------------------------------

    public function test_taxes_and_fees_are_added_to_the_subtotal(): void
    {
        // Non-zero values, set here rather than in config: production defaults
        // to nothing on purpose, and a test that only ever sees zero would pass
        // against a service that computed nothing at all.
        config(['foodonthego.cart.platform_fee_minor' => 1_000]);

        $this->restaurant->forceFill([
            'tax_rate_bps' => 500,
            'packaging_fee_minor' => 2_000,
        ])->save();

        $this->addLine(['quantity' => 2]);

        $totals = $this->asRahul()->getJson($this->cartUrl())->assertOk()->json('data.cart.totals');

        // 65 800 subtotal, 5% = 3 290, packaging 2 000, platform 1 000.
        $this->assertSame(65_800, $totals['subtotal']['amount_minor']);
        $this->assertSame(3_290, $totals['tax']['amount_minor']);
        $this->assertSame(2_000, $totals['packaging_fee']['amount_minor']);
        $this->assertSame(1_000, $totals['platform_fee']['amount_minor']);
        $this->assertSame(72_090, $totals['total']['amount_minor']);

        // The parts add up to the whole. Obvious, and the assertion that would
        // have caught every rounding bug this file exists to prevent.
        $this->assertSame(
            $totals['subtotal']['amount_minor']
                + $totals['tax']['amount_minor']
                + $totals['packaging_fee']['amount_minor']
                + $totals['platform_fee']['amount_minor'],
            $totals['total']['amount_minor'],
        );
    }

    public function test_a_restaurants_own_rate_wins_over_the_platforms(): void
    {
        config(['foodonthego.cart.tax_rate_bps' => 1_800]);

        $this->restaurant->forceFill(['tax_rate_bps' => 500])->save();

        $this->addLine();

        $totals = $this->asRahul()->getJson($this->cartUrl())->json('data.cart.totals');

        $this->assertSame(1_645, $totals['tax']['amount_minor']);
    }

    public function test_a_restaurant_taxed_at_nothing_is_not_given_the_platform_rate(): void
    {
        config(['foodonthego.cart.tax_rate_bps' => 1_800]);

        // Zero, explicitly. Not the same as null: this restaurant is
        // deliberately not taxed, and falling back would charge its customers
        // eighteen per cent because somebody typed a zero.
        $this->restaurant->forceFill(['tax_rate_bps' => 0])->save();

        $this->addLine();

        $totals = $this->asRahul()->getJson($this->cartUrl())->json('data.cart.totals');

        $this->assertSame(0, $totals['tax']['amount_minor']);
        $this->assertSame(32_900, $totals['total']['amount_minor']);
    }

    public function test_an_unconfigured_restaurant_falls_back_to_the_platform_rate(): void
    {
        config(['foodonthego.cart.tax_rate_bps' => 1_800]);

        $this->assertNull($this->restaurant->tax_rate_bps);

        $this->addLine();

        $totals = $this->asRahul()->getJson($this->cartUrl())->json('data.cart.totals');

        $this->assertSame(5_922, $totals['tax']['amount_minor']);
    }

    public function test_the_totals_follow_a_quantity_change(): void
    {
        config(['foodonthego.cart.platform_fee_minor' => 1_000]);
        $this->restaurant->forceFill(['tax_rate_bps' => 500])->save();

        $line = $this->addLine();

        $totals = $this->asRahul()
            ->patchJson($this->lineUrl($line), ['quantity' => 2])
            ->assertOk()
            ->json('data.cart.totals');

        // Recomputed from the cart as it now stands, not adjusted from what it
        // was. 65 800 + 3 290 + 1 000.
        $this->assertSame(65_800, $totals['subtotal']['amount_minor']);
        $this->assertSame(3_290, $totals['tax']['amount_minor']);
        $this->assertSame(70_090, $totals['total']['amount_minor']);
    }

    public function test_a_cart_read_costs_the_same_whether_it_holds_one_line_or_several(): void
    {
        $this->addLine();

        $one = $this->countCartQueries();

        $this->addSecondLine();
        $this->addLine([
            'variant_id' => $this->menu['regular']->uuid,
            'modifier_groups' => [[
                'group_id' => $this->menu['spice']->uuid,
                'option_ids' => [$this->menu['mild']->uuid],
            ]],
            'special_instructions' => 'Extra napkins',
        ]);

        $several = $this->countCartQueries();

        // A cart screen that gets slower the more the customer puts in it is
        // the classic N+1, and the one place it would show first is the screen
        // where they are about to spend money.
        $this->assertSame($one, $several, "one line: {$one}, three lines: {$several}");
    }

    /**
     * How many queries a cart read spends on cart and menu tables.
     *
     * Only the tables under test. A whole-request count drifts by one with the
     * session and token preamble, and a budget that drifts is a budget nobody
     * trusts.
     *
     * The listener is registered once for the life of the test and the counter
     * reset around the request; registering it per call would leave the earlier
     * one attached and count every query twice on the second measurement.
     */
    private function countCartQueries(): int
    {
        $tables = [
            'carts', 'cart_items', 'cart_item_modifiers',
            'menu_items', 'menu_item_variants', 'menu_modifier_options',
            'restaurants',
        ];

        if (! $this->listening) {
            $this->listening = true;

            DB::listen(function (QueryExecuted $query) use ($tables): void {
                foreach ($tables as $table) {
                    if (str_contains($query->sql, '`'.$table.'`')) {
                        $this->queries++;

                        return;
                    }
                }
            });
        }

        $this->queries = 0;

        $this->asRahul()->getJson($this->cartUrl())->assertOk();

        return $this->queries;
    }
}
