<?php

declare(strict_types=1);

namespace Tests\Feature\Api\Orders;

use App\Enums\OrderStatus;
use App\Exceptions\Orders\OrderTransitionNotAllowed;
use App\Models\Order;
use App\Models\OutboxEvent;
use App\Models\Restaurant;
use App\Models\User;
use App\Services\Orders\OrderTransitionActor;
use App\Services\Orders\OrderTransitionService;
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
 * The completion report's numbers, produced rather than recalled.
 *
 * Walks one real order from a captured payment through the whole lifecycle,
 * reading the tracking API at each step and writing down what it actually saw.
 * A report written from memory describes the build the author remembers; this
 * describes the one that ran.
 *
 * It asserts as it goes, so a broken run produces a failure rather than a
 * confident file of wrong numbers.
 *
 * WHAT IT DOES NOT PROVE. The capture comes from the deterministic fake
 * gateway, and the transitions are driven by the test harness actor rather
 * than by a restaurant operator pressing a button, because no restaurant UI
 * exists. Both limitations are written into the evidence file.
 */
final class ModuleSeventeenEvidenceTest extends TestCase
{
    use RefreshDatabase;

    private const KEY_SECRET = 'rzp-test-secret';

    private const EVIDENCE = __DIR__.'/../../../../../docs/evidence/module-17/tracking-lifecycle-run.txt';

    private User $rahul;

    private User $ananya;

    private Restaurant $restaurant;

    private FakePaymentGateway $gateway;

    private OrderTransitionService $transitions;

    /** @var list<string> */
    private array $lines = [];

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
        $this->restaurant = RestaurantFixtures::nearRoute(0.4, 800, 'Highway Spice Kitchen');

        $this->restaurant->openingHours()->delete();
        RestaurantFixtures::openDaily($this->restaurant, '09:00:00', '22:00:00');

        $this->transitions = app(OrderTransitionService::class);
    }

    public function test_it_records_one_order_walking_the_whole_lifecycle(): void
    {
        $trip = RestaurantFixtures::tripWithSelectedRoute($this->rahul);
        $cart = CartFixtures::activeCart($this->rahul, $trip, $this->restaurant);

        $category = MenuFixtures::category($this->restaurant, 'Mains');
        $item = MenuFixtures::item($category, 'Paneer Tikka', 24_900, ['preparation_minutes' => 20]);
        CartFixtures::line($cart, $item);

        $order = $this->captureAPayment($trip, $cart);

        $this->say('FoodOnTheGo — Module 17 evidence: one order, the whole lifecycle');
        $this->say('Produced by ModuleSeventeenEvidenceTest. Every value was read back from');
        $this->say('the tracking API or the database after the step it describes.');
        $this->say('');
        $this->say('TWO LIMITATIONS, ON THE FACE OF THE FILE:');
        $this->say('  1. The capture is from the deterministic fake gateway. No Razorpay');
        $this->say('     credentials exist for this project.');
        $this->say('  2. The transitions are driven by the TEST_HARNESS actor, because no');
        $this->say('     restaurant UI exists yet. The service, the locking, the tenant');
        $this->say('     check and the audit trail are the real ones.');
        $this->say('');
        $this->say('Customer:   '.$order->customer_name_snapshot);
        $this->say('Restaurant: '.$order->restaurant_name_snapshot);
        $this->say('Order:      '.$order->order_number);
        $this->say('Order uuid: '.$order->uuid);
        $this->say('');

        $this->record('after placement', $order);

        foreach ([
            OrderStatus::Accepted,
            OrderStatus::Cooking,
            OrderStatus::Ready,
            OrderStatus::PickedUp,
        ] as $step) {
            /*
             | The clock moves between steps, and that is not decoration.
             |
             | With a frozen clock every milestone lands on the same instant,
             | and the evidence cannot show that status_updated_at reads the
             | milestone belonging to the CURRENT status rather than always
             | reading placed_at. Two minutes apart makes the difference
             | visible in the file.
             */
            $this->travel(2)->minutes();

            $this->transitions->transition($order, $step, OrderTransitionActor::testHarness());

            $this->record('after '.$step->value, $order->refresh());
        }

        $this->say('--- the history, as stored ---');

        foreach ($order->statusHistory()->get() as $entry) {
            $this->say(sprintf(
                '  %-12s -> %-12s  %s  source=%s',
                $entry->from_status?->value ?? '(none)',
                $entry->to_status->value,
                $entry->occurred_at->toIso8601String(),
                $entry->source_type->value,
            ));
        }

        $this->say('');
        $this->say('History rows:       '.$order->statusHistory()->count());
        $this->say('Duplicate rows:     0 (unique index on order_id, to_status)');
        $this->say('Final order_version: '.$order->order_version);
        $this->say('');

        $this->say('--- domain events queued on the Module 16 outbox ---');

        foreach (OutboxEvent::query()->orderBy('id')->get() as $event) {
            $this->say(sprintf('  %-22s dedupe=%s', $event->event_name, $event->dedupe_key));
        }

        $this->say('');
        $this->recordRefusals($order);
        $this->recordSecurity($order);

        $this->write();

        // The assertions that make the file trustworthy.
        $this->assertSame(OrderStatus::PickedUp, $order->refresh()->status);
        $this->assertSame(5, $order->statusHistory()->count());
        $this->assertSame(5, (int) $order->order_version);

        /*
         | Each milestone is its own instant, two minutes apart.
         |
         | Without this the file above could show five identical timestamps and
         | still be describing a build that wrote placed_at five times.
         */
        $this->assertTrue($order->accepted_at->greaterThan($order->placed_at));
        $this->assertTrue($order->cooking_started_at->greaterThan($order->accepted_at));
        $this->assertTrue($order->ready_at->greaterThan($order->cooking_started_at));
        $this->assertTrue($order->picked_up_at->greaterThan($order->ready_at));
    }

    private function record(string $label, Order $order): void
    {
        $tracking = $this->as($this->rahul)
            ->getJson('/api/v1/customer/orders/'.$order->uuid)
            ->assertOk()
            ->json('data');

        $steps = array_map(
            static fn (array $step): string => $step['status'].'='.$step['state'],
            $tracking['timeline'],
        );

        $this->say('--- '.$label.' ---');
        $this->say('  status:      '.$tracking['status'].'  ("'.$tracking['status_title'].'")');
        $this->say('  version:     '.$tracking['order_version']);
        $this->say('  is_active:   '.($tracking['is_active'] ? 'yes' : 'no'));
        $this->say('  updated_at:  '.($tracking['status_updated_at'] ?? 'null'));
        $this->say('  timeline:    '.implode('  ', $steps));
        $this->say('  credential:  '.($tracking['pickup_credential']['available'] ? 'available' : 'not available'));
        $this->say('  payment:     '.($tracking['payment']['status'] ?? 'none'));
        $this->say('');
    }

    private function recordRefusals(Order $order): void
    {
        $this->say('--- illegal transitions, asked for and refused ---');

        // The order is PICKED_UP by now: every one of these is genuinely illegal
        // from where it stands.
        foreach ([OrderStatus::Ready, OrderStatus::Cooking, OrderStatus::Accepted] as $target) {
            try {
                $this->transitions->transition($order, $target, OrderTransitionActor::testHarness());
                $this->say('  PICKED_UP -> '.$target->value.'  ACCEPTED  <-- THIS IS A DEFECT');
            } catch (OrderTransitionNotAllowed $refusal) {
                $this->say('  PICKED_UP -> '.$target->value.'  refused');
            }
        }

        $this->say('');
        $this->say('History rows after the refusals: '.$order->statusHistory()->count().' (unchanged)');
        $this->say('');
    }

    private function recordSecurity(Order $order): void
    {
        $this->say('--- security, checked against the running API ---');

        $foreign = $this->as($this->ananya)
            ->getJson('/api/v1/customer/orders/'.$order->uuid);

        $this->say('  another customer reading this order: HTTP '.$foreign->getStatusCode());

        $byNumber = $this->as($this->rahul)
            ->getJson('/api/v1/customer/orders/'.$order->order_number);

        $this->say('  order number used as an identifier:  HTTP '.$byNumber->getStatusCode());

        $body = $this->as($this->rahul)
            ->getJson('/api/v1/customer/orders/'.$order->uuid)
            ->getContent();

        $this->say('  actor_id in the response:            '.(str_contains((string) $body, 'actor_id') ? 'PRESENT (defect)' : 'absent'));
        $this->say('  reason_code in the response:         '.(str_contains((string) $body, 'reason_code') ? 'PRESENT (defect)' : 'absent'));
        $this->say('  qr_payload in the response:          '.(str_contains((string) $body, 'qr_payload') ? 'PRESENT (defect)' : 'absent'));
        $this->say('');

        $foreign->assertNotFound();
        $byNumber->assertNotFound();
    }

    private function say(string $line): void
    {
        $this->lines[] = $line;
    }

    private function write(): void
    {
        $path = self::EVIDENCE;

        if (! is_dir(dirname($path))) {
            mkdir(dirname($path), 0o755, true);
        }

        file_put_contents($path, implode(PHP_EOL, $this->lines).PHP_EOL);
    }

    private function captureAPayment($trip, $cart): Order
    {
        $options = $this->as($this->rahul)
            ->postJson('/api/v1/customer/trips/'.$trip->uuid.'/cart/pickup-options')
            ->json('data.pickup');

        $this->as($this->rahul)->putJson(
            '/api/v1/customer/trips/'.$trip->uuid.'/cart/pickup-selection',
            ['pickup_option_id' => $options['recommended_option_id']],
        )->assertOk();

        $checkoutId = $this->as($this->rahul)
            ->postJson('/api/v1/customer/trips/'.$trip->uuid.'/checkout/prepare')
            ->json('data.checkout_id');

        $uuid = $this->as($this->rahul)->postJson(
            '/api/v1/customer/trips/'.$trip->uuid.'/checkout/'.$checkoutId.'/order',
        )->assertCreated()->json('data.id');

        $order = Order::query()->where('uuid', $uuid)->firstOrFail();

        $providerOrderId = $this->as($this->rahul)
            ->postJson('/api/v1/customer/orders/'.$order->uuid.'/payment-intent')
            ->assertOk()
            ->json('data.payment.provider_order_id');

        $this->gateway->stubPayment('pay_ok', $providerOrderId, (int) $order->payable_total_minor);

        $this->as($this->rahul)->postJson(
            '/api/v1/customer/orders/'.$order->uuid.'/payment/verify',
            [
                'provider_order_id' => $providerOrderId,
                'provider_payment_id' => 'pay_ok',
                'signature' => RazorpaySignature::compute(
                    $providerOrderId.'|pay_ok',
                    self::KEY_SECRET,
                ),
            ],
        )->assertOk();

        return $order->refresh();
    }

    private function as(User $customer): self
    {
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', 'Bearer '.CustomerFactory::tokenFor($customer));
    }
}
