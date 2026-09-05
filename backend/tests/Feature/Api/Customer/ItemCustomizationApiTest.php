<?php

declare(strict_types=1);

namespace Tests\Feature\Api\Customer;

use App\Models\Restaurant;
use App\Models\Trip;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Cache;
use Tests\Support\CustomerFactory;
use Tests\Support\MenuFixtures;
use Tests\Support\RestaurantFixtures;
use Tests\TestCase;

/**
 * What the item detail endpoint tells a client about configuring a dish.
 *
 * The rules travel as numbers, not prose, so the screen can enforce them
 * without parsing English and a future locale does not have to translate a
 * rule to make it work.
 */
final class ItemCustomizationApiTest extends TestCase
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

    private function itemUrl(?string $uuid = null): string
    {
        return '/api/v1/customer/trips/'.$this->trip->uuid
            .'/restaurants/'.$this->restaurant->uuid
            .'/menu/items/'.($uuid ?? $this->menu['item']->uuid);
    }

    public function test_the_sizes_come_back_in_the_operators_order(): void
    {
        $response = $this->asRahul()->getJson($this->itemUrl())->assertOk();

        $names = array_column($response->json('data.customization.variants'), 'name');

        $this->assertSame(['Regular', 'Large'], $names);
        $this->assertSame(24_900, $response->json('data.customization.variants.0.price.amount_minor'));
        $this->assertSame(32_900, $response->json('data.customization.variants.1.price.amount_minor'));
    }

    public function test_the_configured_default_is_marked_and_no_choice_is_required(): void
    {
        $response = $this->asRahul()->getJson($this->itemUrl())->assertOk();

        $this->assertTrue($response->json('data.customization.variants.0.is_default'));
        $this->assertFalse($response->json('data.customization.variants.1.is_default'));

        // A default exists, so the screen opens on a price somebody chose to
        // show rather than demanding a decision first.
        $this->assertFalse($response->json('data.customization.requires_variant'));
    }

    public function test_without_a_default_a_size_must_be_chosen(): void
    {
        $this->menu['regular']->forceFill(['is_default' => false])->save();

        $response = $this->asRahul()->getJson($this->itemUrl())->assertOk();

        $this->assertTrue($response->json('data.customization.requires_variant'));
    }

    public function test_a_default_that_has_gone_unavailable_is_no_longer_a_default(): void
    {
        $this->menu['regular']->forceFill(['is_available' => false])->save();

        $response = $this->asRahul()->getJson($this->itemUrl())->assertOk();

        // The screen asks rather than quoting a price for a size the kitchen
        // cannot make.
        $this->assertTrue($response->json('data.customization.requires_variant'));
        $this->assertFalse($response->json('data.customization.variants.0.is_available'));
    }

    public function test_a_withdrawn_size_is_absent_and_a_sold_out_one_is_shown(): void
    {
        MenuFixtures::variant($this->menu['item'], 'Family', 54_900, ['available' => false, 'order' => 2]);
        MenuFixtures::variant($this->menu['item'], 'Discontinued', 19_900, ['active' => false, 'order' => 3]);

        $response = $this->asRahul()->getJson($this->itemUrl())->assertOk();

        $names = array_column($response->json('data.customization.variants'), 'name');

        // Withdrawn means gone. Sold out means shown, disabled — a customer
        // who came for the family size learns why.
        $this->assertNotContains('Discontinued', $names);
        $this->assertContains('Family', $names);
        $this->assertFalse($response->json('data.customization.variants.2.is_available'));
    }

    public function test_a_group_carries_its_rules_as_numbers(): void
    {
        $response = $this->asRahul()->getJson($this->itemUrl())->assertOk();

        $spice = $response->json('data.customization.modifier_groups.0');

        $this->assertSame('Spice level', $spice['name']);
        $this->assertSame(1, $spice['min_select']);
        $this->assertSame(1, $spice['max_select']);
        $this->assertTrue($spice['is_required']);
        $this->assertTrue($spice['is_single_select']);

        $extras = $response->json('data.customization.modifier_groups.1');

        $this->assertSame(0, $extras['min_select']);
        $this->assertSame(2, $extras['max_select']);
        $this->assertFalse($extras['is_required']);
        $this->assertFalse($extras['is_single_select']);
    }

    public function test_an_option_carries_its_delta_and_never_a_total(): void
    {
        $response = $this->asRahul()->getJson($this->itemUrl())->assertOk();

        $cheese = $response->json('data.customization.modifier_groups.1.options.0');

        $this->assertSame('Extra Cheese', $cheese['name']);
        $this->assertSame(4_000, $cheese['price_delta']['amount_minor']);
        $this->assertSame('INR', $cheese['price_delta']['currency']);

        // A free option is zero, not absent: "Mild — no charge" is worth
        // seeing.
        $this->assertSame(0, $response->json(
            'data.customization.modifier_groups.0.options.0.price_delta.amount_minor',
        ));
    }

    public function test_a_free_default_option_is_marked_and_a_paid_one_never_is(): void
    {
        $this->menu['cheese']->forceFill(['is_default' => true])->save();

        $response = $this->asRahul()->getJson($this->itemUrl())->assertOk();

        $this->assertTrue($response->json('data.customization.modifier_groups.0.options.0.is_default'));

        // Starting a customer at "Extra Cheese +₹40" and letting them find it
        // at the total is a dark pattern. The column can say so; the API will
        // not.
        $this->assertFalse($response->json('data.customization.modifier_groups.1.options.0.is_default'));
    }

    public function test_a_withdrawn_option_is_absent_and_a_sold_out_one_is_shown(): void
    {
        MenuFixtures::option($this->menu['extras'], 'Extra Cashew', 8_000, ['available' => false, 'order' => 2]);
        MenuFixtures::option($this->menu['extras'], 'Gone', 1_000, ['active' => false, 'order' => 3]);

        $response = $this->asRahul()->getJson($this->itemUrl())->assertOk();

        $names = array_column($response->json('data.customization.modifier_groups.1.options'), 'name');

        $this->assertNotContains('Gone', $names);
        $this->assertContains('Extra Cashew', $names);
    }

    public function test_a_withdrawn_group_is_not_asked_about(): void
    {
        $this->menu['extras']->forceFill(['is_active' => false])->save();

        $response = $this->asRahul()->getJson($this->itemUrl())->assertOk();

        $this->assertCount(1, $response->json('data.customization.modifier_groups'));
    }

    public function test_a_dish_with_no_customization_says_so_plainly(): void
    {
        $category = MenuFixtures::category($this->restaurant, 'Breads', 1);
        $roti = MenuFixtures::item($category, 'Tandoori Roti', 3_900);

        $response = $this->asRahul()->getJson($this->itemUrl($roti->uuid))->assertOk();

        // Empty lists, not a fabricated "Regular" and not a null the client has
        // to guess at.
        $this->assertSame([], $response->json('data.customization.variants'));
        $this->assertSame([], $response->json('data.customization.modifier_groups'));
        $this->assertFalse($response->json('data.customization.requires_variant'));
    }

    public function test_the_limits_travel_with_the_item(): void
    {
        $response = $this->asRahul()->getJson($this->itemUrl())->assertOk();

        // So the stepper and the note counter do not hard-code a number the
        // server could change tomorrow.
        $this->assertSame(
            (int) config('foodonthego.cart.max_quantity_per_line'),
            $response->json('data.customization.limits.max_quantity'),
        );
        $this->assertSame(
            (int) config('foodonthego.cart.max_special_instructions'),
            $response->json('data.customization.limits.max_special_instructions'),
        );
    }

    public function test_a_size_may_override_the_preparation_time(): void
    {
        $this->menu['large']->forceFill(['preparation_minutes' => 25])->save();

        $response = $this->asRahul()->getJson($this->itemUrl())->assertOk();

        $this->assertNull($response->json('data.customization.variants.0.preparation_minutes'));
        $this->assertSame(25, $response->json('data.customization.variants.1.preparation_minutes'));
    }

    public function test_another_restaurants_item_is_still_not_found(): void
    {
        $other = RestaurantFixtures::nearRoute(0.5, 900, 'Rajasthan Highway Bites');
        $theirs = MenuFixtures::configurableItem($other);

        $this->asRahul()->getJson($this->itemUrl($theirs['item']->uuid))->assertNotFound();
    }

    public function test_the_customization_payload_carries_nothing_private(): void
    {
        $body = strtolower($this->asRahul()->getJson($this->itemUrl())->assertOk()->getContent() ?: '');

        foreach ([
            'cost_price', 'margin', 'vendor', 'supplier', 'commission',
            'stock_quantity', 'restaurant_id', 'menu_modifier_group_id',
        ] as $forbidden) {
            $this->assertStringNotContainsString($forbidden, $body);
        }
    }
}
