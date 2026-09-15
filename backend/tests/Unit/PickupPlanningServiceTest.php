<?php

declare(strict_types=1);

namespace Tests\Unit;

use App\Enums\ApiErrorCode;
use App\Enums\RestaurantStatus;
use App\Models\Cart;
use App\Models\CartItem;
use App\Models\Restaurant;
use App\Models\Trip;
use App\Models\User;
use App\Services\Discovery\RestaurantDiscoveryEligibilityService;
use App\Services\Pickup\ArrivalEstimate;
use App\Services\Pickup\ArrivalEstimateProvider;
use App\Services\Pickup\PickupPlan;
use App\Services\Pickup\PickupPlanningService;
use App\Services\Pickup\PickupWindow;
use App\Services\Pickup\PickupWindowGenerator;
use App\Services\Pickup\PreparationEstimateService;
use App\Support\Pickup\PlanningFingerprint;
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Cache;
use Tests\Support\CartFixtures;
use Tests\Support\CustomerFactory;
use Tests\Support\MenuFixtures;
use Tests\Support\RestaurantFixtures;
use Tests\TestCase;

/**
 * When a cart can be collected, and when it cannot be.
 *
 * The arrival estimate is stubbed throughout. That is the point of the test
 * rather than a shortcut: {@see ArrivalEstimateProvider} is the ETA boundary,
 * and driving the planner through it is what proves the planner consumes an
 * arrival time and computes none of its own. It also makes every assertion below
 * exact — the real provider derives a travel time from route geometry, and a
 * test that had to predict that number would be testing the projection maths
 * under the planner's name.
 *
 * The clock is the suite's frozen one: 2026-09-07 06:30:00Z, which is Monday
 * midday in Asia/Kolkata.
 */
final class PickupPlanningServiceTest extends TestCase
{
    use RefreshDatabase;

    private const NOW = '2026-09-07T06:30:00Z';

    private User $rahul;

    private Trip $trip;

    private Restaurant $restaurant;

    protected function setUp(): void
    {
        parent::setUp();

        Cache::flush();

        $this->rahul = CustomerFactory::rahul();
        $this->trip = RestaurantFixtures::tripWithSelectedRoute($this->rahul);
        $this->restaurant = RestaurantFixtures::nearRoute(0.4, 800, 'Highway Spice Kitchen');

        // `nearRoute` already opens the restaurant every hour of every day.
        // Replaced rather than added to: leaving both would give this
        // restaurant two overlapping schedules, which is a state the generator
        // handles but not the one these tests mean to describe.
        $this->restaurant->openingHours()->delete();
        RestaurantFixtures::openDaily($this->restaurant, '09:00:00', '22:00:00');
        $this->restaurant->load('openingHours');
    }

    // --- plumbing ------------------------------------------------------------

    private function now(): CarbonImmutable
    {
        return CarbonImmutable::parse(self::NOW);
    }

    /** A cart holding one dish that takes the stated minutes to cook. */
    private function cart(?int $prepMinutes = 20, int $lines = 1): Cart
    {
        $cart = CartFixtures::activeCart($this->rahul, $this->trip, $this->restaurant);

        $category = MenuFixtures::category($this->restaurant, 'Mains');

        for ($i = 0; $i < $lines; $i++) {
            $item = MenuFixtures::item(
                $category,
                'Dish '.$i,
                24_900,
                ['preparation_minutes' => $prepMinutes],
            );

            CartFixtures::line($cart, $item);
        }

        return $cart->fresh(['items.menuItem', 'items.variant', 'restaurant.openingHours', 'trip.selectedRoute'])
            ?? $cart;
    }

    /**
     * The planner, wired to an arrival time this test chose.
     *
     * `$arrival` null stands for the provider refusing — no route, or a
     * restaurant no longer on the corridor.
     */
    private function planner(?CarbonImmutable $arrival, bool $fresh = true): PickupPlanningService
    {
        $estimate = $arrival === null ? null : new ArrivalEstimate(
            arrivalAt: $arrival,
            travelSeconds: (int) $this->now()->diffInSeconds($arrival),
            source: 'planned_route',
            calculatedAt: $this->now(),
            isFresh: $fresh,
        );

        return new PickupPlanningService(
            arrival: new class($estimate) implements ArrivalEstimateProvider
            {
                public function __construct(private readonly ?ArrivalEstimate $estimate) {}

                public function estimate(Trip $trip, Restaurant $restaurant, CarbonImmutable $now): ?ArrivalEstimate
                {
                    return $this->estimate;
                }
            },
            preparation: new PreparationEstimateService,
            windows: new PickupWindowGenerator,
            eligibility: new RestaurantDiscoveryEligibilityService,
        );
    }

    private function plan(Cart $cart, ?CarbonImmutable $arrival, bool $fresh = true): PickupPlan
    {
        return $this->planner($arrival, $fresh)->plan($cart, $this->now());
    }

    /** Local "H:i" of a window's start, for readable failures. */
    private function local(PickupWindow $window): string
    {
        return $window->startAt->setTimezone($this->restaurant->timezone)->format('H:i');
    }

    // --- the recommendation --------------------------------------------------

    public function test_a_later_arrival_wins_over_an_earlier_ready_time(): void
    {
        // Ready at 12:25 local; the customer gets there at 13:00.
        $plan = $this->plan($this->cart(20), $this->now()->addMinutes(60));

        $this->assertNull($plan->refusal);
        $this->assertNotNull($plan->recommended);

        // Food is not cooked half an hour early to sit under a lamp.
        $this->assertSame('13:00', $this->local($plan->recommended));
    }

    public function test_an_earlier_arrival_loses_to_the_kitchen_and_never_rounds_back(): void
    {
        // The customer would be there at 12:05, the food is ready at 12:25.
        $plan = $this->plan($this->cart(20), $this->now()->addMinutes(5));

        $this->assertNotNull($plan->recommended);

        // 12:30, not 12:20. Rounding back is the one direction that turns a
        // helpful suggestion into a counter with nothing on it.
        $this->assertSame('12:30', $this->local($plan->recommended));

        $this->assertTrue(
            $plan->recommended->startAt >= $plan->earliestReadyAt,
            'a recommendation before the food is ready is a broken promise',
        );
    }

    // --- earliest ready ------------------------------------------------------

    public function test_the_minimum_lead_raises_a_quick_order_to_its_floor(): void
    {
        $this->restaurant->forceFill(['operational_buffer_minutes' => 0])->save();

        // Two minutes of cooking. The ten-minute lead is what actually binds:
        // a kitchen needs a moment to see an order at all.
        $plan = $this->plan($this->cart(2), $this->now()->addMinutes(60));

        $this->assertEquals($this->now()->addMinutes(10), $plan->earliestReadyAt);
    }

    public function test_the_minimum_lead_does_not_stack_onto_a_slow_order(): void
    {
        $this->restaurant->forceFill(['operational_buffer_minutes' => 0])->save();

        // Forty minutes of cooking is forty, not fifty. A floor is a floor.
        $plan = $this->plan($this->cart(40), $this->now()->addMinutes(120));

        $this->assertEquals($this->now()->addMinutes(40), $plan->earliestReadyAt);
    }

    public function test_a_restaurants_own_buffer_wins_and_zero_is_a_real_answer(): void
    {
        $this->restaurant->forceFill(['operational_buffer_minutes' => 0])->save();

        $plan = $this->plan($this->cart(30), $this->now()->addMinutes(120));

        // Thirty, not thirty-five. Zero means this kitchen hands over the
        // moment the food is done — a claim an operator may make, and one the
        // platform must not overwrite with its own default.
        $this->assertSame(0, $plan->bufferMinutes);
        $this->assertEquals($this->now()->addMinutes(30), $plan->earliestReadyAt);
    }

    public function test_the_platform_buffer_applies_when_the_restaurant_has_not_set_one(): void
    {
        $this->assertNull($this->restaurant->operational_buffer_minutes);

        $plan = $this->plan($this->cart(30), $this->now()->addMinutes(120));

        $this->assertSame(5, $plan->bufferMinutes);
        $this->assertEquals($this->now()->addMinutes(35), $plan->earliestReadyAt);
    }

    // --- refusals ------------------------------------------------------------

    public function test_an_empty_cart_is_refused(): void
    {
        $cart = CartFixtures::activeCart($this->rahul, $this->trip, $this->restaurant);

        $plan = $this->plan($cart->fresh(['items', 'restaurant.openingHours', 'trip.selectedRoute']), $this->now()->addMinutes(60));

        $this->assertSame(ApiErrorCode::CartEmpty, $plan->refusal);
        $this->assertSame([], $plan->windows);
    }

    public function test_a_paused_kitchen_is_refused_and_says_which_kind_of_shut_it_is(): void
    {
        $this->restaurant->forceFill(['is_accepting_orders' => false])->save();

        $plan = $this->plan($this->cart(20), $this->now()->addMinutes(60));

        // Not RESTAURANT_UNAVAILABLE. A paused kitchen may be taking orders
        // again in ten minutes; a deactivated restaurant will not, and the
        // customer's next move is different for each.
        $this->assertSame(ApiErrorCode::RestaurantNotAcceptingOrders, $plan->refusal);
    }

    public function test_a_stale_route_is_refused_rather_than_silently_recalculated(): void
    {
        $plan = $this->plan($this->cart(20), $this->now()->addMinutes(60), fresh: false);

        $this->assertSame(ApiErrorCode::RouteStale, $plan->refusal);
        $this->assertTrue($plan->requiresRouteRefresh);
        $this->assertSame([], $plan->windows);

        // The arithmetic survives the refusal, so the screen can explain it
        // rather than showing a bare error.
        $this->assertSame(20, $plan->preparation->minutes);
        $this->assertNotNull($plan->arrival);
    }

    public function test_a_restaurant_no_longer_on_the_route_is_refused(): void
    {
        $plan = $this->plan($this->cart(20), null);

        $this->assertSame(ApiErrorCode::RestaurantOutsideRoute, $plan->refusal);
        $this->assertTrue($plan->requiresRouteRefresh);
    }

    public function test_a_restaurant_shut_all_day_offers_no_window(): void
    {
        $this->restaurant->openingHours()->delete();
        RestaurantFixtures::openOn($this->restaurant, 4, '09:00:00', '22:00:00'); // Friday only.

        $plan = $this->plan($this->cart(20), $this->now()->addMinutes(60));

        $this->assertSame(ApiErrorCode::NoFeasiblePickupWindow, $plan->refusal);
    }

    // --- which options are offered -------------------------------------------

    public function test_the_options_are_capped_and_begin_at_the_recommendation(): void
    {
        $plan = $this->plan($this->cart(20), $this->now()->addMinutes(60));

        $this->assertNotNull($plan->recommended);
        $this->assertCount(8, $plan->windows);

        // Not the first eight from the earliest-ready time. Those would all
        // fall before the customer could get there, which is a column of
        // choices that are not choices.
        $this->assertSame('13:00', $this->local($plan->windows[0]));
        $this->assertSame('14:10', $this->local($plan->windows[7]));

        // Every option is distinct. A capped list with a repeat in it is a
        // shorter list than it looks.
        $starts = array_map(fn (PickupWindow $w): string => $this->local($w), $plan->windows);
        $this->assertSame(array_values(array_unique($starts)), $starts);
    }

    public function test_arriving_after_the_last_window_offers_the_closest_ones_and_recommends_none(): void
    {
        // Planning reaches four hours ahead — noon to 16:00 local — and the
        // customer does not get there until 23:00.
        $plan = $this->plan($this->cart(20), $this->now()->addMinutes(660));

        // No recommendation. Suggesting one would be suggesting a counter they
        // cannot reach in time.
        $this->assertNull($plan->recommended);
        $this->assertNotEmpty($plan->windows);

        // Showing the options is still fair — the estimate assumes they set off
        // now, and they may well go sooner — but they are the LAST ones, the
        // nearest to being reachable, rather than the first eight after the
        // food is ready.
        $this->assertSame('16:00', $this->local($plan->windows[array_key_last($plan->windows)]));
    }

    public function test_no_offered_window_starts_before_the_food_is_ready(): void
    {
        // The invariant behind every case above: a window a customer can tap is
        // one the kitchen has committed to, and offering one that starts before
        // the food exists is the worst thing this module could do.
        //
        // **This assertion cannot currently fail, and that is recorded here
        // rather than left to look load-bearing.** The property is guaranteed at
        // two independent points — the generator starts its cursor at the
        // earliest ready time, and `offered()` slices forward from a
        // recommendation that is itself at or after it — so no single-point
        // mutation reaches it. Both of those points have controls of their own
        // that do fire. This is kept as a guard on the day somebody changes how
        // the offered list is chosen, which is the change that would make it
        // load-bearing.
        // One cart, four journeys' worth of arrival times. One active cart per
        // journey is a database constraint, and building four would be testing
        // that instead.
        $cart = $this->cart(20);

        foreach ([5, 60, 120, 660] as $minutesAway) {
            $plan = $this->plan($cart, $this->now()->addMinutes($minutesAway));

            $this->assertNotEmpty($plan->windows, "no windows planning {$minutesAway} minutes out");

            foreach ($plan->windows as $window) {
                $this->assertTrue(
                    $window->startAt >= $plan->earliestReadyAt,
                    $this->local($window).' is offered before the food is ready',
                );
            }
        }
    }

    // --- what planning must not do -------------------------------------------

    public function test_planning_writes_nothing(): void
    {
        $cart = $this->cart(20);

        $before = Cart::query()->whereKey($cart->id)->firstOrFail();

        $this->plan($cart, $this->now()->addMinutes(60));

        $after = Cart::query()->whereKey($cart->id)->firstOrFail();

        // No order exists in this module and none can. Planning is a
        // calculation over live state: no row, no reservation, no selection.
        $this->assertSame($before->version, $after->version);
        $this->assertSame('NONE', $after->pickup_selection_status->value);
        $this->assertNull($after->requested_pickup_start_at);
        $this->assertEquals($before->updated_at, $after->updated_at);
        $this->assertSame(0, CartItem::query()->where('cart_id', $cart->id)->count() - 1);
    }

    // --- the fingerprint -----------------------------------------------------

    public function test_the_fingerprint_moves_when_the_cart_contents_move(): void
    {
        $cart = $this->cart(20);

        $before = PlanningFingerprint::of($cart);

        $cart->recordContentChange();

        $this->assertNotSame($before, PlanningFingerprint::of($cart->fresh(['restaurant.openingHours', 'trip.selectedRoute'])));
    }

    public function test_the_fingerprint_holds_still_when_only_a_price_moves(): void
    {
        $cart = $this->cart(20);

        $before = PlanningFingerprint::of($cart);

        $cart->items->first()->menuItem->forceFill(['base_price_minor' => 31_900])->save();

        // A dish going up in price does not change how long the kitchen needs.
        // Invalidating a perfectly good pickup window over it would be caution
        // the customer experiences as breakage — and Module 12's revalidation
        // is what actually shows them the new figure.
        $this->assertSame(
            $before,
            PlanningFingerprint::of($cart->fresh(['items.menuItem', 'restaurant.openingHours', 'trip.selectedRoute'])),
        );
    }

    public function test_a_suspended_restaurant_is_refused_without_saying_why(): void
    {
        $this->restaurant->forceFill(['status' => RestaurantStatus::Suspended->value])->save();

        $plan = $this->plan($this->cart(20), $this->now()->addMinutes(60));

        // Not "suspended". Naming the reason tells anybody who can guess a
        // restaurant's name something the platform has not decided to publish.
        $this->assertSame(ApiErrorCode::RestaurantUnavailable, $plan->refusal);
    }

    public function test_the_fingerprint_moves_when_the_restaurant_is_suspended(): void
    {
        $cart = $this->cart(20);

        $before = PlanningFingerprint::of($cart);

        $this->restaurant->forceFill(['status' => RestaurantStatus::Suspended->value])->save();

        $this->assertNotSame(
            $before,
            PlanningFingerprint::of($cart->fresh(['restaurant.openingHours', 'trip.selectedRoute'])),
        );
    }

    public function test_the_fingerprint_moves_when_the_restaurant_stops_taking_orders(): void
    {
        $cart = $this->cart(20);

        $before = PlanningFingerprint::of($cart);

        $this->restaurant->forceFill(['is_accepting_orders' => false])->save();

        $this->assertNotSame(
            $before,
            PlanningFingerprint::of($cart->fresh(['restaurant.openingHours', 'trip.selectedRoute'])),
        );
    }

    public function test_the_fingerprint_moves_when_the_restaurant_edits_its_hours(): void
    {
        $cart = $this->cart(20);

        $before = PlanningFingerprint::of($cart);

        $this->restaurant->openingHours()->delete();
        RestaurantFixtures::openDaily($this->restaurant, '11:00:00', '20:00:00');

        $this->assertNotSame(
            $before,
            PlanningFingerprint::of($cart->fresh(['restaurant.openingHours', 'trip.selectedRoute'])),
        );
    }

    public function test_the_fingerprint_ignores_the_order_hours_were_written_in(): void
    {
        $cart = $this->cart(20);

        $before = PlanningFingerprint::of($cart);

        // The same schedule, inserted back to front. A fingerprint that
        // disagreed would mark every plan stale for a reason no customer could
        // see and no operator caused.
        $this->restaurant->openingHours()->delete();

        foreach (array_reverse(range(0, 6)) as $day) {
            RestaurantFixtures::openOn($this->restaurant, $day, '09:00:00', '22:00:00');
        }

        $this->assertSame(
            $before,
            PlanningFingerprint::of($cart->fresh(['restaurant.openingHours', 'trip.selectedRoute'])),
        );
    }
}
