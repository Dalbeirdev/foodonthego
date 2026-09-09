<?php

declare(strict_types=1);

namespace Tests\Feature\Api\Orders;

use App\Enums\OrderStatus;
use App\Enums\PaymentStatus;
use App\Models\Order;
use App\Models\OutboxEvent;
use App\Models\Payment;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Support\CustomerFactory;
use Tests\Support\RestaurantFixtures;
use Tests\TestCase;

/**
 * The sweeps, and the disasters they exist to catch.
 *
 * Both are about a moment that will happen: a process dies between taking money
 * and writing the order it paid for. One sweep finds the customer who was
 * charged for nothing; the other finds the restaurant about to cook for nobody.
 *
 * The second is the one that usually goes unwritten, because its victim is the
 * business rather than a person who complains.
 */
final class OrderRecoverySweepTest extends TestCase
{
    use RefreshDatabase;

    private User $rahul;

    private Restaurant $restaurant;

    protected function setUp(): void
    {
        parent::setUp();

        $this->rahul = CustomerFactory::rahul();
        $this->restaurant = RestaurantFixtures::nearRoute(0.4, 800, 'Highway Spice Kitchen');
    }

    // ------------------------------------------------------------ scenario 49

    public function test_the_sweep_places_an_order_for_a_stranded_capture(): void
    {
        [$order, $payment] = $this->strandedCapture();

        $this->assertNull($order->order_number);

        $this->artisan('orders:recover-captured', ['--grace' => 0])
            ->expectsOutputToContain('1 captured payment(s) without an order.')
            ->assertSuccessful();

        $order->refresh();

        $this->assertSame(OrderStatus::Placed, $order->status);
        $this->assertNotNull($order->order_number);
        $this->assertSame((int) $payment->id, (int) $order->placed_from_payment_id);
        $this->assertSame(1, OutboxEvent::query()->where('event_name', 'OrderPlaced')->count());
    }

    /**
     * Running it twice must not produce a second order.
     */
    public function test_the_sweep_is_idempotent(): void
    {
        $this->strandedCapture();

        $this->artisan('orders:recover-captured', ['--grace' => 0])->assertSuccessful();
        $this->artisan('orders:recover-captured', ['--grace' => 0])
            ->expectsOutputToContain('No captured payment is missing an order.')
            ->assertSuccessful();

        $this->assertSame(1, Order::query()->where('status', OrderStatus::Placed)->count());
        $this->assertSame(1, OutboxEvent::query()->where('event_name', 'OrderPlaced')->count());
    }

    /**
     * A capture from ten seconds ago is not stranded, it is in flight.
     *
     * Without the grace period the sweep races every ordinary payment and fills
     * the log with duplicate-prevented lines, hiding the real failures among
     * them.
     */
    public function test_a_capture_inside_the_grace_period_is_left_alone(): void
    {
        $this->strandedCapture();

        $this->artisan('orders:recover-captured', ['--grace' => 3600])
            ->expectsOutputToContain('No captured payment is missing an order.')
            ->assertSuccessful();

        $this->assertSame(0, Order::query()->where('status', OrderStatus::Placed)->count());
    }

    public function test_a_dry_run_reports_without_placing(): void
    {
        $this->strandedCapture();

        $this->artisan('orders:recover-captured', ['--grace' => 0, '--dry-run' => true])
            ->assertSuccessful();

        $this->assertSame(0, Order::query()->where('status', OrderStatus::Placed)->count());
    }

    // ------------------------------------------------------------ scenario 50

    public function test_the_integrity_check_is_quiet_when_every_order_has_its_money(): void
    {
        $this->strandedCapture();
        $this->artisan('orders:recover-captured', ['--grace' => 0])->assertSuccessful();

        $this->artisan('orders:check-integrity')
            ->expectsOutputToContain('Every placed order has a captured payment behind it.')
            ->assertSuccessful();
    }

    /**
     * Food a restaurant will cook that nobody paid for.
     */
    public function test_the_integrity_check_reports_an_order_with_no_captured_payment(): void
    {
        $order = new Order;
        $order->customer_id = $this->rahul->id;
        $order->restaurant_id = $this->restaurant->id;
        $order->currency = 'INR';
        $order->items_subtotal_minor = 24_900;
        $order->payable_total_minor = 24_900;
        $order->status = OrderStatus::Placed;
        $order->order_number = 'FOTG-260909-NOMONEY01';
        $order->placed_at = now();
        $order->save();

        $this->artisan('orders:check-integrity')
            ->expectsOutputToContain('1 placed order(s) without a captured payment:')
            ->assertFailed();
    }

    // ------------------------------------------------------------ the outbox

    public function test_publishing_drains_the_outbox_exactly_once(): void
    {
        $this->strandedCapture();
        $this->artisan('orders:recover-captured', ['--grace' => 0])->assertSuccessful();

        $this->artisan('outbox:publish')
            ->expectsOutputToContain('1 event(s) published.')
            ->assertSuccessful();

        $event = OutboxEvent::query()->firstOrFail();

        $this->assertSame('PUBLISHED', $event->status);
        $this->assertNotNull($event->published_at);

        // A second run finds nothing, so a minute-by-minute schedule does not
        // re-ship every event it has ever seen.
        $this->artisan('outbox:publish')
            ->expectsOutputToContain('0 event(s) published.')
            ->assertSuccessful();
    }

    /**
     * The payload carries identifiers and no business data.
     */
    public function test_the_event_payload_is_identifiers_only(): void
    {
        [$order] = $this->strandedCapture();
        $this->artisan('orders:recover-captured', ['--grace' => 0])->assertSuccessful();

        $payload = OutboxEvent::query()->firstOrFail()->payload;

        // Canonicalising, not assertSame.
        //
        // MySQL's JSON type does not preserve object key order — it stores keys
        // sorted by length and then by value, so the array comes back in an
        // order the application never chose. An order-sensitive assertion here
        // tests MySQL's storage format rather than the contract, and fails on a
        // payload that is entirely correct.
        $this->assertEqualsCanonicalizing(
            ['order_uuid', 'restaurant_id', 'payment_uuid'],
            array_keys($payload),
        );

        // Nothing about the customer, the basket, or the money.
        $encoded = json_encode($payload, JSON_THROW_ON_ERROR);
        $this->assertStringNotContainsString((string) $this->rahul->name, $encoded);
        $this->assertStringNotContainsString((string) $order->refresh()->payable_total_minor, $encoded);
    }

    // --- plumbing -------------------------------------------------------------

    /**
     * A captured payment whose order was never written — the crash, reproduced.
     *
     * @return array{0: Order, 1: Payment}
     */
    private function strandedCapture(): array
    {
        $order = new Order;
        $order->customer_id = $this->rahul->id;
        $order->restaurant_id = $this->restaurant->id;
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
        $payment->provider_order_id = 'order_stranded';
        $payment->provider_payment_id = 'pay_stranded';
        $payment->amount_minor = 24_900;
        $payment->currency = 'INR';
        $payment->status = PaymentStatus::Captured;
        $payment->verified_at = now()->subMinutes(30);
        $payment->save();

        return [$order, $payment];
    }
}
