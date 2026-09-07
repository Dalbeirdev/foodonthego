<?php

declare(strict_types=1);

namespace Tests\Feature\Api\Customer;

use App\Enums\ApiErrorCode;
use App\Enums\PickupSelectionStatus;
use App\Models\Cart;
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
 * Choosing a pickup time, over HTTP.
 *
 * The theme is that the client is trusted with nothing. It receives times and
 * sends back an id; there is no field in either request a customer could edit
 * into a pickup time of their choosing, and several tests below try.
 *
 * The second theme is that no order exists. Module 13 ends with four columns on
 * a cart, and the tests that check what did NOT happen matter as much as the
 * ones that check what did.
 */
final class PickupTimeApiTest extends TestCase
{
    use RefreshDatabase;

    private User $rahul;

    private Trip $trip;

    private Restaurant $restaurant;

    private Cart $cart;

    protected function setUp(): void
    {
        parent::setUp();

        Cache::flush();

        $this->rahul = CustomerFactory::rahul();
        $this->trip = RestaurantFixtures::tripWithSelectedRoute($this->rahul);
        $this->restaurant = RestaurantFixtures::nearRoute(0.4, 800, 'Highway Spice Kitchen');

        $this->restaurant->openingHours()->delete();
        RestaurantFixtures::openDaily($this->restaurant, '09:00:00', '22:00:00');

        $this->cart = $this->cartFor($this->rahul, $this->trip, $this->restaurant);
    }

    // --- plumbing ------------------------------------------------------------

    private function cartFor(User $customer, Trip $trip, Restaurant $restaurant): Cart
    {
        $cart = CartFixtures::activeCart($customer, $trip, $restaurant);

        $category = MenuFixtures::category($restaurant, 'Mains');
        $item = MenuFixtures::item($category, 'Paneer Tikka', 24_900, ['preparation_minutes' => 20]);

        CartFixtures::line($cart, $item);

        return $cart->fresh() ?? $cart;
    }

    private function as(User $customer): self
    {
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', 'Bearer '.CustomerFactory::tokenFor($customer));
    }

    private function optionsUrl(?Trip $trip = null): string
    {
        return '/api/v1/customer/trips/'.($trip ?? $this->trip)->uuid.'/cart/pickup-options';
    }

    private function selectUrl(?Trip $trip = null): string
    {
        return '/api/v1/customer/trips/'.($trip ?? $this->trip)->uuid.'/cart/pickup-selection';
    }

    /** @return array<string, mixed> */
    private function pickup(?User $as = null, ?Trip $trip = null): array
    {
        $response = $this->as($as ?? $this->rahul)->postJson($this->optionsUrl($trip));

        $response->assertOk();

        return $response->json('data.pickup');
    }

    /**
     * The same moment, however it is written down.
     *
     * The column holds UTC, as every timestamp in this schema does; the API
     * renders the restaurant's own offset, because a pickup happens at the
     * counter on the counter's clock. Comparing the two as strings would be
     * asserting a formatting choice and calling it a time.
     */
    private function assertSameMoment(string $iso, ?CarbonImmutable $stored, string $what): void
    {
        $this->assertNotNull($stored, "{$what} was not recorded");
        $this->assertTrue(
            CarbonImmutable::parse($iso)->equalTo($stored),
            "{$what}: expected {$iso}, stored ".$stored->toIso8601String(),
        );
    }

    // --- the happy path ------------------------------------------------------

    public function test_options_explain_the_arithmetic_behind_the_times(): void
    {
        $pickup = $this->pickup();

        $this->assertTrue($pickup['is_feasible']);
        $this->assertNotEmpty($pickup['options']);

        // A list of times with no explanation is a list a customer has to take
        // on trust, and the first one that looks wrong is the one that loses
        // them.
        $this->assertSame(20, $pickup['preparation']['preparation_minutes']);
        $this->assertSame(5, $pickup['buffer_minutes']);
        $this->assertSame(10, $pickup['minimum_lead_minutes']);
        $this->assertNotNull($pickup['earliest_ready_at']);
        $this->assertNotNull($pickup['travel']['estimated_arrival_at']);
        $this->assertSame('Asia/Kolkata', $pickup['timezone']);
        $this->assertNotNull($pickup['recommended_option_id']);
    }

    public function test_choosing_a_time_records_it_on_the_cart(): void
    {
        $pickup = $this->pickup();
        $option = $pickup['options'][0];

        $response = $this->as($this->rahul)
            ->putJson($this->selectUrl(), ['pickup_option_id' => $option['id']]);

        $response->assertOk();

        $cart = $this->cart->fresh();

        $this->assertSame(PickupSelectionStatus::Selected, $cart->pickup_selection_status);
        $this->assertSameMoment($option['start_at'], $cart->requested_pickup_start_at, 'start');
        $this->assertSameMoment($option['end_at'], $cart->requested_pickup_end_at, 'end');
        $this->assertSame('Asia/Kolkata', $cart->pickup_timezone);
        $this->assertNotNull($cart->pickup_selected_at);
        $this->assertNotNull($cart->pickup_planning_fingerprint);
    }

    public function test_choosing_again_replaces_the_choice_rather_than_adding_one(): void
    {
        $first = $this->pickup()['options'][0];

        $this->as($this->rahul)->putJson($this->selectUrl(), ['pickup_option_id' => $first['id']])->assertOk();

        $second = $this->pickup()['options'][2];

        $this->as($this->rahul)->putJson($this->selectUrl(), ['pickup_option_id' => $second['id']])->assertOk();

        $cart = $this->cart->fresh();

        // One pickup time per cart. A PUT, and it means it.
        $this->assertSameMoment($second['start_at'], $cart->requested_pickup_start_at, 'the second choice');
    }

    // --- what the client is not trusted with ---------------------------------

    public function test_the_response_carries_no_timestamp_the_client_could_send_back(): void
    {
        $pickup = $this->pickup();

        // The id is the whole of what a client hands back. It carries no
        // structure — no index, no cart, no time — so there is nothing in it to
        // edit and nothing to learn from reading it.
        foreach ($pickup['options'] as $option) {
            $this->assertMatchesRegularExpression('/^[0-9a-f]{64}$/', $option['id']);
        }
    }

    public function test_a_forged_option_id_is_refused(): void
    {
        $this->pickup();

        $this->as($this->rahul)
            ->putJson($this->selectUrl(), ['pickup_option_id' => str_repeat('a', 64)])
            ->assertStatus(409)
            ->assertJsonPath('error.code', ApiErrorCode::PickupOptionExpired->value);

        $this->assertSame(PickupSelectionStatus::None, $this->cart->fresh()->pickup_selection_status);
    }

    public function test_an_id_that_is_not_a_live_option_is_refused_whatever_shape_it_takes(): void
    {
        $this->pickup();

        // None of these resolves, and none of them is special. A cache key is a
        // literal string to Redis and to the array store alike, so a `*` selects
        // nothing rather than everything — the refusal comes from the lookup
        // missing, not from the shape of what was sent.
        foreach (['*', '../../pickup:option', 'pickup:option:1:2', str_repeat('z', 4_096), ''] as $attempt) {
            $this->as($this->rahul)
                ->putJson($this->selectUrl(), ['pickup_option_id' => $attempt])
                ->assertStatus($attempt === '' ? 422 : 409);
        }

        $this->assertSame(PickupSelectionStatus::None, $this->cart->fresh()->pickup_selection_status);
    }

    public function test_a_body_carrying_its_own_pickup_time_is_ignored(): void
    {
        $option = $this->pickup()['options'][0];

        $this->as($this->rahul)->putJson($this->selectUrl(), [
            'pickup_option_id' => $option['id'],
            // Every field a customer might hope decides something.
            'requested_pickup_start_at' => '2026-09-07T04:00:00+00:00',
            'requested_pickup_end_at' => '2026-09-07T04:10:00+00:00',
            'start_at' => '2026-09-07T04:00:00+00:00',
            'preparation_minutes' => 0,
            'pickup_selection_status' => 'SELECTED',
            'version' => 999,
            'restaurant_id' => 999,
            'ready_for_checkout' => true,
        ])->assertOk();

        $cart = $this->cart->fresh();

        // The window the SERVER offered, not the one the request asked for.
        $this->assertSameMoment($option['start_at'], $cart->requested_pickup_start_at, 'the chosen window');
        $this->assertFalse(
            CarbonImmutable::parse('2026-09-07T04:00:00+00:00')->equalTo($cart->requested_pickup_start_at),
            'the request talked the server into its own pickup time',
        );
        $this->assertSame(1, $cart->version);
        $this->assertSame($this->restaurant->id, $cart->restaurant_id);
    }

    // --- IDOR ----------------------------------------------------------------

    public function test_one_customer_cannot_use_anothers_option_id(): void
    {
        $ananya = CustomerFactory::ananya();
        $herTrip = RestaurantFixtures::tripWithSelectedRoute($ananya);
        $this->cartFor($ananya, $herTrip, $this->restaurant);

        $hers = $this->pickup($ananya, $herTrip)['options'][0];

        // Rahul, presenting Ananya's id against his own journey.
        $this->as($this->rahul)
            ->putJson($this->selectUrl(), ['pickup_option_id' => $hers['id']])
            ->assertStatus(409)
            ->assertJsonPath('error.code', ApiErrorCode::PickupOptionExpired->value);

        $this->assertSame(PickupSelectionStatus::None, $this->cart->fresh()->pickup_selection_status);
    }

    public function test_a_customer_cannot_use_their_own_option_from_a_different_journey(): void
    {
        $other = RestaurantFixtures::tripWithSelectedRoute($this->rahul);
        $this->cartFor($this->rahul, $other, $this->restaurant);

        $fromTheOtherTrip = $this->pickup($this->rahul, $other)['options'][0];

        // A window costed against one cart says nothing about another.
        $this->as($this->rahul)
            ->putJson($this->selectUrl(), ['pickup_option_id' => $fromTheOtherTrip['id']])
            ->assertStatus(404)
            ->assertJsonPath('error.code', ApiErrorCode::PickupOptionForbidden->value);
    }

    public function test_a_customer_cannot_read_another_customers_journey(): void
    {
        $ananya = CustomerFactory::ananya();
        $herTrip = RestaurantFixtures::tripWithSelectedRoute($ananya);

        $this->as($this->rahul)->postJson($this->optionsUrl($herTrip))->assertStatus(404);
    }

    // --- staleness -----------------------------------------------------------

    public function test_changing_the_cart_makes_an_outstanding_option_stale(): void
    {
        $option = $this->pickup()['options'][0];

        // The customer adds something while the pickup screen is open.
        $this->cart->recordContentChange();

        $this->as($this->rahul)
            ->putJson($this->selectUrl(), ['pickup_option_id' => $option['id']])
            ->assertStatus(409)
            ->assertJsonPath('error.code', ApiErrorCode::PickupOptionStale->value);

        $this->assertSame(PickupSelectionStatus::None, $this->cart->fresh()->pickup_selection_status);
    }

    public function test_a_paused_kitchen_stops_a_choice_being_made(): void
    {
        $option = $this->pickup()['options'][0];

        $this->restaurant->forceFill(['is_accepting_orders' => false])->save();

        $this->as($this->rahul)
            ->putJson($this->selectUrl(), ['pickup_option_id' => $option['id']])
            ->assertStatus(409)
            ->assertJsonPath('error.code', ApiErrorCode::RestaurantNotAcceptingOrders->value);
    }

    public function test_an_option_cannot_be_used_twice(): void
    {
        $option = $this->pickup()['options'][0];

        $this->as($this->rahul)->putJson($this->selectUrl(), ['pickup_option_id' => $option['id']])->assertOk();

        // Retired once used. Choosing the same time again is harmless in
        // itself, but an id that has done its job should not sit in the store
        // for another ten minutes waiting for a cart that has moved on.
        $this->as($this->rahul)
            ->putJson($this->selectUrl(), ['pickup_option_id' => $option['id']])
            ->assertStatus(409)
            ->assertJsonPath('error.code', ApiErrorCode::PickupOptionExpired->value);
    }

    // --- what must not leak --------------------------------------------------

    public function test_the_response_leaks_nothing_operational(): void
    {
        $this->restaurant->forceFill([
            'internal_notes' => 'Owner is a friend of the founder. Two staff on weekends.',
            'commission_rate' => '18.50',
            'owner_phone' => '+919812345678',
        ])->save();

        // Chosen first, so there is a real fingerprint on the cart to look for.
        $option = $this->pickup()['options'][0];
        $this->as($this->rahul)->putJson($this->selectUrl(), ['pickup_option_id' => $option['id']])->assertOk();

        $body = $this->as($this->rahul)->postJson($this->optionsUrl())->getContent();

        foreach ([
            'internal_notes', 'commission_rate', 'owner_phone', 'owner_email',
            'bank_account_reference', 'tax_identifier', 'friend of the founder',
            '18.50', '9812345678',
        ] as $secret) {
            $this->assertStringNotContainsString($secret, $body, "{$secret} reached the wire");
        }

        // Nor the comparison value the server hashes. No screen has a use for
        // it, and publishing it invites somebody to try reproducing it.
        $stored = $this->cart->fresh()->pickup_planning_fingerprint;
        $this->assertNotNull($stored, 'nothing was stored, so this test would assert nothing');
        $this->assertStringNotContainsString($stored, $body);
        $this->assertStringNotContainsString('fingerprint', $body);
    }

    public function test_the_per_line_preparation_breakdown_stays_off_the_wire(): void
    {
        $body = $this->as($this->rahul)->postJson($this->optionsUrl())->getContent();

        // A customer does not need to know which dish is the slow one, and an
        // operator's preparation times are their business.
        $this->assertStringNotContainsString('"lines"', $body);
        $this->assertStringNotContainsString('platform_fallback', $body);
        $this->assertStringNotContainsString('restaurant_default', $body);
    }

    // --- no order, no payment ------------------------------------------------

    public function test_choosing_a_time_creates_no_order_and_no_payment(): void
    {
        $option = $this->pickup()['options'][0];

        $this->as($this->rahul)->putJson($this->selectUrl(), ['pickup_option_id' => $option['id']])->assertOk();

        // Module 13 ends with four columns on a cart. There is no order table
        // to write to yet, and this asserts that none appeared to be written
        // to — the check that would have caught somebody getting ahead.
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
}
