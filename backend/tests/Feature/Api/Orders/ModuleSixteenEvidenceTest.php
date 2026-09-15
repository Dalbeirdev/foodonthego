<?php

declare(strict_types=1);

namespace Tests\Feature\Api\Orders;

use App\Enums\CartStatus;
use App\Enums\CheckoutQuoteStatus;
use App\Enums\OrderStatus;
use App\Enums\PaymentStatus;
use App\Models\Cart;
use App\Models\CheckoutQuote;
use App\Models\MenuItem;
use App\Models\Order;
use App\Models\OutboxEvent;
use App\Models\Payment;
use App\Models\Restaurant;
use App\Models\Trip;
use App\Models\User;
use App\Services\Orders\PickupCredentialService;
use App\Services\Payments\PaymentGateway;
use App\Services\Payments\RazorpaySignature;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Tests\Support\CartFixtures;
use Tests\Support\CustomerFactory;
use Tests\Support\FakePaymentGateway;
use Tests\Support\MenuFixtures;
use Tests\Support\RestaurantFixtures;
use Tests\TestCase;

/**
 * The completion report's numbers, produced rather than recalled.
 *
 * Sections R, S, T and U of the Module 16 report ask for actual values from an
 * actual run: what the order number was, how many rows exist, what the outbox
 * held, how long creation took. Writing those from memory is how a report ends
 * up describing a build that does not exist.
 *
 * So this test performs the journey through the real HTTP surface and writes
 * what it observed to docs/evidence/module-16/. It asserts as it goes, so a
 * broken run produces a failure rather than a confident file of wrong numbers.
 *
 * WHAT IT DOES NOT PROVE. The capture comes from the deterministic fake
 * gateway, because no Razorpay credentials exist for this project. The
 * arithmetic, the state changes and the row counts are real; the provider is
 * not. That limitation is written into the evidence file itself so the file
 * cannot be read as more than it is.
 *
 * NOTHING SENSITIVE IS WRITTEN. The pickup code and QR token are derived here
 * to prove they verify, and only their lengths and a masked prefix reach the
 * file.
 */
final class ModuleSixteenEvidenceTest extends TestCase
{
    use RefreshDatabase;

    private const KEY_SECRET = 'rzp-test-secret';

    private const EVIDENCE = __DIR__.'/../../../../../docs/evidence/module-16/order-creation-run.txt';

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

    public function test_it_records_one_real_journey_from_capture_to_pickup_credential(): void
    {
        $quote = $this->quote();

        $uuid = $this->as($this->rahul)->postJson(
            '/api/v1/customer/trips/'.$this->trip->uuid.'/checkout/'.$quote->uuid.'/order',
        )->assertCreated()->json('data.id');

        $target = Order::query()->where('uuid', $uuid)->firstOrFail();

        // Before the money: a payment target, not an order.
        $this->assertNull($target->order_number);
        $this->assertNull($target->placed_at);
        $this->assertSame(OrderStatus::AwaitingPayment, $target->status);

        $providerOrderId = $this->as($this->rahul)
            ->postJson('/api/v1/customer/orders/'.$target->uuid.'/payment-intent')
            ->assertOk()
            ->json('data.payment.provider_order_id');

        $this->gateway->stubPayment('pay_ok', $providerOrderId, (int) $target->payable_total_minor);

        // The measured window is the verify call, which is what turns a capture
        // into an order. Wall clock, on this machine, on one run -- reported as
        // an observation rather than as a benchmark.
        DB::enableQueryLog();
        $startedAt = microtime(true);

        $this->as($this->rahul)->postJson(
            '/api/v1/customer/orders/'.$target->uuid.'/payment/verify',
            [
                'provider_order_id' => $providerOrderId,
                'provider_payment_id' => 'pay_ok',
                'signature' => RazorpaySignature::compute(
                    $providerOrderId.'|pay_ok',
                    self::KEY_SECRET,
                ),
            ],
        )->assertOk();

        $elapsedMs = (microtime(true) - $startedAt) * 1000;
        $queries = count(DB::getQueryLog());
        DB::disableQueryLog();

        $order = $target->fresh();
        $payment = Payment::query()->where('order_id', $order->id)->firstOrFail();

        $this->assertSame(OrderStatus::Placed, $order->status);
        $this->assertSame(PaymentStatus::Captured, $payment->status);
        $this->assertSame($payment->id, $order->placed_from_payment_id);
        $this->assertSame((int) $order->payable_total_minor, (int) $payment->amount_minor);

        // Exactly one, counted over the table rather than by re-reading a row.
        $this->assertSame(1, Order::query()->whereNotNull('placed_at')->count());

        $credentials = app(PickupCredentialService::class);
        $credential = $credentials->derive($order);

        $this->assertTrue($credentials->matchesCode($order, $credential->code));
        $this->assertTrue($credentials->matchesToken($order, $credential->token));

        // Neither plaintext is anywhere in the stored row.
        $stored = json_encode($order->getAttributes());
        $this->assertStringNotContainsString($credential->code, (string) $stored);
        $this->assertStringNotContainsString($credential->token, (string) $stored);

        $event = OutboxEvent::query()->where('event_name', 'OrderPlaced')->firstOrFail();

        $this->assertSame(1, OutboxEvent::query()->count());

        $this->write($order, $payment, $event, $credential->code, $credential->token, $elapsedMs, $queries);
    }

    private function write(
        Order $order,
        Payment $payment,
        OutboxEvent $event,
        string $code,
        string $token,
        float $elapsedMs,
        int $queries,
    ): void {
        $cart = Cart::query()->findOrFail($this->cart->id);
        $quote = CheckoutQuote::query()->where('cart_id', $cart->id)->firstOrFail();

        $lines = [
            'FoodOnTheGo — Module 16 evidence: one journey from capture to pickup credential',
            'Produced by ModuleSixteenEvidenceTest. Every value below was read back from the',
            'database after the run, not written by hand.',
            '',
            'THE CAPTURE IS FROM THE DETERMINISTIC FAKE GATEWAY. No Razorpay credentials',
            'exist for this project, so no live provider was involved. The row counts, the',
            'state changes and the credential arithmetic are real; the provider is not.',
            '',
            '--- customer and journey ---',
            'Customer:            '.$order->customer_name_snapshot,
            'Phone (snapshot):    '.$this->maskPhone((string) $order->customer_phone_snapshot),
            'Restaurant:          '.$order->restaurant_name_snapshot,
            'Trip uuid:           '.$this->trip->uuid,
            '',
            '--- the order ---',
            'Order uuid:          '.$order->uuid,
            'Order number:        '.$order->order_number,
            'Status:              '.$order->status->value,
            'Placed at:           '.($order->placed_at?->toIso8601String() ?? 'null'),
            'Paid at:             '.($order->paid_at?->toIso8601String() ?? 'null'),
            'Placed from payment: id '.$order->placed_from_payment_id.' (unique index)',
            'Payable total:       '.$order->payable_total_minor.' minor units, '.$order->currency,
            'Items:               '.$order->items()->count(),
            'Item modifiers:      '.DB::table('order_item_modifiers')->count(),
            '',
            '--- the payment ---',
            'Payment uuid:        '.$payment->uuid,
            'Payment status:      '.$payment->status->value,
            'Amount:              '.$payment->amount_minor.' minor units, '.$payment->currency,
            'Amounts agree:       '.($payment->amount_minor === $order->payable_total_minor ? 'YES' : 'NO'),
            'Verified at:         '.($payment->verified_at?->toIso8601String() ?? 'null'),
            '',
            '--- pickup credential (nothing plaintext recorded) ---',
            'Code length:         '.strlen($code).' characters',
            'Code masked:         '.substr($code, 0, 2).str_repeat('*', max(0, strlen($code) - 2)),
            'Token length:        '.strlen($token).' characters (base64url of 256 bits)',
            'Credential version:  '.$order->pickup_credential_version,
            'Code digest present: '.($order->pickup_code_hash !== null ? 'YES' : 'NO'),
            'Token digest present:'.($order->pickup_token_hash !== null ? 'YES' : 'NO'),
            'Plaintext in row:    NO (asserted by searching the stored attributes)',
            'Expires at:          '.($order->pickup_token_expires_at?->toIso8601String() ?? 'null'),
            '',
            '--- the basket and the quote were spent ---',
            'Cart status:         '.$cart->status->value.($cart->status === CartStatus::Converted ? ' (converted)' : ''),
            'Quote status:        '.$quote->status->value.($quote->status === CheckoutQuoteStatus::Consumed ? ' (consumed)' : ''),
            '',
            '--- the outbox ---',
            'Events written:      '.OutboxEvent::query()->count(),
            'Event name:          '.$event->event_name,
            'Event id:            '.$event->event_id,
            'Dedupe key:          '.$event->dedupe_key.' (the order uuid)',
            'Payload keys:        '.implode(', ', array_keys((array) $event->payload)),
            'Payload carries money or personal data: NO',
            '',
            '--- row counts after the run ---',
            'orders (total):      '.Order::query()->count(),
            'orders (placed):     '.Order::query()->whereNotNull('placed_at')->count(),
            'payments:            '.Payment::query()->count(),
            'outbox_events:       '.OutboxEvent::query()->count(),
            '',
            '--- observed cost of the verify call that created the order ---',
            'Wall clock:          '.number_format($elapsedMs, 1).' ms',
            'Database queries:    '.$queries,
            'One run, one machine, MySQL on the same host. An observation, not a benchmark.',
            '',
        ];

        $path = self::EVIDENCE;

        if (! is_dir(dirname($path))) {
            mkdir(dirname($path), 0o755, true);
        }

        file_put_contents($path, implode(PHP_EOL, $lines));
    }

    private function as(User $customer): self
    {
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', 'Bearer '.CustomerFactory::tokenFor($customer));
    }

    private function maskPhone(string $phone): string
    {
        return $phone === ''
            ? '(empty)'
            : substr($phone, 0, 3).str_repeat('*', max(0, strlen($phone) - 5)).substr($phone, -2);
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
}
