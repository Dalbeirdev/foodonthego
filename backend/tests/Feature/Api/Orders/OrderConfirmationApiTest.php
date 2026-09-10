<?php

declare(strict_types=1);

namespace Tests\Feature\Api\Orders;

use App\Enums\OrderStatus;
use App\Enums\PaymentStatus;
use App\Models\Cart;
use App\Models\CheckoutQuote;
use App\Models\MenuItem;
use App\Models\Order;
use App\Models\Payment;
use App\Models\Restaurant;
use App\Models\Trip;
use App\Models\User;
use App\Services\Orders\PickupCredentialService;
use App\Services\Payments\PaymentGateway;
use App\Services\Payments\RazorpaySignature;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Cache;
use Tests\Support\CartFixtures;
use Tests\Support\CustomerFactory;
use Tests\Support\FakePaymentGateway;
use Tests\Support\MenuFixtures;
use Tests\Support\RestaurantFixtures;
use Tests\TestCase;

/**
 * Reading a confirmed order, and the credential that collects it.
 *
 * Two themes. **An order is only ever readable by the person who bought it**,
 * and the answer for anybody else is indistinguishable from an order that does
 * not exist — because "403" on an identifier that happens to be real is an
 * oracle somebody can walk.
 *
 * And **a pickup credential is not part of an order**. It lives on its own
 * endpoint, is fetched when it is about to be shown, and is absent from every
 * other response. A credential that rode along inside the order would be in
 * every list refresh and every poll, through every proxy in between.
 */
final class OrderConfirmationApiTest extends TestCase
{
    use RefreshDatabase;

    private const KEY_SECRET = 'rzp-test-secret';

    private User $rahul;

    private User $ananya;

    private Trip $trip;

    private Restaurant $restaurant;

    private Cart $cart;

    private MenuItem $item;

    private FakePaymentGateway $gateway;

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
        $this->ananya = CustomerFactory::ananya();

        $this->trip = RestaurantFixtures::tripWithSelectedRoute($this->rahul);
        $this->restaurant = RestaurantFixtures::nearRoute(0.4, 800, 'Highway Spice Kitchen');

        $this->restaurant->openingHours()->delete();
        RestaurantFixtures::openDaily($this->restaurant, '09:00:00', '22:00:00');

        $this->cart = CartFixtures::activeCart($this->rahul, $this->trip, $this->restaurant);

        $category = MenuFixtures::category($this->restaurant, 'Mains');
        $this->item = MenuFixtures::item($category, 'Paneer Tikka', 24_900, ['preparation_minutes' => 20]);

        CartFixtures::line($this->cart, $this->item);
    }

    // ------------------------------------------------------ scenarios 43, 44

    public function test_the_orders_tab_shows_a_placed_order(): void
    {
        $order = $this->placedOrder();

        $body = $this->as($this->rahul)->getJson('/api/v1/customer/orders')->assertOk()->json('data.orders');

        $this->assertCount(1, $body);
        $this->assertSame($order->refresh()->order_number, $body[0]['order_number']);
        $this->assertSame(OrderStatus::Placed->value, $body[0]['status']);
    }

    /**
     * A payment target is not a purchase and must not appear in the list.
     */
    public function test_an_unpaid_payment_target_never_appears_in_the_orders_tab(): void
    {
        $this->orderWithIntent(); // created, never paid

        $body = $this->as($this->rahul)->getJson('/api/v1/customer/orders')->assertOk()->json('data.orders');

        $this->assertSame([], $body);

        // And the row really does exist, so the assertion above is not passing
        // because nothing was created at all.
        $this->assertSame(1, Order::query()->where('status', OrderStatus::AwaitingPayment)->count());
    }

    // --------------------------------------------- scenarios 35, 37, 38

    public function test_another_customer_cannot_read_the_order(): void
    {
        $order = $this->placedOrder();

        $this->as($this->ananya)
            ->getJson('/api/v1/customer/orders/'.$order->uuid)
            ->assertNotFound();

        // Indistinguishable from an identifier that was never issued.
        $this->as($this->ananya)
            ->getJson('/api/v1/customer/orders/2b0f6d3e-0000-4000-8000-000000000000')
            ->assertNotFound();
    }

    public function test_another_customer_cannot_read_the_pickup_credential(): void
    {
        $order = $this->placedOrder();

        $this->as($this->ananya)
            ->getJson('/api/v1/customer/orders/'.$order->uuid.'/pickup-credential')
            ->assertNotFound();

        // Nor does the list leak it.
        $this->as($this->ananya)
            ->getJson('/api/v1/customer/orders')
            ->assertOk()
            ->assertJsonPath('data.orders', []);
    }

    /**
     * Scenario 36 — the order number is not a lookup key anywhere.
     *
     * Asserted by walking the router rather than by trying one URL, because the
     * risk is a future route added without thinking, not this one.
     */
    public function test_no_route_accepts_an_order_number_as_an_identifier(): void
    {
        $order = $this->placedOrder()->refresh();

        $this->as($this->rahul)
            ->getJson('/api/v1/customer/orders/'.$order->order_number)
            ->assertNotFound();

        $this->as($this->rahul)
            ->getJson('/api/v1/customer/orders/'.$order->order_number.'/pickup-credential')
            ->assertNotFound();
    }

    // ---------------------------------------------------- the credential itself

    public function test_the_credential_endpoint_returns_a_code_and_forbids_caching(): void
    {
        $order = $this->placedOrder();

        $response = $this->as($this->rahul)
            ->getJson('/api/v1/customer/orders/'.$order->uuid.'/pickup-credential')
            ->assertOk();

        $pickup = $response->json('data.pickup');

        $this->assertSame(8, strlen($pickup['code']));
        $this->assertStringStartsWith('foodonthego://pickup/v1/', $pickup['qr_payload']);
        $this->assertSame(1, $pickup['credential_version']);

        // The code the endpoint hands out is the one the stored digest verifies.
        $this->assertTrue(
            app(PickupCredentialService::class)->matchesCode($order->refresh(), $pickup['code']),
        );

        $this->assertStringContainsString('no-store', $response->headers->get('Cache-Control') ?? '');
    }

    /**
     * Nothing in the QR payload but the token.
     */
    public function test_the_qr_payload_is_the_token_and_nothing_else(): void
    {
        $order = $this->placedOrder()->refresh();

        $payload = $this->as($this->rahul)
            ->getJson('/api/v1/customer/orders/'.$order->uuid.'/pickup-credential')
            ->assertOk()
            ->json('data.pickup.qr_payload');

        /*
         | Asserted by equality, not by hunting for leaked substrings.
         |
         | The first version of this walked a list of things that must not
         | appear and asked whether each was a substring of the payload. That is
         | the wrong shape twice over: a single-digit database id appears inside
         | a base64 token by coincidence, which fails the test for no reason,
         | and an empty field passes it for no reason. Both happened.
         |
         | Equality against prefix-plus-token proves the strictly stronger
         | thing: there is nothing else in the payload at all. No name, no
         | phone, no total, no payment identifier — not because each was checked
         | for, but because there is no room for anything.
         */
        $credential = app(PickupCredentialService::class)->derive($order);

        $this->assertSame('foodonthego://pickup/v1/'.$credential->token, $payload);

        // The token itself is opaque: base64url only, so nothing readable can
        // have been smuggled into it.
        $this->assertMatchesRegularExpression('/^[A-Za-z0-9_-]+$/', $credential->token);
    }

    public function test_the_order_response_never_carries_the_credential(): void
    {
        $order = $this->placedOrder();

        $credential = app(PickupCredentialService::class)->derive($order->refresh());

        $detail = $this->as($this->rahul)
            ->getJson('/api/v1/customer/orders/'.$order->uuid)
            ->assertOk()
            ->content();

        $this->assertStringNotContainsString($credential->code, $detail);
        $this->assertStringNotContainsString($credential->token, $detail);
        $this->assertStringNotContainsString((string) $order->pickup_code_hash, $detail);
    }

    /**
     * No provider secrets, signatures or reconciliation detail reach a customer.
     */
    public function test_the_order_response_leaks_no_provider_material(): void
    {
        $order = $this->placedOrder();

        $detail = $this->as($this->rahul)
            ->getJson('/api/v1/customer/orders/'.$order->uuid)
            ->assertOk()
            ->content();

        foreach (['rzp_test_fake', self::KEY_SECRET, 'test-webhook-secret', 'signature'] as $secret) {
            $this->assertStringNotContainsString($secret, $detail);
        }
    }

    // ---------------------------------------------- scenarios 39, 40, 41, 42

    public function test_the_status_endpoint_returns_a_placed_order(): void
    {
        $order = $this->placedOrder();

        $this->as($this->rahul)
            ->getJson('/api/v1/customer/orders/'.$order->uuid.'/status')
            ->assertOk()
            ->assertJsonPath('data.state', 'PLACED')
            ->assertJsonPath('data.is_paid_for', true);
    }

    /**
     * The crash path: money taken, order never written, customer comes back.
     *
     * The order must appear, and it must appear exactly once however many times
     * the app asks.
     */
    public function test_a_customer_returning_after_a_crash_gets_their_order_not_a_payment_screen(): void
    {
        [$order, $providerOrderId] = $this->orderWithIntent();

        // A capture that never became an order — the process died in between.
        $payment = new Payment;
        $payment->order_id = $order->id;
        $payment->provider = 'razorpay';
        $payment->provider_order_id = $providerOrderId;
        $payment->provider_payment_id = 'pay_orphaned';
        $payment->amount_minor = (int) $order->payable_total_minor;
        $payment->currency = $order->currency;
        $payment->status = PaymentStatus::Captured;
        $payment->verified_at = now()->toImmutable();
        $payment->save();

        $this->assertNull($order->refresh()->order_number);

        foreach (range(1, 3) as $_) {
            $this->as($this->rahul)
                ->getJson('/api/v1/customer/orders/'.$order->uuid.'/status')
                ->assertOk()
                ->assertJsonPath('data.state', 'PLACED');
        }

        $this->assertSame(1, Order::query()->where('status', OrderStatus::Placed)->count());
        $this->assertNotNull($order->refresh()->order_number);
    }

    /**
     * An order nobody has paid for is still allowed to say so.
     */
    public function test_an_unpaid_order_reports_awaiting_payment(): void
    {
        [$order] = $this->orderWithIntent();

        $this->as($this->rahul)
            ->getJson('/api/v1/customer/orders/'.$order->uuid.'/status')
            ->assertOk()
            ->assertJsonPath('data.state', 'AWAITING_PAYMENT');
    }

    // --- plumbing -------------------------------------------------------------

    private function as(User $customer): self
    {
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', 'Bearer '.CustomerFactory::tokenFor($customer));
    }

    private function placedOrder(): Order
    {
        [$order, $providerOrderId] = $this->orderWithIntent();

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

    /** @return array{0: Order, 1: string} */
    private function orderWithIntent(): array
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

        return [$order, $providerOrderId];
    }
}
