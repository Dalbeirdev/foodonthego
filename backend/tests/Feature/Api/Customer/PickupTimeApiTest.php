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
use Illuminate\Support\Facades\DB;
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

    // --- timezones -----------------------------------------------------------

    public function test_the_chosen_window_is_reported_on_the_same_clock_as_the_options(): void
    {
        $option = $this->pickup()['options'][0];

        $this->as($this->rahul)
            ->putJson($this->selectUrl(), ['pickup_option_id' => $option['id']])
            ->assertOk();

        $selection = $this->pickup()['selection'];

        // Same moment, and the same clock face.
        //
        // The column holds UTC. Serialising it as stored put the selection in a
        // different zone from the options beside it, so a screen showed
        // "12:50 am" for the window a customer had chosen and "6:20 am" for the
        // identical window in the list below. Found on a real device, which is
        // the first place both halves of this response are rendered together.
        $this->assertSame(
            $option['start_at'],
            $selection['start_at'],
            'the chosen window is reported on a different clock from the options',
        );
        $this->assertSame($option['end_at'], $selection['end_at']);

        // Not merely equal strings — both actually carry the restaurant's
        // offset rather than Greenwich's.
        $this->assertStringEndsWith('+05:30', $selection['start_at']);
    }

    /**
     * Every instant in a pickup body carries the counter's offset.
     *
     * The test above pins one field against another. This one pins the whole
     * response, which is the form the rule actually takes: if any moment in a
     * body is expressed on a particular clock, all of them are. It was written
     * because the narrower test passed while `server_now`, `earliest_ready_at`
     * and the travel estimate were still going out in UTC beside windows at
     * +05:30 — a fix that had corrected the field somebody looked at rather
     * than the rule.
     */
    public function test_every_instant_in_one_response_is_on_one_clock(): void
    {
        $option = $this->pickup()['options'][0];

        $this->as($this->rahul)
            ->putJson($this->selectUrl(), ['pickup_option_id' => $option['id']])
            ->assertOk();

        $body = $this->as($this->rahul)->postJson($this->optionsUrl())->json('data');

        $instants = [];

        $walk = function (array $node, string $prefix) use (&$walk, &$instants): void {
            foreach ($node as $key => $value) {
                $path = $prefix === '' ? (string) $key : $prefix.'.'.$key;

                if (is_array($value)) {
                    $walk($value, $path);
                } elseif (is_string($value) && preg_match('/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}$/', $value) === 1) {
                    $instants[$path] = $value;
                }
            }
        };

        $walk($body, '');

        // Without this the comparison below would pass on a body that had
        // stopped sending times at all.
        $this->assertGreaterThan(6, count($instants), 'too few instants to compare');

        $offsets = [];

        foreach ($instants as $path => $value) {
            $offsets[substr($value, -6)][] = $path;
        }

        $this->assertCount(
            1,
            $offsets,
            'instants on more than one clock: '.json_encode($offsets, JSON_PRETTY_PRINT),
        );

        // Asia/Kolkata is never +00:00, so a body that had merely become
        // self-consistent by sending everything in UTC still fails here.
        $this->assertSame('+05:30', array_key_first($offsets));
    }

    public function test_a_pickup_survives_a_round_trip_through_a_dst_jump(): void
    {
        // The bug this test exists for stored a 1:40 PM Kolkata window as 13:40
        // UTC — five and a half hours out. India never changes its clocks, so a
        // fixed-offset zone can hide a whole class of mistake; this one moves.
        //
        // At 01:00 UTC on 29 March 2026 the London clock goes 00:59:59 GMT
        // straight to 02:00:00 BST. The hour from 01:00 to 01:59 local does not
        // happen, and no counter can be open in it.
        $this->restaurant->forceFill(['timezone' => 'Europe/London'])->save();
        $this->restaurant->openingHours()->delete();

        // Closing at four in the morning, local, and that hour is doing work.
        // A restaurant open all day would give the same windows whichever zone
        // the comparison happened in, so this test would pass against a
        // generator that read opening hours as UTC. Four o'clock BST is three
        // o'clock UTC, and the two answers differ by an hour of windows.
        RestaurantFixtures::openDaily($this->restaurant, '00:00:00', '04:00:00');

        $this->travelTo(CarbonImmutable::parse('2026-03-29T00:40:00Z'));

        // The route was calculated against the suite's own clock, which is now
        // months away. Re-stamped so this test is about timezones rather than
        // about route freshness.
        $this->trip->selectedRoute->forceFill([
            'calculated_at' => CarbonImmutable::parse('2026-03-29T00:40:00Z'),
        ])->save();

        $pickup = $this->pickup();

        $this->assertTrue($pickup['is_feasible']);
        $this->assertSame('Europe/London', $pickup['timezone']);

        foreach ($pickup['options'] as $option) {
            $local = CarbonImmutable::parse($option['start_at'])->setTimezone('Europe/London');

            $this->assertFalse(
                $local->format('H:i') >= '01:00' && $local->format('H:i') < '02:00',
                'a window at '.$local->format('H:i').' falls inside the hour that never happened',
            );
        }

        // The kitchen shuts at 04:00 on its own clock, not on Greenwich's.
        $last = $pickup['options'][array_key_last($pickup['options'])];

        $this->assertSame(
            '04:00',
            CarbonImmutable::parse($last['end_at'])->setTimezone('Europe/London')->format('H:i'),
            'the last window does not run up to local closing time',
        );

        $option = $pickup['options'][0];

        // 00:40 GMT, plus a 93-minute drive, is 03:13 BST — the clock jumps an
        // hour in the middle of that journey. The kitchen would be ready at
        // 02:05 BST, so arrival is what binds, rounded forward to 03:20.
        $this->assertSame(
            '03:20',
            CarbonImmutable::parse($option['start_at'])->setTimezone('Europe/London')->format('H:i'),
            'the recommendation is not where the jump puts it',
        );

        $this->as($this->rahul)
            ->putJson($this->selectUrl(), ['pickup_option_id' => $option['id']])
            ->assertOk();

        $cart = $this->cart->fresh();

        // The same instant, stored in UTC, with the counter's own zone kept
        // beside it rather than baked into it.
        $this->assertSameMoment($option['start_at'], $cart->requested_pickup_start_at, 'the chosen window');
        $this->assertSame('Europe/London', $cart->pickup_timezone);
        $this->assertSame('UTC', $cart->requested_pickup_start_at->timezoneName);
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
        /*
         * Module 15 created these tables, so "the table does not exist" is no
         * longer the check — and deleting the test would have thrown away the
         * guarantee it was protecting. What actually matters is unchanged and is
         * now asserted directly: this endpoint writes no order and takes no
         * money. The tables that still have no business existing are still
         * asserted absent.
         */
        foreach (['orders', 'order_items', 'payments'] as $table) {
            $this->assertSame(
                0,
                DB::table($table)->count(),
                "{$table} gained a row, and choosing a pickup time must not create one",
            );
        }

        foreach (['pickup_codes'] as $table) {
            $this->assertFalse(
                Schema::hasTable($table),
                "{$table} exists, and nothing has specified it",
            );
        }

        $cart = $this->cart->fresh();

        $this->assertTrue($cart->isActive());
        $this->assertSame(1, $cart->version);
    }
}
