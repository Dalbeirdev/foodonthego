<?php

declare(strict_types=1);

namespace Tests\Feature\Api\Payments;

use App\Enums\OrderStatus;
use App\Enums\PaymentStatus;
use App\Enums\PaymentVerificationSource;
use App\Enums\Role;
use App\Enums\TenantRole;
use App\Models\Order;
use App\Models\OrderItem;
use App\Models\Payment;
use App\Models\Restaurant;
use App\Models\User;
use App\Services\Orders\OrderNumberGenerator;
use App\Services\Payments\PaymentGateway;
use App\Services\Payments\ReconciliationService;
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Str;
use Tests\Support\CustomerFactory;
use Tests\Support\FakePaymentGateway;
use Tests\Support\RestaurantFixtures;
use Tests\Support\TenancyFixtures;
use Tests\TestCase;

/**
 * Orders across the tenant boundary, and the money nobody told us about.
 *
 * Two subjects in one file because they share a fixture: orders that exist
 * without going through the whole checkout flow. Building them directly is
 * deliberate here — what is under test is who can read an order and what
 * reconciliation does with it, not how it came to exist, and driving fourteen
 * modules of checkout to get one would make these tests fragile for no gain.
 */
final class OrderTenancyAndReconciliationTest extends TestCase
{
    use RefreshDatabase;

    private Restaurant $spice;

    private Restaurant $coast;

    private User $customer;

    private FakePaymentGateway $gateway;

    protected function setUp(): void
    {
        parent::setUp();

        Cache::flush();

        config([
            'services.razorpay.key_id' => 'rzp_test_fake',
            'services.razorpay.key_secret' => 'test-key-secret-not-a-real-one',
            'services.razorpay.webhook_secret' => 'test-webhook-secret',
        ]);

        $this->gateway = new FakePaymentGateway;
        $this->app->instance(PaymentGateway::class, $this->gateway);

        $this->spice = RestaurantFixtures::nearRoute(0.4, 800, 'Spice Kitchen');
        $this->coast = RestaurantFixtures::nearRoute(0.6, 900, 'Coast Cafe');

        $this->customer = CustomerFactory::rahul();
    }

    /** An order sitting on a restaurant, without walking the checkout flow. */
    private function order(Restaurant $restaurant, int $totalMinor = 24_900, ?CarbonImmutable $placedAt = null): Order
    {
        $order = new Order;

        $order->forceFill([
            'uuid' => (string) Str::uuid(),
            'order_number' => (new OrderNumberGenerator)->candidate(CarbonImmutable::now()),
            'customer_id' => $this->customer->id,
            'restaurant_id' => $restaurant->id,
            'currency' => 'INR',
            'items_subtotal_minor' => $totalMinor,
            'payable_total_minor' => $totalMinor,
            'status' => OrderStatus::AwaitingPayment->value,
            'pickup_timezone' => 'Asia/Kolkata',
            'placed_at' => $placedAt ?? CarbonImmutable::now(),
        ])->save();

        $item = new OrderItem;
        $item->forceFill([
            'uuid' => (string) Str::uuid(),
            'order_id' => $order->id,
            'restaurant_id' => $restaurant->id,
            'item_name_snapshot' => 'Paneer Tikka',
            'unit_price_minor' => $totalMinor,
            'line_total_minor' => $totalMinor,
            'currency' => 'INR',
            'quantity' => 1,
        ])->save();

        return $order;
    }

    private function payment(Order $order, string $providerOrderId): Payment
    {
        $payment = new Payment;

        $payment->forceFill([
            'uuid' => (string) Str::uuid(),
            'order_id' => $order->id,
            'provider' => 'fake',
            'provider_order_id' => $providerOrderId,
            'amount_minor' => $order->payable_total_minor,
            'currency' => 'INR',
            'status' => PaymentStatus::Created->value,
        ])->save();

        return $payment;
    }

    private function asOperator(User $operator): self
    {
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', 'Bearer '.TenancyFixtures::tokenFor($operator));
    }

    // --- tenant isolation -----------------------------------------------------

    public function test_an_operator_sees_only_their_own_tenants_orders(): void
    {
        $this->order($this->spice);
        $this->order($this->coast);

        $priya = TenancyFixtures::operator('Priya', '+919999900201');
        TenancyFixtures::assign($priya, $this->spice, TenantRole::Manager);

        $orders = $this->asOperator($priya)
            ->getJson('/api/v1/restaurant/orders')
            ->assertOk()
            ->json('data.orders');

        $this->assertCount(1, $orders);
        $this->assertSame('Spice Kitchen', $orders[0]['restaurant']['name']);
    }

    /**
     * The indirect path, carrying money this time.
     *
     * An order reached by its own identifier names no restaurant anywhere in the
     * request. The obvious implementation looks right and hands one restaurant's
     * customers and takings to another.
     */
    public function test_an_order_from_another_tenant_is_not_found_by_its_own_id(): void
    {
        $coastOrder = $this->order($this->coast);

        $priya = TenancyFixtures::operator('Priya', '+919999900202');
        TenancyFixtures::assign($priya, $this->spice, TenantRole::Manager);

        $this->asOperator($priya)
            ->getJson('/api/v1/restaurant/orders/'.$coastOrder->uuid)
            ->assertStatus(404);
    }

    /** And a fictional one answers identically, so ids cannot be enumerated. */
    public function test_a_foreign_order_and_a_nonexistent_one_answer_identically(): void
    {
        $coastOrder = $this->order($this->coast);

        $priya = TenancyFixtures::operator('Priya', '+919999900203');
        TenancyFixtures::assign($priya, $this->spice, TenantRole::Manager);

        $foreign = $this->asOperator($priya)->getJson('/api/v1/restaurant/orders/'.$coastOrder->uuid);
        $fictional = $this->asOperator($priya)->getJson('/api/v1/restaurant/orders/'.Str::uuid());

        $this->assertSame($foreign->status(), $fictional->status());
        $this->assertSame($foreign->json('error.code'), $fictional->json('error.code'));
        $this->assertSame($foreign->json('error.message'), $fictional->json('error.message'));
    }

    public function test_an_operator_with_no_assignment_sees_no_orders(): void
    {
        $this->order($this->spice);

        $nobody = TenancyFixtures::operator('Nobody', '+919999900204');

        $this->assertSame(
            [],
            $this->asOperator($nobody)->getJson('/api/v1/restaurant/orders')->assertOk()->json('data.orders'),
        );
    }

    public function test_a_customer_cannot_reach_the_restaurant_order_surface(): void
    {
        $this->order($this->spice);

        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        $this->withHeader('Authorization', 'Bearer '.CustomerFactory::tokenFor($this->customer))
            ->getJson('/api/v1/restaurant/orders')
            ->assertStatus(403);
    }

    /**
     * A super administrator is refused at the restaurant surface itself.
     *
     * The first draft of this test expected an empty list and got a 403, which
     * is the more correct answer: the role gate rejects them before tenancy is
     * ever consulted. The two gates do different jobs and this is the surface
     * one — `role:` says which kind of account belongs on this surface at all.
     */
    public function test_a_super_administrator_is_not_on_the_restaurant_surface(): void
    {
        $this->order($this->spice);

        $meera = TenancyFixtures::operator('Meera', '+919999900205', Role::SuperAdmin);

        $this->asOperator($meera)->getJson('/api/v1/restaurant/orders')->assertStatus(403);
    }

    /**
     * And with the surface gate out of the way, the tenancy scope itself still
     * gives a grantless super administrator nothing.
     *
     * Asserted against the query scope rather than a route, because no admin
     * order endpoint exists yet — and inventing one purely to have something to
     * point a test at would be building product to satisfy a test. The claim
     * being checked is Module 14T's: breadth is a grant, never a role string.
     */
    public function test_the_order_scope_gives_a_grantless_super_administrator_nothing(): void
    {
        $this->order($this->spice);
        $this->order($this->coast);

        $meera = TenancyFixtures::operator('Meera', '+919999900206', Role::SuperAdmin);

        $this->assertSame(0, Order::query()->inReachableTenant($meera)->count());

        // And a grant for one restaurant reaches exactly that one — the positive
        // half, without which the assertion above would pass on a scope that
        // returns nothing to anybody.
        TenancyFixtures::grant($meera, $this->spice, TenantRole::Staff);

        $reached = Order::query()->inReachableTenant($meera)->get();

        $this->assertCount(1, $reached);
        $this->assertSame($this->spice->id, $reached->first()?->restaurant_id);
    }

    // --- reconciliation -------------------------------------------------------

    /**
     * The case reconciliation exists for.
     *
     * The customer paid. The app died before reporting it and the webhook never
     * arrived. Nothing but going and asking will find this.
     */
    public function test_reconciliation_settles_an_order_the_provider_says_was_paid(): void
    {
        $order = $this->order($this->spice, placedAt: CarbonImmutable::now()->subHour());
        $payment = $this->payment($order, 'order_FAKE000001');

        $this->gateway->stubPayment('pay_found', 'order_FAKE000001', $order->payable_total_minor);

        $result = app(ReconciliationService::class)->run();

        $order->refresh();

        $this->assertSame(1, $result['settled']);
        $this->assertSame(OrderStatus::Placed, $order->status);
        $this->assertSame(PaymentVerificationSource::Reconciliation, $payment->fresh()->verification_source);
    }

    /**
     * A grace period, so this never races a webhook that is merely in flight.
     */
    public function test_reconciliation_leaves_a_freshly_placed_order_alone(): void
    {
        $order = $this->order($this->spice, placedAt: CarbonImmutable::now());
        $this->payment($order, 'order_FAKE000002');

        $this->gateway->stubPayment('pay_recent', 'order_FAKE000002', $order->payable_total_minor);

        $result = app(ReconciliationService::class)->run(olderThanMinutes: 15);

        $this->assertSame(0, $result['examined']);
        $this->assertSame(OrderStatus::AwaitingPayment, $order->fresh()->status);
    }

    /**
     * A captured payment for the wrong money is not quietly settled.
     *
     * This is the path with nobody waiting on it, which makes it the one where
     * a shortcut would never be noticed. It goes through the same amount check
     * as the other two, and the mismatch is counted rather than swallowed.
     */
    public function test_reconciliation_refuses_a_captured_payment_for_the_wrong_amount(): void
    {
        $order = $this->order($this->spice, placedAt: CarbonImmutable::now()->subHour());
        $this->payment($order, 'order_FAKE000003');

        $this->gateway->stubPayment('pay_wrong', 'order_FAKE000003', 100);

        $result = app(ReconciliationService::class)->run();

        $this->assertSame(0, $result['settled']);
        $this->assertSame(1, $result['failed']);
        $this->assertNotSame(OrderStatus::Placed, $order->fresh()->status);
    }

    public function test_reconciliation_reports_an_unreachable_provider_without_settling(): void
    {
        $order = $this->order($this->spice, placedAt: CarbonImmutable::now()->subHour());
        $this->payment($order, 'order_FAKE000004');

        $this->gateway->failFetch('order_FAKE000004');

        $result = app(ReconciliationService::class)->run();

        $this->assertSame(1, $result['unreachable']);
        $this->assertSame(0, $result['settled']);
        $this->assertSame(OrderStatus::AwaitingPayment, $order->fresh()->status);
    }

    public function test_reconciliation_leaves_an_unpaid_order_unpaid(): void
    {
        $order = $this->order($this->spice, placedAt: CarbonImmutable::now()->subHour());
        $this->payment($order, 'order_FAKE000005');

        // The provider knows of no payment against it, which is the ordinary
        // case: the customer simply abandoned the checkout.
        $result = app(ReconciliationService::class)->run();

        $this->assertSame(0, $result['settled']);
        $this->assertSame(0, $result['failed']);
        $this->assertSame(OrderStatus::AwaitingPayment, $order->fresh()->status);
    }
}
