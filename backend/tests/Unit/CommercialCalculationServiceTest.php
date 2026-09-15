<?php

declare(strict_types=1);

namespace Tests\Unit;

use App\Models\Cart;
use App\Models\Restaurant;
use App\Services\Cart\CartTotalsService;
use App\Services\Checkout\CommercialBreakdown;
use App\Services\Checkout\CommercialCalculationService;
use App\Services\Checkout\CommercialComponent;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Support\CartFixtures;
use Tests\Support\CustomerFactory;
use Tests\Support\MenuFixtures;
use Tests\Support\RestaurantFixtures;
use Tests\TestCase;

/**
 * What the customer owes, and which of it anybody actually chose.
 *
 * The theme is the distinction the whole class exists for: **"not configured"
 * and "configured as zero" are different facts**, and only one of them belongs
 * on a customer's screen. A row reading "Tax  0.00" states a tax decision the
 * platform has not made.
 *
 * The second theme is that no arithmetic lives here. Every total is Module 12's,
 * and a test below proves the two agree rather than assuming it.
 */
final class CommercialCalculationServiceTest extends TestCase
{
    use RefreshDatabase;

    private function service(): CommercialCalculationService
    {
        return new CommercialCalculationService(new CartTotalsService);
    }

    private function cartWith(Restaurant $restaurant, int $priceMinor = 24_900): Cart
    {
        $rahul = CustomerFactory::rahul();
        $trip = RestaurantFixtures::tripWithSelectedRoute($rahul);

        $cart = CartFixtures::activeCart($rahul, $trip, $restaurant);

        $category = MenuFixtures::category($restaurant, 'Mains');
        $item = MenuFixtures::item($category, 'Paneer Tikka', $priceMinor);

        CartFixtures::line($cart, $item);

        return $cart->fresh(['items', 'restaurant']) ?? $cart;
    }

    private function componentIn(CommercialBreakdown $breakdown, string $code): ?CommercialComponent
    {
        foreach ([...$breakdown->charges, ...$breakdown->discounts] as $component) {
            if ($component->code === $code) {
                return $component;
            }
        }

        return null;
    }

    // --- nothing configured ---------------------------------------------------

    public function test_with_nothing_configured_the_payable_total_is_the_items_subtotal(): void
    {
        $restaurant = RestaurantFixtures::nearRoute(0.4, 800, 'Highway Spice Kitchen');

        $breakdown = $this->service()->breakdownFor($this->cartWith($restaurant));

        $this->assertSame(24_900, $breakdown->itemsSubtotal->minor);
        $this->assertSame(24_900, $breakdown->payableTotal->minor);
        $this->assertSame([], $breakdown->configured());
    }

    public function test_an_unconfigured_component_is_absent_from_the_wire_not_zero(): void
    {
        $restaurant = RestaurantFixtures::nearRoute(0.4, 800, 'Highway Spice Kitchen');

        $wire = $this->service()->breakdownFor($this->cartWith($restaurant))->toApiArray();

        // Absent, not "0.00". A zero row tells a customer a decision was made
        // when none was, and this is the difference the class exists to keep.
        $this->assertSame([], $wire['charges']);
        $this->assertSame([], $wire['discounts']);
        $this->assertFalse($wire['has_configured_adjustments']);
    }

    // --- configured as zero ---------------------------------------------------

    public function test_a_restaurant_that_has_explicitly_set_no_tax_is_configured(): void
    {
        $restaurant = RestaurantFixtures::nearRoute(0.4, 800, 'Highway Spice Kitchen');
        $restaurant->forceFill(['tax_rate_bps' => 0])->save();

        $breakdown = $this->service()->breakdownFor($this->cartWith($restaurant->fresh()));

        // An operator who has recorded "no tax here" has made a decision, and
        // the screen should show it. Null would be the absence of a rule; zero
        // is a rule.
        $tax = $this->componentIn($breakdown, 'TAX');

        $this->assertNotNull($tax);
        $this->assertTrue($tax->configured);
        $this->assertSame(0, $tax->amount->minor);
    }

    public function test_a_platform_tax_rate_of_nought_is_not_a_rule(): void
    {
        config(['foodonthego.cart.tax_rate_bps' => 0]);

        $restaurant = RestaurantFixtures::nearRoute(0.4, 800, 'Highway Spice Kitchen');

        $tax = $this->componentIn(
            $this->service()->breakdownFor($this->cartWith($restaurant)),
            'TAX',
        );

        // Unlike a restaurant's own rate there is no null to read here — the
        // config cast makes it an integer either way, so an unset rate and a
        // rate set to nothing are indistinguishable. Read as absent, which is
        // the reading that cannot put a phantom charge on a screen.
        $this->assertFalse($tax?->configured);
    }

    // --- configured, non-zero -------------------------------------------------

    public function test_a_real_tax_rate_is_charged_and_shown(): void
    {
        $restaurant = RestaurantFixtures::nearRoute(0.4, 800, 'Highway Spice Kitchen');
        $restaurant->forceFill(['tax_rate_bps' => 500])->save();

        $breakdown = $this->service()->breakdownFor($this->cartWith($restaurant->fresh()));

        // 5% of 24,900 paise is 1,245 exactly.
        $tax = $this->componentIn($breakdown, 'TAX');

        $this->assertTrue($tax?->configured);
        $this->assertSame(1_245, $tax?->amount->minor);
        $this->assertSame(24_900 + 1_245, $breakdown->payableTotal->minor);
    }

    public function test_a_restaurant_packaging_fee_is_charged_and_shown(): void
    {
        $restaurant = RestaurantFixtures::nearRoute(0.4, 800, 'Highway Spice Kitchen');
        $restaurant->forceFill(['packaging_fee_minor' => 2_000])->save();

        $breakdown = $this->service()->breakdownFor($this->cartWith($restaurant->fresh()));

        $packaging = $this->componentIn($breakdown, 'PACKAGING_FEE');

        $this->assertTrue($packaging?->configured);
        $this->assertSame(2_000, $packaging?->amount->minor);
        $this->assertSame(26_900, $breakdown->payableTotal->minor);
    }

    public function test_a_packaging_fee_nobody_has_set_is_absent(): void
    {
        $restaurant = RestaurantFixtures::nearRoute(0.4, 800, 'Highway Spice Kitchen');

        // Null, which is what an unset fee is. Module 14 made this column
        // nullable precisely so the distinction could be expressed; before that
        // every restaurant read as "configured" and every checkout grew a
        // zero-value packaging row.
        $this->assertNull($restaurant->packaging_fee_minor);

        $packaging = $this->componentIn(
            $this->service()->breakdownFor($this->cartWith($restaurant)),
            'PACKAGING_FEE',
        );

        $this->assertFalse($packaging?->configured);
    }

    public function test_a_platform_fee_is_charged_and_shown(): void
    {
        config(['foodonthego.cart.platform_fee_minor' => 500]);

        $restaurant = RestaurantFixtures::nearRoute(0.4, 800, 'Highway Spice Kitchen');

        $breakdown = $this->service()->breakdownFor($this->cartWith($restaurant));
        $platform = $this->componentIn($breakdown, 'PLATFORM_FEE');

        $this->assertTrue($platform?->configured);
        $this->assertSame(500, $platform?->amount->minor);
        $this->assertSame(25_400, $breakdown->payableTotal->minor);
    }

    // --- nothing is invented --------------------------------------------------

    public function test_no_discount_mechanism_exists_and_the_component_says_so(): void
    {
        $restaurant = RestaurantFixtures::nearRoute(0.4, 800, 'Highway Spice Kitchen');

        $discount = $this->componentIn(
            $this->service()->breakdownFor($this->cartWith($restaurant)),
            'DISCOUNT',
        );

        // Always unconfigured, and that is not a placeholder: no coupon,
        // promotion or discount rule exists anywhere in this project. The day
        // one is built, THIS assertion is what fails, which is the point of
        // writing it down.
        $this->assertNotNull($discount);
        $this->assertFalse($discount->configured);
        $this->assertSame(0, $discount->amount->minor);
    }

    public function test_the_service_invents_no_component_of_its_own(): void
    {
        $restaurant = RestaurantFixtures::nearRoute(0.4, 800, 'Highway Spice Kitchen');

        $breakdown = $this->service()->breakdownFor($this->cartWith($restaurant));

        $codes = array_map(
            static fn (CommercialComponent $c): string => $c->code,
            [...$breakdown->charges, ...$breakdown->discounts],
        );

        // Exactly the components this project has a source for. No GST, no
        // service charge, no convenience fee, no delivery fee — a plausible
        // name here would ship as a real charge on a real customer.
        sort($codes);
        $this->assertSame(
            ['DISCOUNT', 'PACKAGING_FEE', 'PLATFORM_FEE', 'TAX'],
            $codes,
        );
    }

    // --- one money path -------------------------------------------------------

    public function test_the_payable_total_is_module_twelve_s_total_and_not_a_second_sum(): void
    {
        config(['foodonthego.cart.platform_fee_minor' => 700]);

        $restaurant = RestaurantFixtures::nearRoute(0.4, 800, 'Highway Spice Kitchen');
        $restaurant->forceFill(['tax_rate_bps' => 725, 'packaging_fee_minor' => 1_100])->save();

        $cart = $this->cartWith($restaurant->fresh(), 20_000);

        $service = $this->service();

        // The same figure, from the module that owns it. A second sum here that
        // happened to agree today is the thing this assertion exists to stop
        // being written.
        $this->assertSame(
            (new CartTotalsService)->totalsFor($cart)->total->minor,
            $service->breakdownFor($cart)->payableTotal->minor,
        );
    }

    public function test_money_stays_in_integer_minor_units_at_every_step(): void
    {
        $restaurant = RestaurantFixtures::nearRoute(0.4, 800, 'Highway Spice Kitchen');
        // 7.25% of 200 paise is 14.5 exactly. Integer arithmetic rounds half up
        // to 15; the float path answers 14, because 200 * 0.0725 is
        // 14.499999999999998 in binary.
        $restaurant->forceFill(['tax_rate_bps' => 725])->save();

        $breakdown = $this->service()->breakdownFor($this->cartWith($restaurant->fresh(), 200));

        $this->assertSame(15, $this->componentIn($breakdown, 'TAX')?->amount->minor);
        $this->assertIsInt($breakdown->payableTotal->minor);
        $this->assertSame(215, $breakdown->payableTotal->minor);
    }

    public function test_a_large_cart_does_not_overflow(): void
    {
        config(['foodonthego.cart.platform_fee_minor' => 100_000]);

        $restaurant = RestaurantFixtures::nearRoute(0.4, 800, 'Highway Spice Kitchen');
        $restaurant->forceFill(['tax_rate_bps' => 2_800, 'packaging_fee_minor' => 50_000])->save();

        // Ten crore paise of dishes, which is a controlled ceiling well beyond
        // any real basket and well inside a 64-bit integer.
        $cart = $this->cartWith($restaurant->fresh(), 1_000_000_000);

        $breakdown = $this->service()->breakdownFor($cart);

        $this->assertSame(1_000_000_000, $breakdown->itemsSubtotal->minor);
        $this->assertSame(280_000_000, $this->componentIn($breakdown, 'TAX')?->amount->minor);
        $this->assertSame(1_280_150_000, $breakdown->payableTotal->minor);
        $this->assertGreaterThan(0, $breakdown->payableTotal->minor);
    }

    // --- what does not reach the customer -------------------------------------

    public function test_the_rate_behind_a_charge_is_never_on_the_wire(): void
    {
        $restaurant = RestaurantFixtures::nearRoute(0.4, 800, 'Highway Spice Kitchen');
        $restaurant->forceFill(['tax_rate_bps' => 500])->save();

        $wire = json_encode(
            $this->service()->breakdownFor($this->cartWith($restaurant->fresh()))->toApiArray(),
        );

        // A customer needs to know what they are paying. The rate that produced
        // it, and whether it came from the restaurant or the platform, is the
        // platform's business and a competitor's interest.
        $this->assertStringNotContainsString('500', (string) $wire);
        $this->assertStringNotContainsString('basis', (string) $wire);
        $this->assertStringNotContainsString('restaurant', (string) $wire);
        $this->assertStringNotContainsString('bps', (string) $wire);
    }
}
