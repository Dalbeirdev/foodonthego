<?php

declare(strict_types=1);

namespace Tests\Feature\Api\Customer;

use App\Enums\PickupSelectionStatus;
use App\Enums\PreCheckoutIssue;
use App\Models\Cart;
use App\Models\MenuItem;
use App\Models\Restaurant;
use App\Models\Trip;
use App\Models\User;
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Schema;
use Tests\Support\CartFixtures;
use Tests\Support\CustomerFactory;
use Tests\Support\MenuFixtures;
use Tests\Support\RestaurantFixtures;
use Tests\TestCase;

/**
 * The last check before a checkout that does not exist yet.
 *
 * The specification names six things this endpoint must never say yes over: an
 * unreviewed price rise, a sold-out line, a paused kitchen, a stale route, a
 * stale pickup selection, and no selection at all. There is a test below for
 * each, and each asserts `ready_for_checkout` is false rather than merely that
 * an issue was listed — a response that reports a problem and still says yes is
 * the failure worth guarding against.
 */
final class PreCheckoutValidationApiTest extends TestCase
{
    use RefreshDatabase;

    private User $rahul;

    private Trip $trip;

    private Restaurant $restaurant;

    private Cart $cart;

    private MenuItem $item;

    protected function setUp(): void
    {
        parent::setUp();

        Cache::flush();

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

    // --- plumbing ------------------------------------------------------------

    private function as(User $customer): self
    {
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', 'Bearer '.CustomerFactory::tokenFor($customer));
    }

    private function url(?Trip $trip = null): string
    {
        return '/api/v1/customer/trips/'.($trip ?? $this->trip)->uuid.'/cart/pre-checkout-validate';
    }

    /** @return array<string, mixed> */
    private function validate(): array
    {
        $response = $this->as($this->rahul)->postJson($this->url());

        $response->assertOk();

        return $response->json('data');
    }

    /** Chooses the recommended time, the way the screen would. */
    private function choosePickupTime(): void
    {
        $options = $this->as($this->rahul)
            ->postJson('/api/v1/customer/trips/'.$this->trip->uuid.'/cart/pickup-options')
            ->json('data.pickup.options');

        $this->as($this->rahul)->putJson(
            '/api/v1/customer/trips/'.$this->trip->uuid.'/cart/pickup-selection',
            ['pickup_option_id' => $options[0]['id']],
        )->assertOk();
    }

    /** @param array<string, mixed> $data */
    private function issues(array $data): array
    {
        return array_column($data['issues'], 'code');
    }

    /** @param array<string, mixed> $data */
    private function assertBlocked(array $data, PreCheckoutIssue $issue): void
    {
        $this->assertFalse($data['ready_for_checkout'], 'the server said yes anyway');

        // The status appears twice in this response — once at the top level and
        // once inside the pickup block — and a screen may read either. Two
        // fields that can disagree is one field too many.
        $this->assertSame(
            $data['selection_status'],
            $data['pickup']['selection']['status'],
            'the two reported selection statuses disagree',
        );
        $this->assertContains($issue->value, $this->issues($data));

        foreach ($data['issues'] as $listed) {
            if ($listed['code'] === $issue->value) {
                $this->assertTrue($listed['blocking'], $issue->value.' was listed but not blocking');
            }
        }
    }

    // --- the one case that says yes ------------------------------------------

    public function test_a_complete_order_with_a_chosen_time_is_ready(): void
    {
        $this->choosePickupTime();

        $data = $this->validate();

        $this->assertTrue($data['ready_for_checkout']);
        $this->assertSame([], $data['issues']);
        $this->assertSame(PickupSelectionStatus::Selected->value, $data['selection_status']);

        // Both halves are in the response, so a screen can show what was
        // checked rather than only what failed.
        $this->assertTrue($data['revalidation']['can_proceed']);
        $this->assertTrue($data['pickup']['is_feasible']);
    }

    // --- the six the specification names -------------------------------------

    public function test_it_never_says_yes_without_a_pickup_time(): void
    {
        $data = $this->validate();

        $this->assertBlocked($data, PreCheckoutIssue::NoPickupTimeSelected);
        $this->assertSame(PickupSelectionStatus::None->value, $data['selection_status']);
    }

    public function test_it_never_says_yes_over_a_price_rise(): void
    {
        $this->choosePickupTime();

        $this->item->forceFill(['base_price_minor' => 31_900])->save();

        $data = $this->validate();

        // The customer's way past this is to look at the new figure and add the
        // dish again. Nothing here accepts a higher price on their behalf.
        $this->assertBlocked($data, PreCheckoutIssue::PriceIncreased);
    }

    public function test_it_never_says_yes_over_a_sold_out_line(): void
    {
        $this->choosePickupTime();

        $this->item->forceFill(['stock_status' => 'SOLD_OUT'])->save();

        $data = $this->validate();

        $this->assertBlocked($data, PreCheckoutIssue::LineUnavailable);
    }

    public function test_it_never_says_yes_with_a_paused_kitchen(): void
    {
        $this->choosePickupTime();

        $this->restaurant->forceFill(['is_accepting_orders' => false])->save();

        $data = $this->validate();

        $this->assertBlocked($data, PreCheckoutIssue::RestaurantNotAcceptingOrders);

        // Reported once. The cart's revalidation notices a paused kitchen and
        // so does the planner, and a screen listing it twice looks broken.
        $this->assertCount(
            1,
            array_filter(
                $this->issues($data),
                static fn (string $code): bool => $code === PreCheckoutIssue::RestaurantNotAcceptingOrders->value,
            ),
        );
    }

    public function test_it_never_says_yes_on_a_stale_route(): void
    {
        $this->choosePickupTime();

        // Older than ROUTE_ESTIMATE_MAX_AGE_SECONDS.
        $this->trip->selectedRoute->forceFill([
            'calculated_at' => CarbonImmutable::parse('2026-09-07T06:30:00Z')->subHours(2),
        ])->save();

        $data = $this->validate();

        $this->assertBlocked($data, PreCheckoutIssue::RouteStale);
        $this->assertTrue($data['pickup']['requires_route_refresh']);
    }

    public function test_it_never_says_yes_on_a_stale_pickup_selection(): void
    {
        $this->choosePickupTime();

        // The customer adds something after choosing a time.
        $this->cart->recordContentChange();

        $data = $this->validate();

        $this->assertBlocked($data, PreCheckoutIssue::PickupTimeStale);
        $this->assertSame(PickupSelectionStatus::Stale->value, $data['selection_status']);
    }

    // --- the derived status --------------------------------------------------

    public function test_a_selection_whose_window_has_passed_reads_invalid(): void
    {
        $this->choosePickupTime();

        // The route is held fresh for the length of this test, deliberately.
        //
        // With the shipped fifteen-minute route age, three hours of clock also
        // ages the route out, and ROUTE_STALE fires first — which is the right
        // precedence and not what this test is about. In production INVALID is
        // therefore the narrow case: a window that passes while the route is
        // still current. Reachable, and worth pinning, because the moment a
        // future module refreshes routes in the background it stops being
        // narrow at all.
        config(['foodonthego.pickup.route_estimate_max_age_seconds' => 86_400]);

        // The clock moves past the chosen window. Nothing about the cart is
        // wrong; this is the most ordinary way a plan expires.
        $this->travelTo(CarbonImmutable::parse('2026-09-07T06:30:00Z')->addHours(3));

        $data = $this->validate();

        $this->assertBlocked($data, PreCheckoutIssue::PickupTimeInvalid);
        $this->assertSame(PickupSelectionStatus::Invalid->value, $data['selection_status']);
    }

    public function test_the_stored_status_is_never_rewritten_by_validating(): void
    {
        $this->choosePickupTime();

        $this->cart->recordContentChange();

        $before = Cart::query()->whereKey($this->cart->id)->firstOrFail();

        $this->assertSame(PickupSelectionStatus::Stale->value, $this->validate()['selection_status']);

        $after = Cart::query()->whereKey($this->cart->id)->firstOrFail();

        // STALE is a conclusion about the customer's intent, not a replacement
        // for it. The column still records what they chose; a validator that
        // corrected the thing it was validating would disagree with itself on
        // the second run.
        $this->assertSame(
            PickupSelectionStatus::Selected,
            $after->pickup_selection_status,
            'validating rewrote the stored selection',
        );
        $this->assertEquals($before->requested_pickup_start_at, $after->requested_pickup_start_at);
        $this->assertEquals($before->pickup_planning_fingerprint, $after->pickup_planning_fingerprint);
        $this->assertEquals($before->updated_at, $after->updated_at);
    }

    // --- what does not block -------------------------------------------------

    public function test_a_price_that_has_fallen_is_reported_and_does_not_block(): void
    {
        $this->choosePickupTime();

        $this->item->forceFill(['base_price_minor' => 19_900])->save();

        $data = $this->validate();

        // Nobody needs a dialogue to be charged less — but they should be told.
        $this->assertTrue($data['ready_for_checkout']);
        $this->assertContains(PreCheckoutIssue::PriceDecreased->value, $this->issues($data));
        $this->assertFalse($data['issues'][0]['blocking']);
    }

    // --- what it must not do -------------------------------------------------

    public function test_validating_creates_nothing(): void
    {
        $this->choosePickupTime();

        $this->validate();

        foreach (['orders', 'order_items', 'payments', 'pickup_codes'] as $table) {
            $this->assertFalse(
                Schema::hasTable($table),
                "{$table} exists in Module 13, which ends before any order does",
            );
        }

        $cart = $this->cart->fresh();

        $this->assertTrue($cart->isActive());
        $this->assertSame(1, $cart->version);
    }

    public function test_a_client_cannot_talk_the_server_into_saying_yes(): void
    {
        $data = $this->as($this->rahul)->postJson($this->url(), [
            'ready_for_checkout' => true,
            'issues' => [],
            'selection_status' => 'SELECTED',
            'pickup_selection_status' => 'SELECTED',
            'requested_pickup_start_at' => '2026-09-07T13:40:00+05:30',
        ])->json('data');

        // No pickup time has been chosen, whatever the body claims.
        $this->assertFalse($data['ready_for_checkout']);
        $this->assertSame(PickupSelectionStatus::None->value, $data['selection_status']);
        $this->assertSame(
            PickupSelectionStatus::None,
            $this->cart->fresh()->pickup_selection_status,
        );
    }

    public function test_a_customer_cannot_validate_another_customers_journey(): void
    {
        $ananya = CustomerFactory::ananya();
        $herTrip = RestaurantFixtures::tripWithSelectedRoute($ananya);

        $this->as($this->rahul)->postJson($this->url($herTrip))->assertStatus(404);
    }

    public function test_the_response_leaks_nothing_operational(): void
    {
        $this->choosePickupTime();

        $this->restaurant->forceFill([
            'internal_notes' => 'Two staff on weekends. Owner is a friend of the founder.',
            'commission_rate' => '18.50',
            'owner_phone' => '+919812345678',
        ])->save();

        $body = $this->as($this->rahul)->postJson($this->url())->getContent();

        foreach ([
            'internal_notes', 'commission_rate', 'owner_phone', 'owner_email',
            'bank_account_reference', 'tax_identifier', 'friend of the founder',
            '18.50', '9812345678', 'fingerprint',
        ] as $secret) {
            $this->assertStringNotContainsString($secret, $body, "{$secret} reached the wire");
        }
    }
}
