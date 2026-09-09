<?php

declare(strict_types=1);

namespace Tests\Feature\Api\Orders;

use App\Enums\OrderStatus;
use App\Enums\OrderTransitionSource;
use App\Models\Order;
use App\Models\OrderStatusHistory;
use App\Models\Restaurant;
use App\Models\User;
use App\Services\Orders\OrderTransitionActor;
use App\Services\Orders\OrderTransitionService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Support\CustomerFactory;
use Tests\Support\RestaurantFixtures;
use Tests\TestCase;

/**
 * What a customer is shown about their order, and what they are not.
 *
 * Two properties get most of the attention here. The first is that the timeline
 * tells the truth about the future: an upcoming step carries no timestamp, and
 * a rejected order shows no steps that are never going to happen. The second is
 * that nothing internal crosses the boundary — no actor, no reason code, no
 * correlation id — because the history table carries all three and the
 * presenter is the only thing standing between them and a stranger's phone.
 */
final class OrderTrackingApiTest extends TestCase
{
    use RefreshDatabase;

    private User $rahul;

    private User $ananya;

    private Restaurant $restaurant;

    private OrderTransitionService $transitions;

    protected function setUp(): void
    {
        parent::setUp();

        $this->rahul = CustomerFactory::rahul();
        $this->ananya = CustomerFactory::ananya();
        $this->restaurant = RestaurantFixtures::nearRoute(0.4, 800, 'Highway Spice Kitchen');
        $this->transitions = app(OrderTransitionService::class);
    }

    // -------------------------------------------------------------- timeline

    public function test_a_placed_order_shows_one_current_step_and_four_upcoming(): void
    {
        $order = $this->placedOrder();

        $timeline = $this->trackingFor($order)['timeline'];

        $this->assertSame(
            ['PLACED', 'ACCEPTED', 'COOKING', 'READY', 'PICKED_UP'],
            array_column($timeline, 'status'),
        );

        $this->assertSame(
            ['CURRENT', 'UPCOMING', 'UPCOMING', 'UPCOMING', 'UPCOMING'],
            array_column($timeline, 'state'),
        );

        $this->assertNotNull($timeline[0]['occurred_at']);

        /*
         | THE ASSERTION THIS FILE EXISTS FOR.
         |
         | A step that has not happened must carry no time. A fabricated
         | timestamp on an upcoming step is the one error a customer cannot
         | detect: it tells them their food was ready at an hour it was not,
         | and they have no way to know otherwise.
         */
        foreach (array_slice($timeline, 1) as $step) {
            $this->assertNull($step['occurred_at'], $step['status'].' must carry no time');
        }
    }

    public function test_a_cooking_order_shows_two_completed_steps(): void
    {
        $order = $this->placedOrder();

        $this->transitions->transition($order, OrderStatus::Accepted, OrderTransitionActor::system());
        $this->transitions->transition($order, OrderStatus::Cooking, OrderTransitionActor::system());

        $timeline = $this->trackingFor($order)['timeline'];

        $this->assertSame(
            ['COMPLETED', 'COMPLETED', 'CURRENT', 'UPCOMING', 'UPCOMING'],
            array_column($timeline, 'state'),
        );

        $this->assertNotNull($timeline[1]['occurred_at']);
        $this->assertNotNull($timeline[2]['occurred_at']);
    }

    public function test_a_picked_up_order_shows_every_step_complete(): void
    {
        $order = $this->walkTo(OrderStatus::PickedUp);

        $timeline = $this->trackingFor($order)['timeline'];

        $this->assertSame(
            ['COMPLETED', 'COMPLETED', 'COMPLETED', 'COMPLETED', 'CURRENT'],
            array_column($timeline, 'state'),
        );

        $this->assertFalse($this->trackingFor($order)['is_active']);
    }

    /**
     * A refused order shows no future it is not going to have.
     *
     * The branch is the whole reason the timeline is built by a service rather
     * than by a loop over the happy path. Leaving Cooking and Ready sitting
     * ahead of a rejection tells a customer their refused order is queued to
     * be prepared.
     */
    public function test_a_rejected_order_shows_no_cooking_or_ready_step(): void
    {
        $order = $this->placedOrder();

        $this->transitions->transition(
            $order,
            OrderStatus::Rejected,
            OrderTransitionActor::system(),
            reasonCode: 'INVENTORY_EXCEPTION_INTERNAL',
            customerSafeNote: 'An item became unavailable.',
        );

        $tracking = $this->trackingFor($order);
        $statuses = array_column($tracking['timeline'], 'status');

        $this->assertSame(['PLACED', 'REJECTED'], $statuses);
        $this->assertNotContains('COOKING', $statuses);
        $this->assertNotContains('READY', $statuses);
        $this->assertNotContains('PICKED_UP', $statuses);

        $this->assertSame('EXCEPTION', $tracking['timeline'][1]['state']);
        $this->assertSame('An item became unavailable.', $tracking['customer_safe_reason']);
    }

    public function test_a_cancelled_order_keeps_the_steps_it_reached(): void
    {
        $order = $this->placedOrder();

        $this->transitions->transition($order, OrderStatus::Accepted, OrderTransitionActor::system());
        $this->transitions->transition($order, OrderStatus::Cancelled, OrderTransitionActor::system());

        $statuses = array_column($this->trackingFor($order)['timeline'], 'status');

        $this->assertSame(['PLACED', 'ACCEPTED', 'CANCELLED'], $statuses);
    }

    // ------------------------------------------------------------- privacy

    /**
     * Nothing the history table knows about people reaches the customer.
     *
     * Asserted against the serialised response rather than field by field, so
     * a value that appears somewhere nobody thought to check is still caught.
     */
    public function test_the_tracking_response_carries_nothing_internal(): void
    {
        $order = $this->placedOrder();

        $operator = CustomerFactory::make('Priya', 'Nair', '+919999900222', 'operator@foodonthego.example');

        $this->transitions->transition(
            $order,
            OrderStatus::Rejected,
            OrderTransitionActor::restaurant($operator, (int) $order->restaurant_id),
            reasonCode: 'STAFF_SHORTAGE_INTERNAL',
            customerSafeNote: 'Restaurant is unable to fulfil this order.',
            correlationId: '11111111-2222-3333-4444-555555555555',
        );

        $body = json_encode($this->trackingFor($order), JSON_THROW_ON_ERROR);

        // The guard: the fixture really did carry these, so their absence
        // below is a property of the presenter rather than of the fixture.
        $entry = OrderStatusHistory::query()
            ->where('order_id', $order->id)
            ->where('to_status', OrderStatus::Rejected)
            ->firstOrFail();

        $this->assertSame('STAFF_SHORTAGE_INTERNAL', $entry->reason_code);
        $this->assertSame((int) $operator->getKey(), (int) $entry->actor_id);

        $this->assertStringNotContainsString('STAFF_SHORTAGE_INTERNAL', $body);
        $this->assertStringNotContainsString('operator@foodonthego.example', $body);
        $this->assertStringNotContainsString('11111111-2222-3333-4444-555555555555', $body);
        $this->assertStringNotContainsString('Priya', $body);
        $this->assertStringNotContainsString('actor_id', $body);
    }

    public function test_the_tracking_response_never_carries_the_pickup_code(): void
    {
        $order = $this->placedOrder();

        $tracking = $this->trackingFor($order);

        // It says a credential exists. It does not say what it is.
        $this->assertTrue($tracking['pickup_credential']['available']);

        $body = json_encode($tracking, JSON_THROW_ON_ERROR);

        $this->assertStringNotContainsString('qr_payload', $body);
        $this->assertStringNotContainsString('foodonthego://pickup', $body);
    }

    // ------------------------------------------------------------- security

    public function test_another_customer_cannot_track_this_order(): void
    {
        $order = $this->placedOrder();

        $this->as($this->ananya)
            ->getJson('/api/v1/customer/orders/'.$order->uuid)
            ->assertNotFound();
    }

    public function test_an_order_number_is_not_an_identifier_for_tracking(): void
    {
        $order = $this->placedOrder();

        $this->as($this->rahul)
            ->getJson('/api/v1/customer/orders/'.$order->order_number)
            ->assertNotFound();
    }

    /**
     * No customer route writes a status.
     *
     * ASSERTED, NOT ASSUMED. The rule that a phone displays order state and
     * does not decide it is only worth anything if adding such a route fails a
     * test. This walks the registered routes rather than trying a list of
     * guessed URLs, so a route named something nobody predicted is still
     * caught.
     */
    public function test_no_customer_route_can_change_an_order_status(): void
    {
        $offenders = [];

        foreach (app('router')->getRoutes() as $route) {
            $uri = $route->uri();

            if (! str_contains($uri, 'customer/orders')) {
                continue;
            }

            $writes = array_intersect($route->methods(), ['POST', 'PUT', 'PATCH', 'DELETE']);

            if ($writes === []) {
                continue;
            }

            // Module 15's payment routes legitimately write, and neither of
            // them touches a fulfilment status.
            if (str_contains($uri, 'payment')) {
                continue;
            }

            $offenders[] = implode('|', $writes).' '.$uri;
        }

        $this->assertSame([], $offenders, 'a customer route can write to an order');
    }

    // -------------------------------------------------------- the orders tab

    public function test_the_orders_tab_separates_active_from_finished(): void
    {
        $active = $this->placedOrder();
        $finished = $this->walkTo(OrderStatus::PickedUp, 'FOTG-260918-TEST000002');

        $body = $this->as($this->rahul)
            ->getJson('/api/v1/customer/orders')
            ->assertOk()
            ->json('data');

        $this->assertSame([$active->uuid], array_column($body['active'], 'id'));
        $this->assertSame([$finished->uuid], array_column($body['past'], 'id'));
    }

    /**
     * The one a customer must collect next, first.
     *
     * A NEGATIVE CONTROL EXPOSED THE FIRST VERSION OF THIS TEST. It created the
     * later pickup first, so the newer order also had the sooner pickup and
     * every plausible sort produced the same list -- sorting by id descending
     * passed it just as well as sorting by pickup time. The two orderings have
     * to disagree, or the assertion is about nothing.
     *
     * So the order placed FIRST is the one to be collected SOONEST: by id it
     * comes first ascending and last descending, and only pickup time puts it
     * where the assertion expects.
     */
    public function test_two_live_orders_are_listed_soonest_pickup_first(): void
    {
        $sooner = $this->placedOrder('FOTG-260918-TEST000003');
        $sooner->pickup_start_at = now()->addHour();
        $sooner->save();

        $later = $this->placedOrder('FOTG-260918-TEST000004');
        $later->pickup_start_at = now()->addHours(3);
        $later->save();

        // The guard that makes the assertion meaningful: id order and pickup
        // order genuinely disagree, so only one of them can pass below.
        $this->assertLessThan($later->id, $sooner->id);

        $active = $this->as($this->rahul)
            ->getJson('/api/v1/customer/orders')
            ->assertOk()
            ->json('data.active');

        $this->assertSame(
            [$sooner->uuid, $later->uuid],
            array_column($active, 'id'),
            'the order a customer must collect next comes first',
        );
    }

    // ---------------------------------------------------------- cost control

    /**
     * Twenty refreshes cost twenty internal reads and nothing else.
     *
     * The provider bindings in this project refuse every call, so a tracking
     * refresh that reached Razorpay or a routing provider would throw rather
     * than quietly cost money — which makes this test both a cost check and a
     * correctness one.
     */
    public function test_twenty_refreshes_touch_no_external_provider(): void
    {
        $order = $this->placedOrder();

        for ($i = 0; $i < 20; $i++) {
            $this->as($this->rahul)
                ->getJson('/api/v1/customer/orders/'.$order->uuid)
                ->assertOk();
        }
    }

    public function test_the_response_carries_a_version_and_a_server_clock(): void
    {
        $order = $this->placedOrder();

        $before = $this->trackingFor($order);

        $this->transitions->transition($order, OrderStatus::Accepted, OrderTransitionActor::system());

        $after = $this->trackingFor($order);

        $this->assertGreaterThan($before['order_version'], $after['order_version']);
        $this->assertNotNull($after['server_time']);
    }

    // -------------------------------------------------------------- helpers

    /** @return array<string, mixed> */
    private function trackingFor(Order $order): array
    {
        return $this->as($this->rahul)
            ->getJson('/api/v1/customer/orders/'.$order->uuid)
            ->assertOk()
            ->json('data');
    }

    private function walkTo(OrderStatus $status, string $number = 'FOTG-260918-TEST000009'): Order
    {
        $order = $this->placedOrder($number);

        foreach ([OrderStatus::Accepted, OrderStatus::Cooking, OrderStatus::Ready, OrderStatus::PickedUp] as $step) {
            $this->transitions->transition($order, $step, OrderTransitionActor::system());

            if ($step === $status) {
                break;
            }
        }

        return $order->refresh();
    }

    private function placedOrder(string $number = 'FOTG-260918-TEST000001'): Order
    {
        $order = new Order;
        $order->customer_id = $this->rahul->id;
        $order->restaurant_id = $this->restaurant->id;
        $order->currency = 'INR';
        $order->items_subtotal_minor = 24_900;
        $order->payable_total_minor = 24_900;
        $order->status = OrderStatus::Placed;
        $order->order_number = $number;
        $order->pickup_timezone = 'Asia/Kolkata';
        $order->pickup_start_at = now()->addHours(2);
        $order->pickup_end_at = now()->addHours(2)->addMinutes(10);
        $order->placed_at = now();
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

    private function as(User $customer): self
    {
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', 'Bearer '.CustomerFactory::tokenFor($customer));
    }
}
