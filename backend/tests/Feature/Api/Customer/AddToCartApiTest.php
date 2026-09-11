<?php

declare(strict_types=1);

namespace Tests\Feature\Api\Customer;

use App\Enums\ApiErrorCode;
use App\Enums\MenuItemStockStatus;
use App\Enums\RestaurantStatus;
use App\Models\Cart;
use App\Models\CartItem;
use App\Models\MenuItem;
use App\Models\Restaurant;
use App\Models\Trip;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Str;
use Tests\Support\CustomerFactory;
use Tests\Support\MenuFixtures;
use Tests\Support\RestaurantFixtures;
use Tests\TestCase;

/**
 * Adding a configured dish to a cart, over HTTP.
 *
 * The theme of this file is that **nothing the client sends decides what the
 * customer pays**. Most of what follows is an attempt to make it, and a check
 * that the attempt changed nothing.
 */
final class AddToCartApiTest extends TestCase
{
    use RefreshDatabase;

    private User $rahul;

    private string $token;

    private Trip $trip;

    private Restaurant $restaurant;

    /** @var array<string, mixed> */
    private array $menu;

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

    private function asRahul(): self
    {
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', 'Bearer '.$this->token);
    }

    private function url(?Restaurant $restaurant = null, ?Trip $trip = null): string
    {
        return '/api/v1/customer/trips/'.($trip ?? $this->trip)->uuid
            .'/restaurants/'.($restaurant ?? $this->restaurant)->uuid.'/cart/items';
    }

    private function item(): MenuItem
    {
        /** @var MenuItem $item */
        $item = $this->menu['item'];

        return $item;
    }

    /** @return array<string, mixed> */
    private function validBody(array $overrides = []): array
    {
        return [
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
        ];
    }

    // --- the happy path ------------------------------------------------------

    public function test_a_customer_adds_a_configured_dish(): void
    {
        $response = $this->asRahul()
            ->postJson($this->url(), $this->validBody([
                'modifier_groups' => [
                    [
                        'group_id' => $this->menu['spice']->uuid,
                        'option_ids' => [$this->menu['mild']->uuid],
                    ],
                    [
                        'group_id' => $this->menu['extras']->uuid,
                        'option_ids' => [$this->menu['cheese']->uuid, $this->menu['jalapeno']->uuid],
                    ],
                ],
                'quantity' => 2,
                'special_instructions' => 'Less spicy please',
            ]))
            ->assertCreated();

        // 329 + 40 + 20 = 389, twice.
        $this->assertSame(38_900, $response->json('data.unit_price.amount_minor'));
        $this->assertSame(77_800, $response->json('data.line_total.amount_minor'));
        $this->assertSame('INR', $response->json('data.unit_price.currency'));
        $this->assertSame(2, $response->json('data.quantity'));

        $item = CartItem::query()->sole();

        $this->assertSame(38_900, (int) $item->unit_price_minor);
        $this->assertSame(77_800, (int) $item->line_total_minor);
        $this->assertSame('Less spicy please', $item->special_instructions);

        // Snapshots, so a rename tomorrow does not rewrite what was chosen.
        $this->assertSame('Paneer Tikka', $item->item_name_snapshot);
        $this->assertSame('Large', $item->variant_name_snapshot);

        $modifiers = $item->modifiers;

        $this->assertCount(3, $modifiers);
        $this->assertSame('Spice level', $modifiers[0]->group_name_snapshot);
        $this->assertSame('Mild', $modifiers[0]->option_name_snapshot);
        $this->assertSame(4_000, (int) $modifiers[1]->price_delta_minor);
    }

    public function test_the_cart_carries_the_customer_the_trip_and_the_restaurant(): void
    {
        $this->asRahul()->postJson($this->url(), $this->validBody())->assertCreated();

        $cart = Cart::query()->sole();

        $this->assertSame((int) $this->rahul->id, (int) $cart->customer_id);
        $this->assertSame((int) $this->trip->id, (int) $cart->trip_id);
        $this->assertSame((int) $this->restaurant->id, (int) $cart->restaurant_id);
        $this->assertTrue($cart->isActive());
        $this->assertNotNull($cart->expires_at);
    }

    public function test_a_dish_with_no_sizes_needs_no_size(): void
    {
        $category = MenuFixtures::category($this->restaurant, 'Breads', 1);
        $roti = MenuFixtures::item($category, 'Tandoori Roti', 3_900);

        $response = $this->asRahul()
            ->postJson($this->url(), ['item_id' => $roti->uuid, 'quantity' => 1])
            ->assertCreated();

        $this->assertSame(3_900, $response->json('data.unit_price.amount_minor'));
        $this->assertNull(CartItem::query()->sole()->variant_name_snapshot);
    }

    public function test_the_response_carries_a_breakdown_the_customer_can_check(): void
    {
        $response = $this->asRahul()
            ->postJson($this->url(), $this->validBody([
                'modifier_groups' => [
                    ['group_id' => $this->menu['spice']->uuid, 'option_ids' => [$this->menu['mild']->uuid]],
                    ['group_id' => $this->menu['extras']->uuid, 'option_ids' => [$this->menu['cheese']->uuid]],
                ],
                'quantity' => 2,
            ]))
            ->assertCreated();

        $this->assertSame('Large', $response->json('data.breakdown.base.label'));
        $this->assertSame(32_900, $response->json('data.breakdown.base.amount.amount_minor'));
        $this->assertSame('Mild', $response->json('data.breakdown.additions.0.name'));
        $this->assertSame(4_000, $response->json('data.breakdown.additions.1.amount.amount_minor'));
        $this->assertSame(73_800, $response->json('data.breakdown.line_total.amount_minor'));
    }

    // --- price authority -----------------------------------------------------

    public function test_a_client_supplied_price_changes_nothing(): void
    {
        $response = $this->asRahul()
            ->postJson($this->url(), $this->validBody([
                // Every shape an attacker would reach for.
                'unit_price_minor' => 1,
                'unit_price' => ['amount_minor' => 1, 'currency' => 'INR'],
                'line_total_minor' => 1,
                'subtotal' => 1,
                'discount' => 999_999,
                'tax' => 0,
                'final_total' => 1,
                'price' => 1,
            ]))
            ->assertCreated();

        // The dish is ₹329 and stays ₹329.
        $this->assertSame(32_900, $response->json('data.unit_price.amount_minor'));
        $this->assertSame(32_900, (int) CartItem::query()->sole()->unit_price_minor);
    }

    public function test_a_price_that_rose_since_the_screen_loaded_is_refused(): void
    {
        // The customer's screen said ₹329. The kitchen has since raised it.
        $this->menu['large']->forceFill(['price_minor' => 35_900])->save();

        $response = $this->asRahul()
            ->postJson($this->url(), $this->validBody([
                'quoted_unit_price_minor' => 32_900,
            ]))
            ->assertStatus(409);

        $this->assertSame(ApiErrorCode::PriceUpdated->value, $response->json('error.code'));
        $this->assertSame(35_900, $response->json('error.details.current_unit_price.amount_minor'));

        // And nothing was added: the customer has not agreed to the new figure.
        $this->assertSame(0, CartItem::query()->count());
    }

    public function test_a_price_that_fell_is_charged_at_the_lower_figure(): void
    {
        $this->menu['large']->forceFill(['price_minor' => 29_900])->save();

        $response = $this->asRahul()
            ->postJson($this->url(), $this->validBody([
                'quoted_unit_price_minor' => 32_900,
            ]))
            ->assertCreated();

        // Nobody needs a confirmation dialogue to be charged less.
        $this->assertSame(29_900, $response->json('data.unit_price.amount_minor'));
    }

    public function test_quoting_a_higher_price_than_the_real_one_buys_nothing(): void
    {
        $response = $this->asRahul()
            ->postJson($this->url(), $this->validBody([
                'quoted_unit_price_minor' => 99_999,
            ]))
            ->assertCreated();

        $this->assertSame(32_900, $response->json('data.unit_price.amount_minor'));
    }

    // --- ownership and eligibility -------------------------------------------

    public function test_another_customers_trip_is_not_found(): void
    {
        $ananya = CustomerFactory::ananya();
        $hers = RestaurantFixtures::tripWithSelectedRoute($ananya);

        $response = $this->asRahul()
            ->postJson($this->url(trip: $hers), $this->validBody())
            ->assertNotFound();

        $this->assertSame(ApiErrorCode::TripNotFound->value, $response->json('error.code'));
        $this->assertSame(0, Cart::query()->count());
    }

    public function test_an_unauthenticated_call_adds_nothing(): void
    {
        $this->postJson($this->url(), $this->validBody())->assertUnauthorized();

        $this->assertSame(0, Cart::query()->count());
    }

    public function test_a_suspended_restaurant_takes_no_orders(): void
    {
        $this->restaurant->forceFill(['status' => RestaurantStatus::Suspended])->save();
        Cache::flush();

        $this->asRahul()->postJson($this->url(), $this->validBody())->assertNotFound();

        $this->assertSame(0, Cart::query()->count());
    }

    public function test_a_paused_kitchen_takes_no_orders(): void
    {
        $this->restaurant->forceFill(['is_accepting_orders' => false])->save();
        Cache::flush();

        $response = $this->asRahul()
            ->postJson($this->url(), $this->validBody())
            ->assertStatus(409);

        $this->assertSame(
            ApiErrorCode::RestaurantNotAcceptingOrders->value,
            $response->json('error.code'),
        );
        $this->assertSame(0, Cart::query()->count());
    }

    public function test_an_item_from_another_restaurant_is_not_found(): void
    {
        $other = RestaurantFixtures::nearRoute(0.5, 900, 'Rajasthan Highway Bites');
        $theirs = MenuFixtures::configurableItem($other);

        $response = $this->asRahul()
            ->postJson($this->url(), [
                'item_id' => $theirs['item']->uuid,
                'quantity' => 1,
            ])
            ->assertNotFound();

        $this->assertSame(ApiErrorCode::ItemNotFound->value, $response->json('error.code'));
    }

    public function test_a_variant_from_another_item_is_refused(): void
    {
        $other = RestaurantFixtures::nearRoute(0.5, 900, 'Rajasthan Highway Bites');
        $theirs = MenuFixtures::configurableItem($other);

        $response = $this->asRahul()
            ->postJson($this->url(), $this->validBody([
                'variant_id' => $theirs['large']->uuid,
            ]))
            ->assertStatus(422);

        $this->assertSame(ApiErrorCode::VariantInvalid->value, $response->json('error.code'));
    }

    public function test_an_option_from_another_group_is_refused(): void
    {
        $sauces = MenuFixtures::group($this->restaurant, 'Choose a sauce', 0, 1);
        $garlic = MenuFixtures::option($sauces, 'Garlic', 3_000);

        $response = $this->asRahul()
            ->postJson($this->url(), $this->validBody([
                'modifier_groups' => [[
                    // Claiming the garlic belongs to the spice group. The group
                    // id in the request is ignored — an option knows its own.
                    'group_id' => $this->menu['spice']->uuid,
                    'option_ids' => [$this->menu['mild']->uuid, $garlic->uuid],
                ]],
            ]))
            ->assertStatus(422);

        $this->assertSame(ApiErrorCode::ModifierInvalid->value, $response->json('error.code'));
    }

    // --- selection rules over HTTP -------------------------------------------

    public function test_a_missing_required_group_names_the_group(): void
    {
        $response = $this->asRahul()
            ->postJson($this->url(), $this->validBody(['modifier_groups' => []]))
            ->assertStatus(422);

        $this->assertSame(ApiErrorCode::ModifierRequired->value, $response->json('error.code'));

        // Named, so the screen can scroll to it rather than saying "invalid".
        $this->assertSame($this->menu['spice']->uuid, $response->json('error.details.group_id'));
        $this->assertStringContainsString('Spice level', (string) $response->json('error.message'));
    }

    public function test_exceeding_a_maximum_says_what_the_maximum_is(): void
    {
        $third = MenuFixtures::option($this->menu['extras'], 'Extra Paneer', 6_000, ['order' => 2]);

        $response = $this->asRahul()
            ->postJson($this->url(), $this->validBody([
                'modifier_groups' => [
                    ['group_id' => $this->menu['spice']->uuid, 'option_ids' => [$this->menu['mild']->uuid]],
                    ['group_id' => $this->menu['extras']->uuid, 'option_ids' => [
                        $this->menu['cheese']->uuid,
                        $this->menu['jalapeno']->uuid,
                        $third->uuid,
                    ]],
                ],
            ]))
            ->assertStatus(422);

        $this->assertSame(ApiErrorCode::ModifierMaxExceeded->value, $response->json('error.code'));
        $this->assertSame(2, $response->json('error.details.max_select'));
    }

    public function test_a_flat_option_list_is_accepted_too(): void
    {
        $this->asRahul()
            ->postJson($this->url(), [
                'item_id' => $this->item()->uuid,
                'variant_id' => $this->menu['large']->uuid,
                'modifier_option_ids' => [$this->menu['mild']->uuid],
                'quantity' => 1,
            ])
            ->assertCreated();

        $this->assertSame(1, CartItem::query()->count());
    }

    // --- races ---------------------------------------------------------------

    public function test_an_item_that_sold_out_after_the_screen_loaded_is_refused(): void
    {
        $this->menu['item']->forceFill([
            'stock_status' => MenuItemStockStatus::SoldOut->value,
        ])->save();

        $response = $this->asRahul()
            ->postJson($this->url(), $this->validBody())
            ->assertStatus(409);

        $this->assertSame(ApiErrorCode::ItemSoldOut->value, $response->json('error.code'));
        $this->assertSame(0, CartItem::query()->count());
    }

    public function test_a_variant_that_sold_out_after_the_screen_loaded_is_refused(): void
    {
        $this->menu['large']->forceFill(['is_available' => false])->save();

        $response = $this->asRahul()
            ->postJson($this->url(), $this->validBody())
            ->assertStatus(409);

        $this->assertSame(ApiErrorCode::VariantUnavailable->value, $response->json('error.code'));
    }

    public function test_an_option_that_sold_out_after_the_screen_loaded_is_refused(): void
    {
        $this->menu['cheese']->forceFill(['is_available' => false])->save();

        $response = $this->asRahul()
            ->postJson($this->url(), $this->validBody([
                'modifier_groups' => [
                    ['group_id' => $this->menu['spice']->uuid, 'option_ids' => [$this->menu['mild']->uuid]],
                    ['group_id' => $this->menu['extras']->uuid, 'option_ids' => [$this->menu['cheese']->uuid]],
                ],
            ]))
            ->assertStatus(409);

        $this->assertSame(ApiErrorCode::ModifierUnavailable->value, $response->json('error.code'));
        $this->assertSame($this->menu['cheese']->uuid, $response->json('error.details.option_id'));
    }

    // --- quantity and notes ---------------------------------------------------

    public function test_a_tampered_quantity_is_refused(): void
    {
        foreach ([0, -1, 999_999] as $quantity) {
            $this->asRahul()
                ->postJson($this->url(), $this->validBody(['quantity' => $quantity]))
                ->assertStatus(422);
        }

        foreach (['2.5', 'two', true, []] as $quantity) {
            $this->asRahul()
                ->postJson($this->url(), $this->validBody(['quantity' => $quantity]))
                ->assertStatus(422);
        }

        $this->assertSame(0, CartItem::query()->count());
    }

    public function test_an_oversized_note_is_refused(): void
    {
        $max = (int) config('foodonthego.cart.max_special_instructions');

        $response = $this->asRahul()
            ->postJson($this->url(), $this->validBody([
                'special_instructions' => str_repeat('a', $max + 1),
            ]))
            ->assertStatus(422);

        $this->assertSame(
            ApiErrorCode::SpecialInstructionsTooLong->value,
            $response->json('error.code'),
        );
    }

    public function test_a_note_is_stored_as_written_and_never_executed(): void
    {
        $hostile = '<script>alert(1)</script> & "quotes" '."\n".'no onion — ज्यादा तीखा नहीं 🌶';

        $this->asRahul()
            ->postJson($this->url(), $this->validBody(['special_instructions' => $hostile]))
            ->assertCreated();

        $stored = (string) CartItem::query()->sole()->special_instructions;

        // Stored verbatim. Escaping on the way in would double-escape on the
        // way out, and the place to make markup safe is where it is rendered.
        $this->assertStringContainsString('<script>', $stored);
        $this->assertStringContainsString('🌶', $stored);
        $this->assertStringContainsString('ज्यादा', $stored);

        // And the response quotes it back as text, not as markup.
        $response = $this->asRahul()
            ->getJson('/api/v1/customer/trips/'.$this->trip->uuid.'/cart')
            ->assertOk();

        $this->assertStringNotContainsString('<script>', $response->getContent() ?: '');
    }

    // --- cart line matching --------------------------------------------------

    public function test_the_same_configuration_twice_increments_one_line(): void
    {
        $this->asRahul()->postJson($this->url(), $this->validBody(['quantity' => 1]))->assertCreated();

        $second = $this->asRahul()
            ->postJson($this->url(), $this->validBody(['quantity' => 2]))
            ->assertCreated();

        $this->assertTrue($second->json('data.merged_with_existing_line'));
        $this->assertSame(3, $second->json('data.quantity'));
        $this->assertSame(1, CartItem::query()->count());
        $this->assertSame(98_700, (int) CartItem::query()->sole()->line_total_minor);
    }

    public function test_option_order_does_not_split_a_line(): void
    {
        $body = fn (array $options): array => $this->validBody([
            'modifier_groups' => [
                ['group_id' => $this->menu['spice']->uuid, 'option_ids' => [$this->menu['mild']->uuid]],
                ['group_id' => $this->menu['extras']->uuid, 'option_ids' => $options],
            ],
        ]);

        $this->asRahul()->postJson($this->url(), $body([
            $this->menu['cheese']->uuid, $this->menu['jalapeno']->uuid,
        ]))->assertCreated();

        $this->asRahul()->postJson($this->url(), $body([
            $this->menu['jalapeno']->uuid, $this->menu['cheese']->uuid,
        ]))->assertCreated();

        // Cheese-then-jalapeño is the same order as jalapeño-then-cheese.
        $this->assertSame(1, CartItem::query()->count());
    }

    public function test_a_different_size_is_a_different_line(): void
    {
        $this->asRahul()->postJson($this->url(), $this->validBody())->assertCreated();
        $this->asRahul()->postJson($this->url(), $this->validBody([
            'variant_id' => $this->menu['regular']->uuid,
        ]))->assertCreated();

        $this->assertSame(2, CartItem::query()->count());
    }

    public function test_a_different_note_is_a_different_line(): void
    {
        $this->asRahul()->postJson($this->url(), $this->validBody([
            'special_instructions' => 'No onion',
        ]))->assertCreated();

        $this->asRahul()->postJson($this->url(), $this->validBody([
            'special_instructions' => 'Extra onion',
        ]))->assertCreated();

        // Not a detail the kitchen can merge.
        $this->assertSame(2, CartItem::query()->count());
    }

    public function test_merging_still_respects_the_quantity_ceiling(): void
    {
        $max = (int) config('foodonthego.cart.max_quantity_per_line');

        $this->asRahul()->postJson($this->url(), $this->validBody([
            'quantity' => $max,
        ]))->assertCreated();

        $response = $this->asRahul()
            ->postJson($this->url(), $this->validBody(['quantity' => 1]))
            ->assertStatus(422);

        $this->assertSame(
            ApiErrorCode::QuantityLimitExceeded->value,
            $response->json('error.code'),
        );
        $this->assertSame($max, (int) CartItem::query()->sole()->quantity);
    }

    // --- conflicts -----------------------------------------------------------

    public function test_a_second_restaurant_is_a_conflict_and_changes_nothing(): void
    {
        $other = RestaurantFixtures::nearRoute(0.5, 900, 'Rajasthan Highway Bites');
        $theirs = MenuFixtures::configurableItem($other);

        $this->asRahul()->postJson($this->url(), $this->validBody())->assertCreated();

        // The corridor result was cached by the first add. Both restaurants
        // existed before it, so both are in it.
        $response = $this->asRahul()
            ->postJson($this->url(restaurant: $other), [
                'item_id' => $theirs['item']->uuid,
                'variant_id' => $theirs['large']->uuid,
                'modifier_option_ids' => [$theirs['mild']->uuid],
                'quantity' => 1,
            ])
            ->assertStatus(409);

        $this->assertSame(
            ApiErrorCode::CartRestaurantConflict->value,
            $response->json('error.code'),
        );

        // Named, so the screen can say which restaurant rather than "conflict".
        $this->assertSame('Highway Spice Kitchen', $response->json('error.details.restaurant_name'));

        // And nothing was destroyed to make the call succeed.
        $this->assertSame(1, Cart::query()->count());
        $this->assertSame(1, CartItem::query()->count());
    }

    public function test_a_second_journey_is_a_conflict_and_changes_nothing(): void
    {
        $this->asRahul()->postJson($this->url(), $this->validBody())->assertCreated();

        $second = RestaurantFixtures::tripWithSelectedRoute($this->rahul);
        Cache::flush();

        $response = $this->asRahul()
            ->postJson($this->url(trip: $second), $this->validBody())
            ->assertStatus(409);

        $this->assertSame(ApiErrorCode::CartTripConflict->value, $response->json('error.code'));
        $this->assertSame(1, Cart::query()->count());
    }

    // --- idempotency ---------------------------------------------------------

    public function test_a_retry_with_the_same_key_adds_nothing_twice(): void
    {
        $key = (string) Str::uuid();
        $body = $this->validBody(['quantity' => 2]);

        $first = $this->asRahul()
            ->withHeader('Idempotency-Key', $key)
            ->postJson($this->url(), $body)
            ->assertCreated();

        // The response was lost; the client retries the identical request.
        $second = $this->asRahul()
            ->withHeader('Idempotency-Key', $key)
            ->postJson($this->url(), $body)
            ->assertCreated();

        $this->assertSame($first->json('data.cart_item_id'), $second->json('data.cart_item_id'));
        $this->assertSame(2, $second->json('data.quantity'));

        // Exactly one logical line, at the quantity asked for once.
        $this->assertSame(1, CartItem::query()->count());
        $this->assertSame(2, (int) CartItem::query()->sole()->quantity);
    }

    public function test_a_reused_key_with_a_different_body_is_refused(): void
    {
        $key = (string) Str::uuid();

        $this->asRahul()
            ->withHeader('Idempotency-Key', $key)
            ->postJson($this->url(), $this->validBody(['quantity' => 1]))
            ->assertCreated();

        // A client bug or an attack, not a retry.
        $this->asRahul()
            ->withHeader('Idempotency-Key', $key)
            ->postJson($this->url(), $this->validBody(['quantity' => 5]))
            ->assertStatus(409);

        $this->assertSame(1, (int) CartItem::query()->sole()->quantity);
    }

    public function test_without_a_key_a_repeat_is_an_ordinary_second_add(): void
    {
        $this->asRahul()->postJson($this->url(), $this->validBody())->assertCreated();
        $this->asRahul()->postJson($this->url(), $this->validBody())->assertCreated();

        // Merged into one line at quantity two — which is what "add it again"
        // means without a key saying "this is the same request".
        $this->assertSame(1, CartItem::query()->count());
        $this->assertSame(2, (int) CartItem::query()->sole()->quantity);
    }

    // --- the badge -----------------------------------------------------------

    public function test_an_empty_cart_is_a_state_not_an_error(): void
    {
        $response = $this->asRahul()
            ->getJson('/api/v1/customer/trips/'.$this->trip->uuid.'/cart')
            ->assertOk();

        $this->assertNull($response->json('data.cart'));
        $this->assertSame(0, $response->json('data.item_count'));
    }

    public function test_the_badge_counts_items_not_lines(): void
    {
        $this->asRahul()->postJson($this->url(), $this->validBody(['quantity' => 2]))->assertCreated();
        $this->asRahul()->postJson($this->url(), $this->validBody([
            'variant_id' => $this->menu['regular']->uuid,
            'quantity' => 3,
        ]))->assertCreated();

        $response = $this->asRahul()
            ->getJson('/api/v1/customer/trips/'.$this->trip->uuid.'/cart')
            ->assertOk();

        $this->assertSame(5, $response->json('data.item_count'));
        $this->assertSame(2, $response->json('data.line_count'));
        $this->assertSame(140_500, $response->json('data.cart.subtotal.amount_minor'));
    }

    public function test_another_customers_cart_is_unreachable(): void
    {
        $this->asRahul()->postJson($this->url(), $this->validBody())->assertCreated();

        $ananya = CustomerFactory::ananya();
        $herToken = CustomerFactory::tokenFor($ananya);

        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        // Rahul's trip id, Ananya's token. The trip is not hers, so there is
        // nothing to read.
        $this->withHeader('Authorization', 'Bearer '.$herToken)
            ->getJson('/api/v1/customer/trips/'.$this->trip->uuid.'/cart')
            ->assertNotFound();
    }

    // --- privacy -------------------------------------------------------------

    public function test_the_response_carries_no_operator_private_data(): void
    {
        $body = $this->asRahul()
            ->postJson($this->url(), $this->validBody())
            ->assertCreated()
            ->getContent() ?: '';

        foreach ([
            'cost_price', 'margin', 'vendor', 'supplier', 'commission',
            'internal', 'stock_quantity', 'gst_number', 'bank',
        ] as $forbidden) {
            $this->assertStringNotContainsString($forbidden, strtolower($body));
        }
    }

    public function test_no_internal_database_key_is_exposed(): void
    {
        $response = $this->asRahul()
            ->postJson($this->url(), $this->validBody())
            ->assertCreated();

        $this->assertSame(36, strlen((string) $response->json('data.cart_id')));
        $this->assertSame(36, strlen((string) $response->json('data.cart_item_id')));

        $body = $response->getContent() ?: '';

        $this->assertStringNotContainsString('menu_item_id', $body);
        $this->assertStringNotContainsString('"customer_id"', $body);
    }
}
