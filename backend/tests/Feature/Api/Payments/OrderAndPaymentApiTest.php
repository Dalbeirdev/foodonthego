<?php

declare(strict_types=1);

namespace Tests\Feature\Api\Payments;

use App\Enums\ApiErrorCode;
use App\Enums\CheckoutQuoteStatus;
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
 * Placing an order and paying for it, over HTTP.
 *
 * The theme is one sentence: **the client is never believed about money.** It
 * cannot say what it owes, cannot say what it paid, and cannot say that it paid.
 * Several tests below post bodies stuffed with amounts and assert the response
 * is exactly what it would have been without them — not because the server
 * validates those fields, but because nothing reads them.
 *
 * The three checks that stand between a signed message and a paid order are
 * tested separately, because each closes a hole the others do not: the signature
 * proves the message is ours, the binding proves the payment is this order's,
 * and the amount proves it is the right money.
 */
final class OrderAndPaymentApiTest extends TestCase
{
    use RefreshDatabase;

    private const KEY_SECRET = 'test-key-secret-not-a-real-one';

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

    // --- plumbing -------------------------------------------------------------

    private function as(User $customer): self
    {
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', 'Bearer '.CustomerFactory::tokenFor($customer));
    }

    private function choosePickup(): void
    {
        $options = $this->as($this->rahul)
            ->postJson('/api/v1/customer/trips/'.$this->trip->uuid.'/cart/pickup-options')
            ->json('data.pickup');

        $this->as($this->rahul)->putJson(
            '/api/v1/customer/trips/'.$this->trip->uuid.'/cart/pickup-selection',
            ['pickup_option_id' => $options['recommended_option_id']],
        )->assertOk();
    }

    private function quote(): CheckoutQuote
    {
        $this->choosePickup();

        $id = $this->as($this->rahul)
            ->postJson('/api/v1/customer/trips/'.$this->trip->uuid.'/checkout/prepare')
            ->json('data.checkout_id');

        return CheckoutQuote::query()->where('uuid', $id)->firstOrFail();
    }

    /** @param array<string, mixed> $body */
    private function placeResponse(?CheckoutQuote $quote = null, array $body = [])
    {
        $quote ??= $this->quote();

        return $this->as($this->rahul)->postJson(
            '/api/v1/customer/trips/'.$this->trip->uuid.'/checkout/'.$quote->uuid.'/order',
            $body,
        );
    }

    private function placedOrder(): Order
    {
        $uuid = $this->placeResponse()->assertCreated()->json('data.id');

        return Order::query()->where('uuid', $uuid)->firstOrFail();
    }

    /** Places an order and opens a payment against it. */
    private function orderWithIntent(): array
    {
        $order = $this->placedOrder();

        $intent = $this->as($this->rahul)
            ->postJson('/api/v1/customer/orders/'.$order->uuid.'/payment-intent')
            ->assertOk()
            ->json('data.payment');

        return [$order, $intent['provider_order_id']];
    }

    private function signatureFor(string $providerOrderId, string $providerPaymentId): string
    {
        return RazorpaySignature::compute(
            $providerOrderId.'|'.$providerPaymentId,
            self::KEY_SECRET,
        );
    }

    /** @param array<string, mixed> $extra */
    private function verify(Order $order, string $providerOrderId, string $providerPaymentId, ?string $signature = null, array $extra = [])
    {
        return $this->as($this->rahul)->postJson(
            '/api/v1/customer/orders/'.$order->uuid.'/payment/verify',
            [
                'provider_order_id' => $providerOrderId,
                'provider_payment_id' => $providerPaymentId,
                'signature' => $signature ?? $this->signatureFor($providerOrderId, $providerPaymentId),
                ...$extra,
            ],
        );
    }

    // --- placing an order -----------------------------------------------------

    public function test_an_active_quote_becomes_an_order_at_the_quoted_total(): void
    {
        $quote = $this->quote();

        $data = $this->placeResponse($quote)->assertCreated()->json('data');

        $order = Order::query()->where('uuid', $data['id'])->firstOrFail();

        $this->assertSame($quote->payable_total_minor, $order->payable_total_minor);
        $this->assertSame($quote->items_subtotal_minor, $order->items_subtotal_minor);
        $this->assertSame(OrderStatus::AwaitingPayment, $order->status);
        // Deliberately inverted since Module 16. A quote that has been
        // accepted produces a payment target, not an order: no number, no
        // placed_at, nothing a customer could be shown as a purchase. The
        // number is minted when the money is captured.
        $this->assertNull($order->order_number);
        $this->assertNull($order->placed_at);
        $this->assertSame(OrderStatus::AwaitingPayment, $order->status);
    }

    /**
     * The lines are a snapshot, not a reference.
     *
     * Asserted by renaming the dish and repricing it *after* the order exists.
     * A receipt that resolved through the menu would change; this one must not.
     */
    public function test_order_lines_survive_the_menu_changing_underneath_them(): void
    {
        $order = $this->placedOrder();

        // forceFill, because every model in this project has an empty \$fillable
        // on purpose. Nothing reaches a column from a request body.
        $this->item->forceFill(['name' => 'Renamed Entirely', 'base_price_minor' => 99_900])->save();

        $data = $this->as($this->rahul)
            ->getJson('/api/v1/customer/orders/'.$order->uuid)
            ->assertOk()
            ->json('data');

        $this->assertSame('Paneer Tikka', $data['items'][0]['name']);
        $this->assertSame(24_900, $data['items'][0]['unit_price']['amount_minor']);
    }

    public function test_placing_an_order_consumes_the_quote(): void
    {
        $quote = $this->quote();

        $this->placeResponse($quote)->assertCreated();

        $this->assertSame(CheckoutQuoteStatus::Consumed, $quote->fresh()->status);
    }

    /**
     * A double tap must not buy the food twice.
     *
     * The second call answers 200 rather than 201, and there is exactly one
     * order — which is the assertion that would fail if somebody replaced the
     * unique index with a status check.
     */
    public function test_placing_the_same_quote_twice_returns_the_same_order(): void
    {
        $quote = $this->quote();

        $first = $this->placeResponse($quote)->assertCreated()->json('data.id');
        $second = $this->placeResponse($quote)->assertOk()->json('data.id');

        $this->assertSame($first, $second);
        $this->assertSame(1, Order::query()->count());
    }

    public function test_an_expired_quote_cannot_be_placed(): void
    {
        $quote = $this->quote();

        $quote->forceFill(['expires_at' => CarbonImmutable::now()->subMinute()])->save();

        $this->placeResponse($quote)
            ->assertStatus(409)
            ->assertJsonPath('error.code', ApiErrorCode::CheckoutQuoteExpired->value);

        $this->assertSame(0, Order::query()->count());
    }

    public function test_a_quote_that_no_longer_matches_the_cart_cannot_be_placed(): void
    {
        $quote = $this->quote();

        CartFixtures::line($this->cart, $this->item);

        // The fixture writes a row; the cart service is what bumps the version
        // and it is the version the quote's fingerprint covers. Calling it here
        // makes this the same cart change a customer would cause.
        $this->cart->recordContentChange();

        $this->placeResponse($quote)
            ->assertStatus(409)
            ->assertJsonPath('error.code', ApiErrorCode::CheckoutQuoteStale->value);

        $this->assertSame(0, Order::query()->count());
    }

    /**
     * Somebody else's quote is not found, not forbidden.
     *
     * 404 so that trying identifiers tells an attacker nothing about which ones
     * are real.
     */
    public function test_another_customers_quote_cannot_be_placed(): void
    {
        $quote = $this->quote();

        $ananya = CustomerFactory::ananya();

        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        $this->withHeader('Authorization', 'Bearer '.CustomerFactory::tokenFor($ananya))
            ->postJson('/api/v1/customer/trips/'.$this->trip->uuid.'/checkout/'.$quote->uuid.'/order')
            ->assertStatus(404);

        $this->assertSame(0, Order::query()->count());
    }

    // --- the client never sends money ----------------------------------------

    /**
     * An amount in the body changes nothing, because nothing reads it.
     *
     * Not "the server rejects a bad total" — there is no field for one. The
     * order is byte-for-byte what it would have been.
     */
    public function test_amounts_posted_when_placing_an_order_are_ignored_entirely(): void
    {
        $quote = $this->quote();

        $data = $this->placeResponse($quote, [
            'payable_total_minor' => 1,
            'items_subtotal_minor' => 1,
            'amount' => 1,
            'total' => 1,
            'discount_minor' => 999_999,
        ])->assertCreated()->json('data');

        $this->assertSame(
            $quote->payable_total_minor,
            $data['commercial']['payable_total']['amount_minor'],
        );
    }

    public function test_an_amount_posted_when_verifying_is_ignored_entirely(): void
    {
        [$order, $providerOrderId] = $this->orderWithIntent();

        $this->gateway->stubPayment('pay_ok', $providerOrderId, $order->payable_total_minor);

        $this->verify($order, $providerOrderId, 'pay_ok', null, ['amount' => 1, 'amount_minor' => 1])
            ->assertOk();

        $this->assertSame(OrderStatus::Placed, $order->fresh()->status);
    }

    // --- the payment intent ---------------------------------------------------

    public function test_the_intent_asks_the_provider_for_the_orders_total(): void
    {
        $order = $this->placedOrder();

        $this->as($this->rahul)
            ->postJson('/api/v1/customer/orders/'.$order->uuid.'/payment-intent')
            ->assertOk()
            ->assertJsonPath('data.payment.amount.amount_minor', $order->payable_total_minor);

        $this->assertCount(1, $this->gateway->createdOrders);
        $this->assertSame($order->payable_total_minor, $this->gateway->createdOrders[0]['amount']);
        // The uuid, because at intent time there is no order number to send.
        $this->assertSame((string) $order->uuid, $this->gateway->createdOrders[0]['receipt']);
    }

    /**
     * Asking twice does not open two ways to pay.
     *
     * Several live provider orders against one of ours is how a customer ends up
     * able to pay the same order twice.
     */
    public function test_asking_for_an_intent_twice_reuses_the_first(): void
    {
        $order = $this->placedOrder();

        $first = $this->as($this->rahul)->postJson('/api/v1/customer/orders/'.$order->uuid.'/payment-intent')
            ->assertOk()->json('data.payment.provider_order_id');

        $second = $this->as($this->rahul)->postJson('/api/v1/customer/orders/'.$order->uuid.'/payment-intent')
            ->assertOk()->json('data.payment.provider_order_id');

        $this->assertSame($first, $second);
        $this->assertCount(1, $this->gateway->createdOrders);
        $this->assertSame(1, Payment::query()->count());
    }

    /** The public key id is public. The secret is not, and must appear nowhere. */
    public function test_no_response_ever_contains_the_key_secret(): void
    {
        [$order, $providerOrderId] = $this->orderWithIntent();

        $this->gateway->stubPayment('pay_ok', $providerOrderId, $order->payable_total_minor);

        $bodies = [
            $this->as($this->rahul)->postJson('/api/v1/customer/orders/'.$order->uuid.'/payment-intent')->content(),
            $this->verify($order, $providerOrderId, 'pay_ok')->content(),
            $this->as($this->rahul)->getJson('/api/v1/customer/orders/'.$order->uuid)->content(),
            $this->as($this->rahul)->getJson('/api/v1/customer/orders')->content(),
        ];

        foreach ($bodies as $body) {
            $this->assertStringNotContainsString(self::KEY_SECRET, $body);
            $this->assertStringNotContainsString('key_secret', $body);
        }
    }

    public function test_an_order_already_paid_will_not_open_another_payment(): void
    {
        [$order, $providerOrderId] = $this->orderWithIntent();

        $this->gateway->stubPayment('pay_ok', $providerOrderId, $order->payable_total_minor);
        $this->verify($order, $providerOrderId, 'pay_ok')->assertOk();

        $this->as($this->rahul)
            ->postJson('/api/v1/customer/orders/'.$order->uuid.'/payment-intent')
            ->assertStatus(409)
            ->assertJsonPath('error.code', ApiErrorCode::OrderAlreadyPaid->value);
    }

    public function test_when_the_gateway_is_unreachable_no_payment_row_is_written(): void
    {
        $order = $this->placedOrder();

        $this->gateway->failNextCreateOrder();

        $this->as($this->rahul)
            ->postJson('/api/v1/customer/orders/'.$order->uuid.'/payment-intent')
            ->assertStatus(503)
            ->assertJsonPath('error.code', ApiErrorCode::PaymentGatewayUnavailable->value);

        $this->assertSame(0, Payment::query()->count());
        $this->assertSame(OrderStatus::AwaitingPayment, $order->fresh()->status);
    }

    // --- verification: the three checks ---------------------------------------

    public function test_a_genuine_result_settles_the_order(): void
    {
        [$order, $providerOrderId] = $this->orderWithIntent();

        $this->gateway->stubPayment('pay_ok', $providerOrderId, $order->payable_total_minor);

        $this->verify($order, $providerOrderId, 'pay_ok')
            ->assertOk()
            ->assertJsonPath('data.status', OrderStatus::Placed->value);

        $order->refresh();

        $this->assertSame(OrderStatus::Placed, $order->status);
        $this->assertNotNull($order->paid_at);
        $this->assertSame(PaymentStatus::Captured, $order->settledPayment()?->status);
    }

    /** Check one: the message must be ours. */
    public function test_a_forged_signature_settles_nothing(): void
    {
        [$order, $providerOrderId] = $this->orderWithIntent();

        $this->gateway->stubPayment('pay_ok', $providerOrderId, $order->payable_total_minor);

        $this->verify($order, $providerOrderId, 'pay_ok', str_repeat('a', 64))
            ->assertStatus(422)
            ->assertJsonPath('error.code', ApiErrorCode::PaymentSignatureInvalid->value);

        $this->assertSame(OrderStatus::AwaitingPayment, $order->fresh()->status);
    }

    /**
     * Check two: a genuinely signed payment belonging to a different provider
     * order settles nothing.
     *
     * This is the hole a signature check alone does not close. The signature
     * here is real and verifies; what fails is that the provider says the
     * payment belongs somewhere else.
     */
    public function test_a_correctly_signed_payment_for_another_provider_order_settles_nothing(): void
    {
        [$order, $providerOrderId] = $this->orderWithIntent();

        // Genuinely captured, genuinely the right money — for somebody else.
        $this->gateway->stubPayment('pay_elsewhere', 'order_FAKE999999', $order->payable_total_minor);

        $this->verify($order, $providerOrderId, 'pay_elsewhere')
            ->assertStatus(422)
            ->assertJsonPath('error.code', ApiErrorCode::PaymentSignatureInvalid->value);

        $this->assertSame(OrderStatus::AwaitingPayment, $order->fresh()->status);
    }

    /**
     * Check three: the right money.
     *
     * A real payment, correctly signed, correctly bound — for ₹1. Without this
     * check the order settles.
     */
    public function test_a_payment_for_the_wrong_amount_settles_nothing(): void
    {
        [$order, $providerOrderId] = $this->orderWithIntent();

        $this->gateway->stubPayment('pay_short', $providerOrderId, 100);

        $this->verify($order, $providerOrderId, 'pay_short')
            ->assertStatus(409)
            ->assertJsonPath('error.code', ApiErrorCode::PaymentAmountMismatch->value);

        $this->assertNotSame(OrderStatus::Placed, $order->fresh()->status);
    }

    public function test_a_declined_payment_leaves_the_order_payable(): void
    {
        [$order, $providerOrderId] = $this->orderWithIntent();

        $this->gateway->stubPayment(
            'pay_declined',
            $providerOrderId,
            $order->payable_total_minor,
            PaymentStatus::Failed,
            failureReason: 'Card declined by issuer',
        );

        $this->verify($order, $providerOrderId, 'pay_declined')
            ->assertStatus(422)
            ->assertJsonPath('error.code', ApiErrorCode::PaymentDeclined->value);

        $order->refresh();

        $this->assertSame(OrderStatus::PaymentFailed, $order->status);
        $this->assertTrue($order->status->acceptsPayment(), 'a declined card must not close the order');
    }

    /** A provider's decline text is written for a merchant, not a customer. */
    public function test_a_providers_failure_text_is_not_relayed_to_the_customer(): void
    {
        [$order, $providerOrderId] = $this->orderWithIntent();

        $this->gateway->stubPayment(
            'pay_declined',
            $providerOrderId,
            $order->payable_total_minor,
            PaymentStatus::Failed,
            failureReason: 'issuer_declined_suspected_fraud_on_card_4111',
        );

        $body = $this->verify($order, $providerOrderId, 'pay_declined')->assertStatus(422)->content();

        $this->assertStringNotContainsString('4111', $body);
        $this->assertStringNotContainsString('suspected_fraud', $body);
    }

    /**
     * Settling twice must leave the first settlement alone.
     *
     * **The clock is moved between the two calls, and that is not decoration.**
     * The first version of this test made both calls in the same second, and
     * `paid_at` is a second-precision column — so a build with the "is it
     * already paid?" guard deleted rewrote the timestamp with an identical
     * value and the test still passed. The negative control caught it by
     * staying silent. Five minutes apart, a second write is visible.
     */
    public function test_verifying_twice_settles_once(): void
    {
        [$order, $providerOrderId] = $this->orderWithIntent();

        $this->gateway->stubPayment('pay_ok', $providerOrderId, $order->payable_total_minor);

        $this->verify($order, $providerOrderId, 'pay_ok')->assertOk();

        $paidAt = $order->fresh()->paid_at;
        $verifiedAt = $order->fresh()->settledPayment()?->verified_at;

        $this->travel(5)->minutes();

        $this->verify($order, $providerOrderId, 'pay_ok')->assertOk();

        $this->assertEquals($paidAt, $order->fresh()->paid_at, 'paid_at was rewritten by a second settlement');
        $this->assertEquals($verifiedAt, $order->fresh()->settledPayment()?->verified_at);
        $this->assertSame(1, Payment::query()->where('status', PaymentStatus::Captured->value)->count());
    }

    // --- ownership ------------------------------------------------------------

    public function test_another_customer_cannot_read_or_pay_for_this_order(): void
    {
        [$order, $providerOrderId] = $this->orderWithIntent();

        $this->gateway->stubPayment('pay_ok', $providerOrderId, $order->payable_total_minor);

        $ananya = CustomerFactory::ananya();

        $this->app['auth']->forgetGuards();
        $this->flushHeaders();
        $this->withHeader('Authorization', 'Bearer '.CustomerFactory::tokenFor($ananya));

        $this->getJson('/api/v1/customer/orders/'.$order->uuid)->assertStatus(404);
        $this->postJson('/api/v1/customer/orders/'.$order->uuid.'/payment-intent')->assertStatus(404);
        $this->postJson('/api/v1/customer/orders/'.$order->uuid.'/payment/verify', [
            'provider_order_id' => $providerOrderId,
            'provider_payment_id' => 'pay_ok',
            'signature' => $this->signatureFor($providerOrderId, 'pay_ok'),
        ])->assertStatus(404);

        $this->assertSame(OrderStatus::AwaitingPayment, $order->fresh()->status);
    }

    public function test_a_provider_order_id_from_another_order_is_not_found(): void
    {
        [$first, $firstProviderOrderId] = $this->orderWithIntent();

        // A second order, with its own provider order.
        CartFixtures::line($this->cart, $this->item);
        $second = $this->placedOrder();

        $this->as($this->rahul)->postJson('/api/v1/customer/orders/'.$second->uuid.'/payment-intent')->assertOk();

        $this->gateway->stubPayment('pay_ok', $firstProviderOrderId, $first->payable_total_minor);

        // The first order's provider order id, presented against the second.
        $this->verify($second, $firstProviderOrderId, 'pay_ok')
            ->assertStatus(404)
            ->assertJsonPath('error.code', ApiErrorCode::PaymentNotFound->value);

        $this->assertSame(OrderStatus::AwaitingPayment, $second->fresh()->status);
    }

    // --- one response, one clock ---------------------------------------------

    /**
     * Module 14's rule, applied to this module's bodies.
     *
     * Walks every string in the response that looks like an instant and asserts
     * they all carry the same offset, and that it is the restaurant's. A body
     * mixing UTC with +05:30 renders a pickup window hours in the customer's
     * past on the screen where they collect their food.
     */
    public function test_every_instant_in_one_order_response_is_on_one_clock(): void
    {
        [$order, $providerOrderId] = $this->orderWithIntent();

        $this->gateway->stubPayment('pay_ok', $providerOrderId, $order->payable_total_minor);
        $this->verify($order, $providerOrderId, 'pay_ok')->assertOk();

        $body = $this->as($this->rahul)->getJson('/api/v1/customer/orders/'.$order->uuid)->assertOk()->json('data');

        $offsets = [];
        $found = [];

        $walk = function (array $node, string $path) use (&$walk, &$offsets, &$found): void {
            foreach ($node as $key => $value) {
                $here = $path === '' ? (string) $key : $path.'.'.$key;

                if (is_array($value)) {
                    $walk($value, $here);

                    continue;
                }

                if (is_string($value) && preg_match('/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}([+-]\d{2}:\d{2}|Z)$/', $value, $m) === 1) {
                    $offsets[$m[1]] = true;
                    $found[] = $here.' = '.$value;
                }
            }
        };

        $walk($body, '');

        $this->assertNotEmpty($found, 'the response carried no instants at all, so this proves nothing');

        $this->assertCount(
            1,
            $offsets,
            "more than one clock in one response:\n  ".implode("\n  ", $found),
        );

        $this->assertSame(['+05:30'], array_keys($offsets));
    }

    // --- nothing invented -----------------------------------------------------

    /**
     * With no commercial rule configured the payable is the subtotal, and the
     * charges list is empty rather than a set of zeroes.
     *
     * "Not configured" and "configured as nought" are different facts. An order
     * showing "Tax 0.00" tells a customer a decision was made when none was.
     */
    public function test_an_order_with_no_configured_charges_shows_no_charges(): void
    {
        $order = $this->placedOrder();

        $data = $this->as($this->rahul)->getJson('/api/v1/customer/orders/'.$order->uuid)->assertOk()->json('data');

        $this->assertSame([], $data['commercial']['charges']);
        $this->assertSame([], $data['commercial']['discounts']);
        $this->assertFalse($data['commercial']['has_configured_adjustments']);
        $this->assertSame(
            $data['commercial']['items_subtotal']['amount_minor'],
            $data['commercial']['payable_total']['amount_minor'],
        );
    }
}
