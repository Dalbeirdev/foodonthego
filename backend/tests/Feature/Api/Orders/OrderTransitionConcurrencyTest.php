<?php

declare(strict_types=1);

namespace Tests\Feature\Api\Orders;

use App\Enums\OrderStatus;
use App\Enums\OrderTransitionSource;
use App\Exceptions\Orders\OrderTransitionNotAllowed;
use App\Models\Order;
use App\Models\OrderStatusHistory;
use App\Models\OutboxEvent;
use App\Models\Restaurant;
use App\Models\User;
use App\Services\Orders\OrderTransitionActor;
use App\Services\Orders\OrderTransitionService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Support\CustomerFactory;
use Tests\Support\RestaurantFixtures;
use Tests\TestCase;

/**
 * Two actors, one order, one truth.
 *
 * These are the tests that would be written after the first production incident
 * if they were not written now. A status column that two workers can read and
 * then write produces states that are impossible to reach on purpose and
 * therefore impossible to reason about afterwards — an order that is COOKING
 * with a cancelled_at, a timeline with two branches.
 *
 * WHAT THIS CAN AND CANNOT SIMULATE. A single PHP process cannot run two
 * requests at literally the same instant, so these drive the same collision
 * sequentially through the real service with stale model instances, which is
 * what a losing worker actually holds. The row lock and the status re-read are
 * exercised for real; true parallel execution is not, and that is stated rather
 * than implied.
 */
final class OrderTransitionConcurrencyTest extends TestCase
{
    use RefreshDatabase;

    private User $rahul;

    private Restaurant $restaurant;

    private OrderTransitionService $transitions;

    protected function setUp(): void
    {
        parent::setUp();

        $this->rahul = CustomerFactory::rahul();
        $this->restaurant = RestaurantFixtures::nearRoute(0.4, 800, 'Highway Spice Kitchen');
        $this->transitions = app(OrderTransitionService::class);
    }

    /**
     * Both workers ask for ACCEPTED. One writes.
     *
     * The second holds a model loaded before the first ran, so its in-memory
     * status still says PLACED. If the service validated against that instead
     * of re-reading under the lock, it would decide the transition was legal
     * and write a second history row.
     */
    public function test_two_identical_transitions_produce_one_history_entry(): void
    {
        $order = $this->placedOrder();

        $stale = Order::query()->findOrFail($order->id);
        $this->assertSame(OrderStatus::Placed, $stale->status);

        $first = $this->transitions->transition($order, OrderStatus::Accepted, OrderTransitionActor::system());
        $second = $this->transitions->transition($stale, OrderStatus::Accepted, OrderTransitionActor::system());

        $this->assertTrue($first->applied);
        $this->assertFalse($second->applied, 'the second worker must not write');

        $this->assertSame(
            1,
            OrderStatusHistory::query()
                ->where('order_id', $order->id)
                ->where('to_status', OrderStatus::Accepted)
                ->count(),
        );

        $this->assertSame(
            1,
            OutboxEvent::query()->where('event_name', 'OrderAccepted')->count(),
        );

        // One transition, one version bump.
        $this->assertSame(2, (int) $order->refresh()->order_version);
    }

    /**
     * Two different legal transitions from one state. One of them stops being
     * legal the moment the other lands.
     *
     * ACCEPTED → COOKING and ACCEPTED → CANCELLED are both permitted. Whichever
     * arrives second is validated against the state the first one left behind,
     * so it is refused rather than applied on top — and the order does not end
     * up carrying both a cooking_started_at and a cancelled_at.
     */
    public function test_conflicting_transitions_leave_one_coherent_history(): void
    {
        $order = $this->placedOrder();

        $this->transitions->transition($order, OrderStatus::Accepted, OrderTransitionActor::system());

        $stale = Order::query()->findOrFail($order->id);

        $this->transitions->transition($order, OrderStatus::Cooking, OrderTransitionActor::system());

        try {
            $this->transitions->transition($stale, OrderStatus::Cancelled, OrderTransitionActor::system());
            $this->fail('cancelling an order already cooking must be refused');
        } catch (OrderTransitionNotAllowed) {
            // expected: COOKING has no edge to CANCELLED
        }

        $order->refresh();

        $this->assertSame(OrderStatus::Cooking, $order->status);
        $this->assertNotNull($order->cooking_started_at);

        // The impossible state this test exists to rule out.
        $this->assertNull($order->cancelled_at, 'an order cannot be cooking and cancelled at once');

        $this->assertSame(
            ['PLACED', 'ACCEPTED', 'COOKING'],
            $order->statusHistory()->get()
                ->map(fn (OrderStatusHistory $entry): string => $entry->to_status->value)
                ->all(),
        );
    }

    /**
     * The milestone is written once, by the transition that entered the state.
     *
     * A second attempt at READY returns early and writes nothing, so ready_at
     * still records when the food was actually ready rather than when the last
     * duplicate delivery arrived.
     */
    public function test_a_milestone_timestamp_is_not_rewritten_by_a_duplicate(): void
    {
        $order = $this->placedOrder();

        $this->transitions->transition($order, OrderStatus::Accepted, OrderTransitionActor::system());
        $this->transitions->transition($order, OrderStatus::Cooking, OrderTransitionActor::system());
        $this->transitions->transition($order, OrderStatus::Ready, OrderTransitionActor::system());

        $readyAt = $order->refresh()->ready_at;
        $this->assertNotNull($readyAt);

        $this->travel(5)->minutes();

        $this->transitions->transition($order, OrderStatus::Ready, OrderTransitionActor::system());

        $this->assertTrue(
            $readyAt->equalTo($order->refresh()->ready_at),
            'a duplicate must not move the moment the food became ready',
        );
    }

    private function placedOrder(): Order
    {
        $order = new Order;
        $order->customer_id = $this->rahul->id;
        $order->restaurant_id = $this->restaurant->id;
        $order->currency = 'INR';
        $order->items_subtotal_minor = 24_900;
        $order->payable_total_minor = 24_900;
        $order->status = OrderStatus::Placed;
        $order->order_number = 'FOTG-260918-CONC00001';
        $order->pickup_timezone = 'Asia/Kolkata';
        $order->placed_at = now()->toImmutable();
        $order->save();
        $order->refresh();

        $history = new OrderStatusHistory;
        $history->order_id = $order->id;
        $history->from_status = null;
        $history->to_status = OrderStatus::Placed;
        $history->source_type = OrderTransitionSource::System;
        $history->occurred_at = $order->placed_at;
        $history->save();

        return $order;
    }
}
