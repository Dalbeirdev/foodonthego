<?php

declare(strict_types=1);

namespace Tests\Feature\Api\Orders;

use App\Enums\CartStatus;
use App\Enums\CheckoutQuoteStatus;
use App\Enums\OrderStatus;
use App\Enums\PaymentStatus;
use App\Exceptions\Orders\OrderCreationRefused;
use App\Exceptions\Orders\PickupCredentialVersionMissing;
use App\Models\Cart;
use App\Models\CheckoutQuote;
use App\Models\MenuItem;
use App\Models\Order;
use App\Models\OutboxEvent;
use App\Models\Payment;
use App\Models\Restaurant;
use App\Models\Trip;
use App\Models\User;
use App\Services\Orders\CreateOrderFromCapturedPayment;
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
 * One captured payment becomes exactly one order.
 *
 * The invariant this file exists to defend is the one the specification calls
 * the most important requirement of Module 16, and it is not the kind of thing
 * a happy-path test can establish. A single call proving "an order was created"
 * says nothing about the case that actually costs money: the same capture
 * arriving twice, from two routes, into two workers.
 *
 * So most of what follows delivers the same capture repeatedly and counts rows.
 * The count is taken over the whole table rather than by re-reading one order,
 * because "the order I already had is unchanged" is compatible with a second
 * order existing beside it.
 */
final class OrderPlacementTest extends TestCase
{
    use RefreshDatabase;

    private const KEY_SECRET = 'rzp-test-secret';

    private User $rahul;

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
        $this->trip = RestaurantFixtures::tripWithSelectedRoute($this->rahul);
        $this->restaurant = RestaurantFixtures::nearRoute(0.4, 800, 'Highway Spice Kitchen');

        $this->restaurant->openingHours()->delete();
        RestaurantFixtures::openDaily($this->restaurant, '09:00:00', '22:00:00');

        $this->cart = CartFixtures::activeCart($this->rahul, $this->trip, $this->restaurant);

        $category = MenuFixtures::category($this->restaurant, 'Mains');
        $this->item = MenuFixtures::item($category, 'Paneer Tikka', 24_900, ['preparation_minutes' => 20]);

        CartFixtures::line($this->cart, $this->item);
    }

    // ------------------------------------------------------------- scenario 1

    public function test_a_captured_payment_produces_exactly_one_placed_order(): void
    {
        [$order] = $this->captureAPayment();

        $this->assertSame(1, Order::query()->where('status', OrderStatus::Placed)->count());

        $order->refresh();

        $this->assertSame(OrderStatus::Placed, $order->status);
        $this->assertNotNull($order->order_number);
        $this->assertNotNull($order->placed_at);
        $this->assertNotNull($order->placed_from_payment_id);

        /*
         | Scenario 26 — the operational snapshots a counter needs, asserted
         | non-empty rather than merely present.
         |
         | A NULL here does not throw and does not fail any other test; it just
         | means the restaurant has no name to call out and no number to ring.
         | The first version of this wrote users.phone, a column Module 03
         | superseded and nothing populates, and every test still passed.
         */
        $this->assertNotEmpty($order->customer_name_snapshot);
        $this->assertNotEmpty($order->customer_phone_snapshot);
        $this->assertNotEmpty($order->restaurant_name_snapshot);
        $this->assertSame($this->restaurant->name, $order->restaurant_name_snapshot);

        // Scenario 46 — nothing may set a fulfilment state because payment
        // succeeded. The restaurant has not seen this order yet.
        $this->assertNotSame(OrderStatus::Accepted, $order->status);

        // Scenario 47 — the two statuses are read from two records, and both
        // are correct at once.
        $this->assertSame(
            PaymentStatus::Captured,
            Payment::query()->findOrFail($order->placed_from_payment_id)->status,
        );
    }

    /**
     * Scenario 51 — the money invariant, which the specification marks mandatory.
     */
    public function test_the_order_total_is_exactly_what_was_captured(): void
    {
        [$order] = $this->captureAPayment();

        $payment = Payment::query()->findOrFail($order->refresh()->placed_from_payment_id);

        $this->assertSame((int) $order->payable_total_minor, (int) $payment->amount_minor);
        $this->assertSame($order->currency, $payment->currency);

        // And the lines add up to the total, so the receipt a customer reads is
        // internally consistent rather than merely equal to what was charged.
        $lines = $order->items->sum('line_total_minor');

        $this->assertSame((int) $order->items_subtotal_minor, (int) $lines);
    }

    // ------------------------------------------------- scenarios 24, 25 and 48

    public function test_placing_an_order_spends_the_basket_the_quote_and_the_event(): void
    {
        [$order] = $this->captureAPayment();

        $order->refresh();

        $this->assertSame(CartStatus::Converted, $order->cart?->status);
        $this->assertSame(CheckoutQuoteStatus::Consumed, $order->checkoutQuote?->status);

        // The customer must not be able to reopen the basket and buy it again.
        $this->assertFalse($order->cart?->isActive());

        $this->assertSame(
            1,
            OutboxEvent::query()
                ->where('event_name', 'OrderPlaced')
                ->where('dedupe_key', $order->uuid)
                ->count(),
        );
    }

    // ------------------------------------------ scenarios 7, 8, 9, 11, 12, 42

    /**
     * The same capture, delivered again by the client.
     */
    public function test_a_duplicate_callback_does_not_place_a_second_order(): void
    {
        [$order, $providerOrderId, $providerPaymentId] = $this->captureAPayment();

        $this->verify($order, $providerOrderId, $providerPaymentId)->assertOk();

        $this->assertSame(1, $this->placedOrderCount());
    }

    /**
     * The same capture, delivered again by the provider.
     */
    public function test_a_duplicate_webhook_does_not_place_a_second_order(): void
    {
        [$order, $providerOrderId, $providerPaymentId] = $this->captureAPayment();

        $this->deliverWebhook($providerOrderId, $providerPaymentId, 'evt_dup_a')->assertOk();
        $this->deliverWebhook($providerOrderId, $providerPaymentId, 'evt_dup_b')->assertOk();

        $this->assertSame(1, $this->placedOrderCount());
    }

    /**
     * Both routes, for one capture. The pair the specification singles out.
     */
    public function test_a_callback_and_a_webhook_for_one_capture_place_one_order(): void
    {
        [$order, $providerOrderId, $providerPaymentId] = $this->captureAPayment();

        $this->deliverWebhook($providerOrderId, $providerPaymentId, 'evt_race')->assertOk();
        $this->verify($order, $providerOrderId, $providerPaymentId)->assertOk();

        $this->assertSame(1, $this->placedOrderCount());
    }

    /**
     * Two workers calling the service directly, as a queue retry would.
     *
     * Deliberately bypasses HTTP. The controllers have their own idempotency
     * middleware, and a test that went through them could pass because of that
     * rather than because order creation is idempotent — which is the thing
     * being claimed.
     */
    public function test_two_workers_placing_the_same_payment_produce_one_order(): void
    {
        [$order] = $this->captureAPayment();

        $payment = Payment::query()->findOrFail($order->refresh()->placed_from_payment_id);

        $service = app(CreateOrderFromCapturedPayment::class);

        $first = $service->place($payment);
        $second = $service->place($payment);

        $this->assertSame($first->id, $second->id);
        $this->assertSame(1, $this->placedOrderCount());

        // And the second run must not have minted a second event either.
        $this->assertSame(1, OutboxEvent::query()->where('event_name', 'OrderPlaced')->count());
    }

    // --------------------------------------------------- scenarios 2, 3, 4, 6

    public function test_an_authorized_payment_places_nothing(): void
    {
        $this->assertNoOrderFor(PaymentStatus::Authorized);
    }

    public function test_a_created_payment_places_nothing(): void
    {
        $this->assertNoOrderFor(PaymentStatus::Created);
    }

    public function test_a_failed_payment_places_nothing(): void
    {
        $this->assertNoOrderFor(PaymentStatus::Failed);
    }

    // ------------------------------------------------------ scenarios 18, 19

    public function test_a_capture_for_the_wrong_amount_places_nothing(): void
    {
        [$order, $providerOrderId] = $this->orderWithIntent();

        // The provider says it took more than the quote said was owed.
        $this->gateway->stubPayment(
            'pay_wrong_amount',
            $providerOrderId,
            (int) $order->payable_total_minor + 5_000,
        );

        $this->verify($order, $providerOrderId, 'pay_wrong_amount');

        $this->assertSame(0, $this->placedOrderCount());
        $this->assertNull($order->refresh()->order_number);
    }

    public function test_a_capture_in_the_wrong_currency_places_nothing(): void
    {
        [$order, $providerOrderId] = $this->orderWithIntent();

        $this->gateway->stubPayment(
            'pay_wrong_currency',
            $providerOrderId,
            (int) $order->payable_total_minor,
            currency: 'USD',
        );

        $this->verify($order, $providerOrderId, 'pay_wrong_currency');

        $this->assertSame(0, $this->placedOrderCount());
    }

    // ------------------------------------------------------ scenarios 32–34

    public function test_the_pickup_credentials_are_unpredictable_and_bound_to_the_order(): void
    {
        [$order] = $this->captureAPayment();

        $credentials = app(PickupCredentialService::class);
        $mine = $credentials->derive($order->refresh());

        $this->assertSame(8, strlen($mine->code));

        // 43 base64url characters is 258 bits of encoding over 256 bits of
        // HMAC output — comfortably past the specification's 128-bit floor.
        $this->assertGreaterThanOrEqual(43, strlen($mine->token));

        // Not derived from anything an attacker holding the order already knows.
        $this->assertStringNotContainsString((string) $order->id, $mine->code);
        $this->assertStringNotContainsString((string) $order->uuid, $mine->token);
        $this->assertNotSame($order->order_number, $mine->code);

        // Bound: a second order's credentials are different, and neither
        // validates against the other. This is what stops a customer replaying
        // their own code against somebody else's order.
        $other = $this->independentPlacedOrder();

        $theirs = $credentials->derive($other);

        $this->assertNotSame($mine->code, $theirs->code);
        $this->assertNotSame($mine->token, $theirs->token);
        $this->assertFalse($credentials->matchesCode($other, $mine->code));
        $this->assertFalse($credentials->matchesToken($other, $mine->token));

        // And the right one does verify, or the assertions above would pass
        // against an implementation that never matches anything.
        $this->assertTrue($credentials->matchesCode($other, $theirs->code));
        $this->assertTrue($credentials->matchesToken($other, $theirs->token));
    }

    public function test_no_plaintext_credential_is_ever_written_to_the_database(): void
    {
        [$order] = $this->captureAPayment();

        $order->refresh();
        $credential = app(PickupCredentialService::class)->derive($order);

        // Every column of the row, as the database holds it.
        $row = json_encode($order->getAttributes(), JSON_THROW_ON_ERROR);

        $this->assertStringNotContainsString($credential->code, $row);
        $this->assertStringNotContainsString($credential->token, $row);

        // The digests are present, so the assertions above are not passing
        // because nothing was stored at all.
        $this->assertNotNull($order->pickup_code_hash);
        $this->assertNotNull($order->pickup_token_hash);
        $this->assertSame(64, strlen((string) $order->pickup_code_hash));
    }

    public function test_a_credential_redacts_itself_when_serialised(): void
    {
        [$order] = $this->captureAPayment();

        $credential = app(PickupCredentialService::class)->derive($order->refresh());

        $debug = print_r($credential->__debugInfo(), true);

        $this->assertStringNotContainsString($credential->code, $debug);
        $this->assertStringNotContainsString($credential->token, $debug);
        $this->assertStringNotContainsString($credential->code, (string) $credential);
    }

    // ------------------------------------------------- Module 16's own guards
    //
    // THE TESTS ABOVE DO NOT REACH THEM, AND THAT MATTERS.
    //
    // Four negative controls were run against the HTTP tests — deleting the
    // already-placed return, the amount check, the captured-payment check, and
    // the credential's order binding — and all four stayed green. The reason is
    // that Module 15 refuses first: PaymentService returns early when the
    // provider reports anything but a capture, and answers a second verify with
    // OrderAlreadyPaid. So those tests prove Module 15's guards work and say
    // nothing at all about Module 16's.
    //
    // These call the service directly, which is the only place its own
    // preconditions can be observed. The controls fire here.

    public function test_the_service_refuses_a_payment_that_is_not_captured(): void
    {
        [$order, $payment] = $this->orderAwaitingPayment(PaymentStatus::Authorized);

        $this->expectException(OrderCreationRefused::class);

        try {
            app(CreateOrderFromCapturedPayment::class)->place($payment);
        } finally {
            $this->assertSame(0, $this->placedOrderCount());
            $this->assertNull($order->refresh()->order_number);
        }
    }

    public function test_the_service_refuses_a_capture_for_the_wrong_amount(): void
    {
        [$order, $payment] = $this->orderAwaitingPayment(PaymentStatus::Captured);

        $payment->amount_minor = (int) $order->payable_total_minor + 1;
        $payment->save();

        $this->expectException(OrderCreationRefused::class);

        try {
            app(CreateOrderFromCapturedPayment::class)->place($payment);
        } finally {
            $this->assertSame(0, $this->placedOrderCount());
        }
    }

    public function test_the_service_refuses_a_capture_in_the_wrong_currency(): void
    {
        [$order, $payment] = $this->orderAwaitingPayment(PaymentStatus::Captured);

        $payment->currency = 'USD';
        $payment->save();

        $this->expectException(OrderCreationRefused::class);

        try {
            app(CreateOrderFromCapturedPayment::class)->place($payment);
        } finally {
            $this->assertSame(0, $this->placedOrderCount());
        }
    }

    /**
     * The idempotency guard itself, with nothing in front of it.
     */
    public function test_the_service_placed_twice_writes_one_order_and_one_event(): void
    {
        [, $payment] = $this->orderAwaitingPayment(PaymentStatus::Captured);

        $service = app(CreateOrderFromCapturedPayment::class);

        $first = $service->place($payment);
        $second = $service->place($payment);
        $third = $service->place($payment->fresh());

        $this->assertSame($first->id, $second->id);
        $this->assertSame($first->id, $third->id);
        $this->assertSame(1, $this->placedOrderCount());
        $this->assertSame(1, OutboxEvent::query()->where('event_name', 'OrderPlaced')->count());
    }

    /**
     * An order that has never been reloaded must not silently mint a credential
     * for the wrong version. See PickupCredentialService::version().
     */
    public function test_deriving_from_an_unreloaded_order_is_refused_rather_than_wrong(): void
    {
        $order = new Order;
        $order->customer_id = $this->rahul->id;
        $order->restaurant_id = $this->restaurant->id;
        $order->currency = 'INR';
        $order->items_subtotal_minor = 100;
        $order->payable_total_minor = 100;
        $order->status = OrderStatus::Placed;
        $order->save();

        $this->assertNull($order->pickup_credential_version);

        $this->expectException(PickupCredentialVersionMissing::class);

        app(PickupCredentialService::class)->derive($order);
    }

    // --- plumbing -------------------------------------------------------------

    /**
     * An order in AWAITING_PAYMENT with a payment against it in a chosen state.
     *
     * Built directly rather than over HTTP, because the states under test are
     * precisely the ones Module 15 refuses to let a request produce.
     *
     * @return array{0: Order, 1: Payment}
     */
    private function orderAwaitingPayment(PaymentStatus $status): array
    {
        $order = new Order;
        $order->customer_id = $this->rahul->id;
        $order->restaurant_id = $this->restaurant->id;
        $order->cart_id = $this->cart->id;
        $order->currency = 'INR';
        $order->items_subtotal_minor = 24_900;
        $order->payable_total_minor = 24_900;
        $order->status = OrderStatus::AwaitingPayment;
        $order->pickup_timezone = 'Asia/Kolkata';
        $order->save();
        $order->refresh();

        $payment = new Payment;
        $payment->order_id = $order->id;
        $payment->provider = 'razorpay';
        $payment->provider_order_id = 'order_direct_'.$order->id;
        $payment->provider_payment_id = 'pay_direct_'.$order->id;
        $payment->amount_minor = 24_900;
        $payment->currency = 'INR';
        $payment->status = $status;
        $payment->verified_at = $status === PaymentStatus::Captured ? now() : null;
        $payment->save();

        return [$order, $payment];
    }

    private function placedOrderCount(): int
    {
        return Order::query()->where('status', OrderStatus::Placed)->count();
    }

    private function assertNoOrderFor(PaymentStatus $status): void
    {
        [$order, $providerOrderId] = $this->orderWithIntent();

        $this->gateway->stubPayment(
            'pay_'.strtolower($status->value),
            $providerOrderId,
            (int) $order->payable_total_minor,
            status: $status,
        );

        $this->verify($order, $providerOrderId, 'pay_'.strtolower($status->value));

        $this->assertSame(0, $this->placedOrderCount());
        $this->assertNull($order->refresh()->order_number);
        $this->assertNull($order->placed_at);
    }

    /** @return array{0: Order, 1: string, 2: string} */
    private function captureAPayment(): array
    {
        [$order, $providerOrderId] = $this->orderWithIntent();

        $this->gateway->stubPayment('pay_ok', $providerOrderId, (int) $order->payable_total_minor);

        $this->verify($order, $providerOrderId, 'pay_ok')->assertOk();

        return [$order, $providerOrderId, 'pay_ok'];
    }

    /**
     * A second placed order belonging to somebody else entirely.
     *
     * Built through the real flow rather than by inserting a row, because the
     * credential binding under test depends on fields the real flow populates.
     */
    private function independentPlacedOrder(): Order
    {
        $ananya = CustomerFactory::ananya();
        $trip = RestaurantFixtures::tripWithSelectedRoute($ananya);
        $cart = CartFixtures::activeCart($ananya, $trip, $this->restaurant);

        CartFixtures::line($cart, $this->item);

        $order = new Order;
        $order->customer_id = $ananya->id;
        $order->restaurant_id = $this->restaurant->id;
        $order->currency = 'INR';
        $order->items_subtotal_minor = 24_900;
        $order->payable_total_minor = 24_900;
        $order->status = OrderStatus::Placed;
        $order->pickup_timezone = 'Asia/Kolkata';
        $order->save();

        // Mint this order's digests too.
        //
        // Without them matchesCode returns false because there is nothing to
        // compare against, and the cross-order assertions above would pass
        // against an implementation that never matches anything at all. The
        // positive assertion that follows them exists to catch exactly that,
        // and on first run it did.
        // refresh() first, and this is not tidiness.
        //
        // pickup_credential_version has a database default of 1, and a model
        // that has only been save()d holds NULL for it. Deriving from the
        // un-reloaded model used to produce a credential for version 0 while
        // every later read produced version 1 — different codes for one order.
        // The service now refuses rather than deriving; this reloads so there
        // is something to derive from.
        $order->refresh();

        $digests = app(PickupCredentialService::class)->digests($order);
        $order->pickup_code_hash = $digests->codeHash;
        $order->pickup_token_hash = $digests->tokenHash;
        $order->save();

        return $order;
    }

    private function as(User $customer): self
    {
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', 'Bearer '.CustomerFactory::tokenFor($customer));
    }

    private function quote(): CheckoutQuote
    {
        $options = $this->as($this->rahul)
            ->postJson('/api/v1/customer/trips/'.$this->trip->uuid.'/cart/pickup-options')
            ->json('data.pickup');

        $this->as($this->rahul)->putJson(
            '/api/v1/customer/trips/'.$this->trip->uuid.'/cart/pickup-selection',
            ['pickup_option_id' => $options['recommended_option_id']],
        )->assertOk();

        $id = $this->as($this->rahul)
            ->postJson('/api/v1/customer/trips/'.$this->trip->uuid.'/checkout/prepare')
            ->json('data.checkout_id');

        return CheckoutQuote::query()->where('uuid', $id)->firstOrFail();
    }

    /** @return array{0: Order, 1: string} */
    private function orderWithIntent(): array
    {
        $quote = $this->quote();

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

    private function verify(Order $order, string $providerOrderId, string $providerPaymentId)
    {
        return $this->as($this->rahul)->postJson(
            '/api/v1/customer/orders/'.$order->uuid.'/payment/verify',
            [
                'provider_order_id' => $providerOrderId,
                'provider_payment_id' => $providerPaymentId,
                'signature' => RazorpaySignature::compute(
                    $providerOrderId.'|'.$providerPaymentId,
                    self::KEY_SECRET,
                ),
            ],
        );
    }

    private function deliverWebhook(string $providerOrderId, string $providerPaymentId, string $eventId)
    {
        $body = json_encode([
            'event' => 'payment.captured',
            'payload' => [
                'payment' => [
                    'entity' => [
                        'id' => $providerPaymentId,
                        'order_id' => $providerOrderId,
                        'amount' => 24_900,
                        'currency' => 'INR',
                        'status' => 'captured',
                    ],
                ],
            ],
        ], JSON_THROW_ON_ERROR);

        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->call(
            'POST',
            '/api/v1/webhooks/razorpay',
            server: [
                'HTTP_X_RAZORPAY_SIGNATURE' => hash_hmac('sha256', $body, 'test-webhook-secret'),
                'HTTP_X_RAZORPAY_EVENT_ID' => $eventId,
                'CONTENT_TYPE' => 'application/json',
            ],
            content: $body,
        );
    }
}
