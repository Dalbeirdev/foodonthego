<?php

declare(strict_types=1);

namespace Tests\Feature\Api\Orders;

use App\Enums\OrderStatus;
use App\Enums\OrderTransitionSource;
use App\Exceptions\Orders\OrderTransitionNotAllowed;
use App\Exceptions\Orders\OrderTransitionNotPermittedForActor;
use App\Models\Order;
use App\Models\OrderStatusHistory;
use App\Models\OutboxEvent;
use App\Models\Restaurant;
use App\Models\User;
use App\Services\Orders\OrderTransitionActor;
use App\Services\Orders\OrderTransitionService;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Support\CustomerFactory;
use Tests\Support\RestaurantFixtures;
use Tests\TestCase;

/**
 * What may happen to an order, and what may not.
 *
 * The lifecycle is a graph, and a graph is exactly the kind of thing that
 * passes a happy-path test while permitting something nobody intended. So most
 * of this file asks for transitions that must be refused, and each refusal is
 * asked for by name rather than through a loop — a loop over "all illegal
 * pairs" proves the table is self-consistent, which it would be even if the
 * table were wrong.
 */
final class OrderTransitionTest extends TestCase
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

    // ------------------------------------------------------- the happy path

    public function test_an_order_walks_the_whole_lifecycle(): void
    {
        $order = $this->placedOrder();

        foreach ([OrderStatus::Accepted, OrderStatus::Cooking, OrderStatus::Ready, OrderStatus::PickedUp] as $step) {
            $result = $this->transitions->transition($order, $step, OrderTransitionActor::system());

            $this->assertTrue($result->applied);
        }

        $order->refresh();

        $this->assertSame(OrderStatus::PickedUp, $order->status);

        // Every milestone written, each exactly once.
        $this->assertNotNull($order->accepted_at);
        $this->assertNotNull($order->cooking_started_at);
        $this->assertNotNull($order->ready_at);
        $this->assertNotNull($order->picked_up_at);

        // Placement wrote one; four transitions wrote four more.
        $this->assertSame(5, $order->statusHistory()->count());
    }

    public function test_the_version_increments_once_per_transition(): void
    {
        $order = $this->placedOrder();

        $before = (int) $order->order_version;

        $this->transitions->transition($order, OrderStatus::Accepted, OrderTransitionActor::system());
        $this->transitions->transition($order, OrderStatus::Cooking, OrderTransitionActor::system());

        $this->assertSame($before + 2, (int) $order->refresh()->order_version);
    }

    // ---------------------------------------------------- illegal transitions

    public function test_placed_cannot_jump_to_ready(): void
    {
        $this->assertRefused(OrderStatus::Placed, OrderStatus::Ready);
    }

    public function test_placed_cannot_jump_to_picked_up(): void
    {
        $this->assertRefused(OrderStatus::Placed, OrderStatus::PickedUp);
    }

    public function test_accepted_cannot_jump_to_ready(): void
    {
        $this->assertRefused(OrderStatus::Accepted, OrderStatus::Ready);
    }

    public function test_cooking_cannot_go_back_to_accepted(): void
    {
        $this->assertRefused(OrderStatus::Cooking, OrderStatus::Accepted);
    }

    public function test_ready_cannot_go_back_to_cooking(): void
    {
        $this->assertRefused(OrderStatus::Ready, OrderStatus::Cooking);
    }

    // ------------------------------------------------- terminal-state defence

    public function test_a_picked_up_order_cannot_be_reopened(): void
    {
        $this->assertRefused(OrderStatus::PickedUp, OrderStatus::Ready);
    }

    public function test_a_rejected_order_cannot_be_accepted_after_all(): void
    {
        $this->assertRefused(OrderStatus::Rejected, OrderStatus::Accepted);
    }

    public function test_a_cancelled_order_cannot_start_cooking(): void
    {
        $this->assertRefused(OrderStatus::Cancelled, OrderStatus::Cooking);
    }

    /**
     * Cancellation stops where policy stops, not where convenience would.
     *
     * COOKING → CANCELLED is refused because nobody has decided who pays for
     * food already made. This asserts the absence deliberately, so that adding
     * the edge later is a decision somebody makes rather than a line somebody
     * adds while fixing something else.
     */
    public function test_an_order_already_cooking_cannot_be_cancelled(): void
    {
        $this->assertRefused(OrderStatus::Cooking, OrderStatus::Cancelled);
    }

    // ----------------------------------------------------------- duplicates

    public function test_asking_for_the_state_it_is_already_in_writes_nothing(): void
    {
        $order = $this->placedOrder();

        $this->transitions->transition($order, OrderStatus::Accepted, OrderTransitionActor::system());

        $version = (int) $order->refresh()->order_version;
        $history = $order->statusHistory()->count();
        $events = OutboxEvent::query()->count();

        $result = $this->transitions->transition($order, OrderStatus::Accepted, OrderTransitionActor::system());

        $this->assertFalse($result->applied);
        $this->assertSame($version, (int) $order->refresh()->order_version);
        $this->assertSame($history, $order->statusHistory()->count());
        $this->assertSame($events, OutboxEvent::query()->count());
    }

    public function test_a_duplicate_ready_leaves_one_timeline_entry(): void
    {
        $order = $this->orderAt(OrderStatus::Cooking);

        $this->transitions->transition($order, OrderStatus::Ready, OrderTransitionActor::system());
        $this->transitions->transition($order, OrderStatus::Ready, OrderTransitionActor::system());

        $this->assertSame(
            1,
            OrderStatusHistory::query()
                ->where('order_id', $order->id)
                ->where('to_status', OrderStatus::Ready)
                ->count(),
        );
    }

    /**
     * The unique index, not the early return.
     *
     * The check above proves the fast path. This proves what holds when the
     * fast path is wrong: writing the history row directly, as a second worker
     * that got past the status check would, must be refused by the database.
     */
    public function test_the_database_refuses_a_second_history_row_for_one_state(): void
    {
        $order = $this->placedOrder();

        $this->transitions->transition($order, OrderStatus::Accepted, OrderTransitionActor::system());

        $duplicate = new OrderStatusHistory;
        $duplicate->order_id = $order->id;
        $duplicate->from_status = OrderStatus::Placed;
        $duplicate->to_status = OrderStatus::Accepted;
        $duplicate->source_type = OrderTransitionSource::System;
        $duplicate->occurred_at = now()->toImmutable();

        $this->expectException(QueryException::class);

        $duplicate->save();
    }

    // -------------------------------------------------------------- tenancy

    public function test_a_restaurant_cannot_move_another_restaurants_order(): void
    {
        $order = $this->placedOrder();

        $elsewhere = RestaurantFixtures::nearRoute(0.5, 900, 'Roadside Grill');
        $this->assertNotSame($order->restaurant_id, $elsewhere->id);

        $operator = CustomerFactory::make('Priya', 'Nair', '+919999900222', 'operator@foodonthego.example');

        $this->expectException(OrderTransitionNotPermittedForActor::class);

        $this->transitions->transition(
            $order,
            OrderStatus::Accepted,
            OrderTransitionActor::restaurant($operator, $elsewhere->id),
        );
    }

    public function test_a_restaurant_may_move_its_own_order(): void
    {
        $order = $this->placedOrder();

        $operator = CustomerFactory::make('Vikram', 'Rao', '+919999900333', 'own@foodonthego.example');

        $result = $this->transitions->transition(
            $order,
            OrderStatus::Accepted,
            OrderTransitionActor::restaurant($operator, (int) $order->restaurant_id),
        );

        // The positive half. Without it, a service that refused everything
        // would satisfy the cross-tenant assertion above.
        $this->assertTrue($result->applied);
        $this->assertSame(OrderStatus::Accepted, $order->refresh()->status);
    }

    public function test_a_refused_transition_writes_no_history_and_no_event(): void
    {
        $order = $this->placedOrder();

        $history = $order->statusHistory()->count();
        $events = OutboxEvent::query()->count();

        try {
            $this->transitions->transition($order, OrderStatus::Ready, OrderTransitionActor::system());
            $this->fail('the transition should have been refused');
        } catch (OrderTransitionNotAllowed) {
            // expected
        }

        $this->assertSame($history, $order->statusHistory()->count());
        $this->assertSame($events, OutboxEvent::query()->count());
        $this->assertSame(OrderStatus::Placed, $order->refresh()->status);
    }

    // --------------------------------------------------------------- events

    public function test_each_transition_queues_exactly_one_domain_event(): void
    {
        $order = $this->placedOrder();

        $this->transitions->transition($order, OrderStatus::Accepted, OrderTransitionActor::system());

        $this->assertSame(
            1,
            OutboxEvent::query()->where('event_name', 'OrderAccepted')->count(),
        );

        $event = OutboxEvent::query()->where('event_name', 'OrderAccepted')->firstOrFail();

        // Identifiers only, as Module 16 established.
        $this->assertEqualsCanonicalizing(
            ['order_uuid', 'restaurant_id', 'status', 'order_version'],
            array_keys((array) $event->payload),
        );
    }

    // -------------------------------------------------------------- history

    public function test_placement_writes_the_first_history_entry(): void
    {
        $order = $this->placedOrder();

        $first = $order->statusHistory()->first();

        $this->assertNotNull($first);
        $this->assertNull($first->from_status);
        $this->assertSame(OrderStatus::Placed, $first->to_status);
        $this->assertSame(OrderTransitionSource::System, $first->source_type);
    }

    public function test_the_current_status_always_matches_the_latest_history_entry(): void
    {
        $order = $this->placedOrder();

        $this->transitions->transition($order, OrderStatus::Accepted, OrderTransitionActor::system());
        $this->transitions->transition($order, OrderStatus::Cooking, OrderTransitionActor::system());

        $order->refresh();

        // Asked of the database rather than fetched-then-discarded. The
        // relation orders by (occurred_at, id) ascending, so BOTH columns are
        // inverted here -- reversing only the timestamp would leave two rows
        // written in the same second to be separated by whatever the storage
        // engine felt like, which is the tie-break the relation exists to pin.
        $latest = $order->statusHistory()
            ->reorder('occurred_at', 'desc')
            ->orderBy('id', 'desc')
            ->first();

        $this->assertSame($order->status, $latest->to_status);
    }

    /**
     * The internal reason stays internal.
     *
     * Both columns exist, and only one of them is ever read by a customer
     * presenter. Asserting they hold different values is what makes a later
     * change that reads the wrong one visible.
     */
    public function test_an_internal_reason_and_a_customer_note_are_different_fields(): void
    {
        $order = $this->placedOrder();

        $this->transitions->transition(
            $order,
            OrderStatus::Rejected,
            OrderTransitionActor::system(),
            reasonCode: 'INVENTORY_EXCEPTION_INTERNAL',
            customerSafeNote: 'An item became unavailable.',
        );

        $entry = OrderStatusHistory::query()
            ->where('order_id', $order->id)
            ->where('to_status', OrderStatus::Rejected)
            ->firstOrFail();

        $this->assertSame('INVENTORY_EXCEPTION_INTERNAL', $entry->reason_code);
        $this->assertSame('An item became unavailable.', $entry->customer_safe_note);
        $this->assertSame('An item became unavailable.', $order->refresh()->customer_safe_reason);
    }

    // -------------------------------------------------------------- helpers

    private function assertRefused(OrderStatus $from, OrderStatus $to): void
    {
        $order = $this->orderAt($from);

        $this->expectException(OrderTransitionNotAllowed::class);

        $this->transitions->transition($order, $to, OrderTransitionActor::system());
    }

    /**
     * An order parked in a given state.
     *
     * Written directly rather than walked there, because a test for
     * PICKED_UP → READY should fail if that edge exists, not if some earlier
     * edge is missing.
     */
    private function orderAt(OrderStatus $status): Order
    {
        $order = $this->placedOrder();

        $order->status = $status;
        $order->save();

        return $order->refresh();
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
        $order->order_number = 'FOTG-260918-TEST000001';
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
