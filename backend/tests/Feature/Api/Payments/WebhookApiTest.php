<?php

declare(strict_types=1);

namespace Tests\Feature\Api\Payments;

use App\Enums\ApiErrorCode;
use App\Enums\OrderStatus;
use App\Enums\PaymentEventOutcome;
use App\Enums\PaymentStatus;
use App\Models\Cart;
use App\Models\CheckoutQuote;
use App\Models\MenuItem;
use App\Models\Order;
use App\Models\Payment;
use App\Models\PaymentEvent;
use App\Models\Restaurant;
use App\Models\Trip;
use App\Models\User;
use App\Services\Payments\PaymentGateway;
use App\Services\Payments\RazorpaySignature;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Cache;
use Illuminate\Testing\TestResponse;
use Tests\Support\CartFixtures;
use Tests\Support\CustomerFactory;
use Tests\Support\FakePaymentGateway;
use Tests\Support\MenuFixtures;
use Tests\Support\RestaurantFixtures;
use Tests\TestCase;

/**
 * The one endpoint anybody on the internet can call.
 *
 * It is unauthenticated because the provider has no account here, so an HMAC
 * over the raw body stands in for authentication — and everything below tests
 * either that substitution or the idempotency that keeps a retrying provider
 * from being charged twice.
 *
 * The test worth reading first is
 * {@see test_a_forged_delivery_cannot_poison_the_idempotency_key()}. It is the
 * attack that makes "log rejected deliveries into the events table" a bad idea,
 * and it is not obvious until it is written down.
 */
final class WebhookApiTest extends TestCase
{
    use RefreshDatabase;

    private const KEY_SECRET = 'test-key-secret-not-a-real-one';

    private const WEBHOOK_SECRET = 'test-webhook-secret-not-a-real-one';

    private const URL = '/api/v1/webhooks/razorpay';

    private User $rahul;

    private Trip $trip;

    private Restaurant $restaurant;

    private Cart $cart;

    private MenuItem $item;

    private FakePaymentGateway $gateway;

    private Order $order;

    private string $providerOrderId;

    protected function setUp(): void
    {
        parent::setUp();

        Cache::flush();

        config([
            'services.razorpay.key_id' => 'rzp_test_fake',
            'services.razorpay.key_secret' => self::KEY_SECRET,
            'services.razorpay.webhook_secret' => self::WEBHOOK_SECRET,
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

        [$this->order, $this->providerOrderId] = $this->orderWithIntent();
    }

    // --- plumbing -------------------------------------------------------------

    private function as(User $customer): self
    {
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', 'Bearer '.CustomerFactory::tokenFor($customer));
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

        $orderUuid = $this->as($this->rahul)->postJson(
            '/api/v1/customer/trips/'.$this->trip->uuid.'/checkout/'.$quote->uuid.'/order',
        )->assertCreated()->json('data.id');

        $order = Order::query()->where('uuid', $orderUuid)->firstOrFail();

        $providerOrderId = $this->as($this->rahul)
            ->postJson('/api/v1/customer/orders/'.$order->uuid.'/payment-intent')
            ->assertOk()
            ->json('data.payment.provider_order_id');

        return [$order, $providerOrderId];
    }

    private function body(string $event, string $paymentId, ?string $providerOrderId = null, ?int $amountMinor = null): string
    {
        return json_encode([
            'event' => $event,
            'payload' => [
                'payment' => [
                    'entity' => [
                        'id' => $paymentId,
                        'order_id' => $providerOrderId ?? $this->providerOrderId,
                        'amount' => $amountMinor ?? $this->order->payable_total_minor,
                        'status' => $event === 'payment.failed' ? 'failed' : 'captured',
                    ],
                ],
            ],
        ], JSON_THROW_ON_ERROR);
    }

    /** Posts a raw body, the way the provider does. */
    private function deliver(string $rawBody, ?string $signature = null, string $eventId = 'evt_default'): TestResponse
    {
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->call(
            'POST',
            self::URL,
            [],
            [],
            [],
            [
                'CONTENT_TYPE' => 'application/json',
                'HTTP_X_RAZORPAY_SIGNATURE' => $signature ?? RazorpaySignature::compute($rawBody, self::WEBHOOK_SECRET),
                'HTTP_X_RAZORPAY_EVENT_ID' => $eventId,
            ],
            $rawBody,
        );
    }

    // --- the happy path -------------------------------------------------------

    public function test_a_signed_capture_settles_the_order(): void
    {
        $this->gateway->stubPayment('pay_hook', $this->providerOrderId, $this->order->payable_total_minor);

        $this->deliver($this->body('payment.captured', 'pay_hook'), eventId: 'evt_1')
            ->assertOk()
            ->assertJsonPath('data.outcome', PaymentEventOutcome::Applied->value);

        $this->order->refresh();

        $this->assertSame(OrderStatus::Placed, $this->order->status);
        $this->assertNotNull($this->order->paid_at);
    }

    /**
     * The webhook exists for the case where the app never came back.
     *
     * No client callback happens anywhere in this test; the order is settled
     * entirely by the provider talking to the server.
     */
    public function test_the_webhook_settles_an_order_the_app_never_reported(): void
    {
        $this->gateway->stubPayment('pay_hook', $this->providerOrderId, $this->order->payable_total_minor);

        $this->assertSame(OrderStatus::AwaitingPayment, $this->order->status);

        $this->deliver($this->body('payment.captured', 'pay_hook'), eventId: 'evt_only')->assertOk();

        $this->assertSame(OrderStatus::Placed, $this->order->fresh()->status);
    }

    // --- the signature --------------------------------------------------------

    public function test_an_unsigned_delivery_is_refused_and_changes_nothing(): void
    {
        $this->gateway->stubPayment('pay_hook', $this->providerOrderId, $this->order->payable_total_minor);

        $this->deliver($this->body('payment.captured', 'pay_hook'), signature: '')
            ->assertStatus(400)
            ->assertJsonPath('error.code', ApiErrorCode::WebhookSignatureInvalid->value);

        $this->assertSame(OrderStatus::AwaitingPayment, $this->order->fresh()->status);
        $this->assertSame(0, PaymentEvent::query()->count());
    }

    public function test_a_forged_signature_is_refused_and_changes_nothing(): void
    {
        $this->gateway->stubPayment('pay_hook', $this->providerOrderId, $this->order->payable_total_minor);

        $this->deliver($this->body('payment.captured', 'pay_hook'), signature: str_repeat('f', 64))
            ->assertStatus(400);

        $this->assertSame(OrderStatus::AwaitingPayment, $this->order->fresh()->status);
        $this->assertSame(0, PaymentEvent::query()->count());
    }

    /**
     * A signature made with the API secret rather than the webhook secret.
     *
     * Razorpay signs the two messages with two different keys, and a deployment
     * that reused one for both would verify nothing while appearing to work.
     * This is the test that catches that configuration mistake.
     */
    public function test_a_signature_made_with_the_api_secret_is_refused(): void
    {
        $raw = $this->body('payment.captured', 'pay_hook');

        $this->deliver($raw, signature: RazorpaySignature::compute($raw, self::KEY_SECRET))
            ->assertStatus(400);

        $this->assertSame(OrderStatus::AwaitingPayment, $this->order->fresh()->status);
    }

    /**
     * **The attack that shaped the schema.**
     *
     * The endpoint is public, so anybody may post to it. Suppose rejected
     * deliveries were recorded in `payment_events` with the event id they
     * claimed — a natural thing to want, since a run of rejections is worth
     * seeing. An attacker who could guess or learn the event id of a payment
     * about to happen could post a forged body carrying that id. It would be
     * rejected, but the row would exist; and when the genuine delivery arrived,
     * the unique index would treat it as a duplicate and discard it.
     *
     * The result is an order that was paid for and stays unpaid, achieved by
     * somebody who never had the secret. So nothing is written until the
     * signature verifies, and this test asserts both halves: the forged one
     * stores nothing, and the genuine one afterwards is applied rather than
     * swallowed.
     */
    public function test_a_forged_delivery_cannot_poison_the_idempotency_key(): void
    {
        $this->gateway->stubPayment('pay_hook', $this->providerOrderId, $this->order->payable_total_minor);

        $eventId = 'evt_the_one_that_matters';

        // The attacker, with no secret, claiming an event id in advance.
        $this->deliver(
            $this->body('payment.captured', 'pay_hook'),
            signature: str_repeat('0', 64),
            eventId: $eventId,
        )->assertStatus(400);

        $this->assertSame(0, PaymentEvent::query()->count(), 'a rejected delivery must leave no trace to collide with');

        // The provider's genuine delivery, with the same event id.
        $this->deliver($this->body('payment.captured', 'pay_hook'), eventId: $eventId)
            ->assertOk()
            ->assertJsonPath('data.outcome', PaymentEventOutcome::Applied->value);

        $this->assertSame(OrderStatus::Placed, $this->order->fresh()->status);
    }

    // --- idempotency ----------------------------------------------------------

    public function test_a_replayed_delivery_is_a_duplicate_and_runs_nothing_twice(): void
    {
        $this->gateway->stubPayment('pay_hook', $this->providerOrderId, $this->order->payable_total_minor);

        $raw = $this->body('payment.captured', 'pay_hook');

        $this->deliver($raw, eventId: 'evt_same')->assertOk()
            ->assertJsonPath('data.outcome', PaymentEventOutcome::Applied->value);

        $paidAt = $this->order->fresh()->paid_at;

        // Moved on, so that a second write would be visible. paid_at has
        // second precision and two calls in one second are indistinguishable.
        $this->travel(5)->minutes();

        $this->deliver($raw, eventId: 'evt_same')->assertOk()
            ->assertJsonPath('data.outcome', PaymentEventOutcome::Duplicate->value);

        $this->assertEquals($paidAt, $this->order->fresh()->paid_at);
        $this->assertSame(1, PaymentEvent::query()->count());
        $this->assertSame(1, Payment::query()->where('status', PaymentStatus::Captured->value)->count());
    }

    /**
     * A webhook arriving after the app already reported the same payment.
     *
     * Both are genuine and both are about the same money. The order must be paid
     * exactly once, with the timestamp from whichever got there first.
     */
    public function test_a_webhook_after_a_client_callback_settles_nothing_further(): void
    {
        $this->gateway->stubPayment('pay_hook', $this->providerOrderId, $this->order->payable_total_minor);

        $this->as($this->rahul)->postJson(
            '/api/v1/customer/orders/'.$this->order->uuid.'/payment/verify',
            [
                'provider_order_id' => $this->providerOrderId,
                'provider_payment_id' => 'pay_hook',
                'signature' => RazorpaySignature::compute($this->providerOrderId.'|pay_hook', self::KEY_SECRET),
            ],
        )->assertOk();

        $paidAt = $this->order->fresh()->paid_at;

        $this->travel(5)->minutes();

        $this->deliver($this->body('payment.captured', 'pay_hook'), eventId: 'evt_after')->assertOk();

        $this->assertEquals($paidAt, $this->order->fresh()->paid_at);
        $this->assertSame(1, Payment::query()->where('status', PaymentStatus::Captured->value)->count());
    }

    // --- what it does with the rest -------------------------------------------

    public function test_a_failure_event_records_the_failure_without_closing_the_order(): void
    {
        $this->gateway->stubPayment(
            'pay_bad',
            $this->providerOrderId,
            $this->order->payable_total_minor,
            PaymentStatus::Failed,
        );

        $this->deliver($this->body('payment.failed', 'pay_bad'), eventId: 'evt_fail')
            ->assertOk()
            ->assertJsonPath('data.outcome', PaymentEventOutcome::Applied->value);

        $this->order->refresh();

        $this->assertSame(OrderStatus::PaymentFailed, $this->order->status);
        $this->assertTrue($this->order->status->acceptsPayment());
    }

    /**
     * A verified delivery about something this deployment has never heard of.
     *
     * 200, not 500. The provider retries on a non-2xx, and answering with an
     * error for a condition no retry can fix earns an escalating storm of
     * deliveries.
     */
    public function test_a_delivery_about_an_unknown_order_is_accepted_and_recorded(): void
    {
        $this->deliver(
            $this->body('payment.captured', 'pay_unknown', 'order_NOT_OURS_AT_ALL'),
            eventId: 'evt_unknown',
        )
            ->assertOk()
            ->assertJsonPath('data.outcome', PaymentEventOutcome::Unknown->value);

        $this->assertSame(1, PaymentEvent::query()->count());
        $this->assertSame(OrderStatus::AwaitingPayment, $this->order->fresh()->status);
    }

    public function test_an_event_type_we_do_not_act_on_is_recorded_and_ignored(): void
    {
        $this->deliver($this->body('payment.dispute.created', 'pay_hook'), eventId: 'evt_ignored')
            ->assertOk()
            ->assertJsonPath('data.outcome', PaymentEventOutcome::Ignored->value);

        $this->assertSame(OrderStatus::AwaitingPayment, $this->order->fresh()->status);
    }

    /**
     * Even a genuine webhook does not settle the wrong amount.
     *
     * The webhook is signed and about a real payment against a real order — and
     * the provider says the money was ₹1. It goes through the same amount check
     * as everything else.
     */
    public function test_a_signed_webhook_for_the_wrong_amount_settles_nothing(): void
    {
        $this->gateway->stubPayment('pay_short', $this->providerOrderId, 100);

        $this->deliver($this->body('payment.captured', 'pay_short', null, 100), eventId: 'evt_short')
            ->assertOk();

        $this->assertNotSame(OrderStatus::Placed, $this->order->fresh()->status);
    }

    // --- the payload is not kept ---------------------------------------------

    /**
     * A digest is stored, and the body is not.
     *
     * A provider payload can carry a contact number, an email address, a billing
     * name and card metadata. None of it is ours to keep, and there is no column
     * it could go in.
     */
    public function test_the_raw_payload_is_never_stored(): void
    {
        $this->gateway->stubPayment('pay_hook', $this->providerOrderId, $this->order->payable_total_minor);

        $raw = $this->body('payment.captured', 'pay_hook');

        $this->deliver($raw, eventId: 'evt_digest')->assertOk();

        $event = PaymentEvent::query()->firstOrFail();

        $this->assertSame(hash('sha256', $raw), $event->payload_digest);

        foreach ($event->getAttributes() as $column => $value) {
            if (is_string($value)) {
                $this->assertStringNotContainsString('"payload"', $value, "{$column} holds the raw body");
                $this->assertStringNotContainsString('entity', $value, "{$column} holds the raw body");
            }
        }
    }
}
