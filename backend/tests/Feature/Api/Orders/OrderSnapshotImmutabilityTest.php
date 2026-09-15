<?php

declare(strict_types=1);

namespace Tests\Feature\Api\Orders;

use App\Models\CartItemModifier;
use App\Models\CheckoutQuote;
use App\Models\MenuItem;
use App\Models\MenuModifierOption;
use App\Models\Order;
use App\Models\Restaurant;
use App\Models\Trip;
use App\Models\User;
use App\Services\Orders\OrderNumberGenerator;
use App\Services\Payments\PaymentGateway;
use App\Services\Payments\RazorpaySignature;
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Cache;
use Tests\Support\CartFixtures;
use Tests\Support\CustomerFactory;
use Tests\Support\FakePaymentGateway;
use Tests\Support\MenuFixtures;
use Tests\Support\RestaurantFixtures;
use Tests\TestCase;

/**
 * A receipt is a record of what happened, not a view of what is true now.
 *
 * Restaurants rename dishes, reprice them, withdraw them, drop a size and
 * discontinue an add-on — all of it routine, none of it retrospective. An order
 * placed in March has to keep saying what was bought in March, and it has to
 * keep saying it when the menu row it came from no longer exists.
 *
 * Each test below places a real order, then does something destructive to the
 * menu, then re-reads the order over HTTP and asserts nothing moved.
 */
final class OrderSnapshotImmutabilityTest extends TestCase
{
    use RefreshDatabase;

    private const KEY_SECRET = 'rzp-test-secret';

    private User $rahul;

    private Trip $trip;

    private Restaurant $restaurant;

    private MenuItem $item;

    private FakePaymentGateway $gateway;

    /** @var array<string, mixed> */
    private array $menu;

    protected function setUp(): void
    {
        parent::setUp();

        Cache::flush();

        config([
            'services.razorpay.key_id' => 'rzp_test_fake',
            'services.razorpay.key_secret' => self::KEY_SECRET,
            'services.razorpay.webhook_secret' => 'test-webhook-secret',
        ]);

        $this->gateway = new FakePaymentGateway;
        $this->app->instance(PaymentGateway::class, $this->gateway);

        $this->rahul = CustomerFactory::rahul();
        $this->trip = RestaurantFixtures::tripWithSelectedRoute($this->rahul);
        $this->restaurant = RestaurantFixtures::nearRoute(0.4, 800, 'Highway Spice Kitchen');

        $this->restaurant->openingHours()->delete();
        RestaurantFixtures::openDaily($this->restaurant, '09:00:00', '22:00:00');

        // A dish with a size and an add-on, so variant and modifier snapshots
        // have something to be about.
        $this->menu = MenuFixtures::configurableItem($this->restaurant);
        $this->item = $this->menu['item'];

        $cart = CartFixtures::activeCart($this->rahul, $this->trip, $this->restaurant);
        $line = CartFixtures::line($cart, $this->item, 2, $this->menu['large']);

        $delta = 0;

        foreach ([$this->menu['mild'], $this->menu['cheese']] as $index => $option) {
            $modifier = new CartItemModifier;
            $modifier->forceFill([
                'cart_item_id' => $line->id,
                'menu_modifier_group_id' => $option->menu_modifier_group_id,
                'menu_modifier_option_id' => $option->id,
                'group_name_snapshot' => $option->group->name,
                'option_name_snapshot' => $option->name,
                'price_delta_minor' => $option->price_delta_minor,
                'currency' => 'INR',
                'display_order' => $index,
            ])->save();

            $delta += (int) $option->price_delta_minor;
        }

        /*
         | The line totals have to include the add-ons, or the cart is
         | internally inconsistent and checkout answers STALE.
         |
         | CartFixtures::line prices a line from its variant alone, because
         | every existing caller adds no modifiers. Writing modifier rows
         | beside it without repricing leaves a basket whose stated total does
         | not match its own contents — which the checkout service correctly
         | refuses to quote. It cost a debugging round; the alternative was
         | assuming the fixture covered a case it was never written for.
         */
        $unit = (int) $this->menu['large']->price_minor + $delta;

        $line->forceFill([
            'unit_price_minor' => $unit,
            'line_total_minor' => $unit * 2,
        ])->save();

        $cart->recordContentChange();
    }

    // ------------------------------------------------------ scenarios 26–30

    public function test_renaming_the_dish_does_not_rewrite_the_order(): void
    {
        $order = $this->placedOrder();
        $before = $this->readOrder($order);

        $this->item->forceFill(['name' => 'Paneer Tikka Supreme'])->save();

        $this->assertSame($before, $this->readOrder($order));
        $this->assertSame('Paneer Tikka', $before['items'][0]['name']);
    }

    public function test_repricing_the_dish_does_not_change_what_was_paid(): void
    {
        $order = $this->placedOrder();
        $paid = $order->refresh()->payable_total_minor;
        $before = $this->readOrder($order);

        // A steep rise, so a recomputed total could not coincidentally match.
        $this->item->forceFill(['base_price_minor' => 99_900])->save();
        $this->menu['large']->forceFill(['price_minor' => 99_900])->save();

        $after = $this->readOrder($order);

        $this->assertSame($before, $after);
        $this->assertSame((int) $paid, (int) $order->refresh()->payable_total_minor);
    }

    public function test_deleting_the_dish_leaves_the_order_complete(): void
    {
        $order = $this->placedOrder();
        $before = $this->readOrder($order);

        $this->item->delete();

        $after = $this->readOrder($order);

        $this->assertSame($before, $after);

        // The line survives with its name, and the foreign key is nulled rather
        // than the row cascading away with the dish. An order line is evidence
        // of a sale; a cart line is not, which is why only one of them is
        // allowed to vanish with the menu.
        $line = $order->items()->firstOrFail();
        $this->assertNull($line->menu_item_id);
        $this->assertSame('Paneer Tikka', $line->item_name_snapshot);
    }

    public function test_removing_the_variant_leaves_the_size_on_the_order(): void
    {
        $order = $this->placedOrder();
        $before = $this->readOrder($order);

        $this->menu['large']->delete();

        $this->assertSame($before, $this->readOrder($order));
        $this->assertSame('Large', $order->items()->firstOrFail()->variant_name_snapshot);
    }

    public function test_removing_a_modifier_option_leaves_it_on_the_order(): void
    {
        $order = $this->placedOrder();
        $before = $this->readOrder($order);

        MenuModifierOption::query()->whereKey($this->menu['cheese']->id)->delete();

        $after = $this->readOrder($order);

        $this->assertSame($before, $after);

        $names = $order->items()->firstOrFail()->modifiers->pluck('option_name_snapshot')->all();
        $this->assertContains('Extra Cheese', $names);
    }

    /**
     * Scenario 31 — a renamed restaurant, and the documented policy for it.
     */
    public function test_renaming_the_restaurant_leaves_the_order_snapshot_alone(): void
    {
        $order = $this->placedOrder();

        $this->assertSame('Highway Spice Kitchen', $order->refresh()->restaurant_name_snapshot);

        $this->restaurant->forceFill(['name' => 'Highway Spice Kitchen (Closed)'])->save();

        // The snapshot is what the customer was told at the moment they paid,
        // and it does not move. The live record is free to change; a support
        // conversation six months from now needs the name on the receipt.
        $this->assertSame('Highway Spice Kitchen', $order->refresh()->restaurant_name_snapshot);
    }

    // ------------------------------------------------------ scenario 15

    /**
     * A forced order-number collision, which cannot otherwise happen.
     *
     * The generator is handed a random source that returns the same draw every
     * time, so its first candidate is guaranteed to be one that already exists.
     * A generator without a retry would hand back the duplicate and the insert
     * would fail on the unique index — a customer whose money is captured and
     * whose order cannot be written.
     */
    public function test_an_order_number_collision_is_retried_rather_than_returned(): void
    {
        $order = $this->placedOrder()->refresh();
        $taken = (string) $order->order_number;

        $draws = 0;

        // Repeats the taken number's draw for the first ten characters, then
        // varies, so attempt one collides and attempt two cannot.
        $alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
        $suffix = substr($taken, -10);

        $generator = new OrderNumberGenerator(function (int $max) use (&$draws, $alphabet, $suffix): int {
            $index = $draws % 10;
            $draws++;

            return $draws <= 10
                ? (int) strpos($alphabet, $suffix[$index])
                : 1;
        });

        $minted = $generator->mint(CarbonImmutable::parse($order->placed_at));

        $this->assertNotSame($taken, $minted, 'The generator returned a number that is already taken.');
        $this->assertGreaterThan(10, $draws, 'The generator never made a second attempt, so no collision was exercised.');
    }

    // --- plumbing -------------------------------------------------------------

    /**
     * The order as the customer's app sees it, with volatile fields removed.
     *
     * Compared whole rather than field by field. A test that checks the name and
     * the price would not notice a modifier quietly disappearing, and the point
     * of a snapshot is that *nothing* moves.
     *
     * @return array<string, mixed>
     */
    private function readOrder(Order $order): array
    {
        $body = $this->as($this->rahul)
            ->getJson('/api/v1/customer/orders/'.$order->uuid)
            ->assertOk()
            ->json('data');

        // Server time, present on every response and different on every call.
        unset($body['as_of'], $body['server_time']);

        return $body;
    }

    private function as(User $customer): self
    {
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', 'Bearer '.CustomerFactory::tokenFor($customer));
    }

    private function placedOrder(): Order
    {
        $options = $this->as($this->rahul)
            ->postJson('/api/v1/customer/trips/'.$this->trip->uuid.'/cart/pickup-options')
            ->json('data.pickup');

        $this->as($this->rahul)->putJson(
            '/api/v1/customer/trips/'.$this->trip->uuid.'/cart/pickup-selection',
            ['pickup_option_id' => $options['recommended_option_id']],
        )->assertOk();

        $checkoutId = $this->as($this->rahul)
            ->postJson('/api/v1/customer/trips/'.$this->trip->uuid.'/checkout/prepare')
            ->json('data.checkout_id');

        $quote = CheckoutQuote::query()->where('uuid', $checkoutId)->firstOrFail();

        $uuid = $this->as($this->rahul)->postJson(
            '/api/v1/customer/trips/'.$this->trip->uuid.'/checkout/'.$quote->uuid.'/order',
        )->assertCreated()->json('data.id');

        $order = Order::query()->where('uuid', $uuid)->firstOrFail();

        $providerOrderId = $this->as($this->rahul)
            ->postJson('/api/v1/customer/orders/'.$order->uuid.'/payment-intent')
            ->assertOk()
            ->json('data.payment.provider_order_id');

        $this->gateway->stubPayment('pay_ok', $providerOrderId, (int) $order->payable_total_minor);

        $this->as($this->rahul)->postJson(
            '/api/v1/customer/orders/'.$order->uuid.'/payment/verify',
            [
                'provider_order_id' => $providerOrderId,
                'provider_payment_id' => 'pay_ok',
                'signature' => RazorpaySignature::compute($providerOrderId.'|pay_ok', self::KEY_SECRET),
            ],
        )->assertOk();

        return $order;
    }
}
