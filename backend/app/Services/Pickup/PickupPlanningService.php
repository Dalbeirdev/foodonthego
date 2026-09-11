<?php

declare(strict_types=1);

namespace App\Services\Pickup;

use App\Enums\ApiErrorCode;
use App\Models\Cart;
use App\Models\Restaurant;
use App\Services\Discovery\RestaurantDiscoveryEligibilityService;
use App\Support\Pickup\PlanningFingerprint;
use Carbon\CarbonImmutable;

/**
 * When this cart can be collected, and why.
 *
 * The one place the arithmetic lives. Travel comes from
 * {@see ArrivalEstimateProvider}, cooking from {@see PreparationEstimateService},
 * the calendar from {@see PickupWindowGenerator}; this service is what puts them
 * in an order and refuses when they do not add up.
 *
 * **Every instant here is the server's.** `$now` is injectable only so tests can
 * fix a moment, and it is never populated from a request. A device whose clock
 * is an hour fast would otherwise be handed windows in the past and told they
 * were fine, which is the failure this module is most obliged not to have.
 *
 * Nothing here creates anything. Planning a pickup writes no row, reserves no
 * capacity, calls no routing provider and touches no payment. It is a
 * calculation over live state, run again from scratch every time it is asked.
 */
final class PickupPlanningService
{
    public function __construct(
        private readonly ArrivalEstimateProvider $arrival,
        private readonly PreparationEstimateService $preparation,
        private readonly PickupWindowGenerator $windows,
        private readonly RestaurantDiscoveryEligibilityService $eligibility,
    ) {}

    public function plan(Cart $cart, ?CarbonImmutable $now = null): PickupPlan
    {
        $now = $now ?? CarbonImmutable::now();

        $restaurant = $cart->restaurant;
        $trip = $cart->trip;

        $preparation = $this->preparation->forCart($cart);
        $buffer = $this->bufferMinutes($restaurant);
        $lead = max(0, (int) config('foodonthego.pickup.minimum_lead_minutes'));
        $zone = $this->zone($restaurant);
        $fingerprint = PlanningFingerprint::of($cart);

        // A refusal still carries the arithmetic. "The kitchen needs twenty-five
        // minutes and you would arrive after they close" is something a screen
        // can explain; a bare error is something a customer has to guess at.
        $refuse = fn (ApiErrorCode $code, bool $refresh = false, ?ArrivalEstimate $arrival = null): PickupPlan => new PickupPlan(
            serverNow: $now,
            arrival: $arrival,
            preparation: $preparation,
            bufferMinutes: $buffer,
            minimumLeadMinutes: $lead,
            earliestReadyAt: null,
            recommended: null,
            windows: [],
            allWindows: [],
            fingerprint: $fingerprint,
            timezone: $zone,
            requiresRouteRefresh: $refresh,
            refusal: $code,
        );

        if ($cart->items->isEmpty()) {
            return $refuse(ApiErrorCode::CartEmpty);
        }

        // The same rule discovery applies, from the same service. A second
        // expression of "may a customer be shown this restaurant" is a rule
        // that drifts, and the way it drifts is that a suspended restaurant
        // keeps taking pickup times on a screen nobody was looking at.
        //
        // Why not the plain reason: "this restaurant is suspended" tells anyone
        // who can guess a name something the platform has not published.
        if ($restaurant === null || ! $this->eligibility->isEligible($restaurant)) {
            return $refuse(ApiErrorCode::RestaurantUnavailable);
        }

        if (! $restaurant->is_accepting_orders) {
            // Separate from unavailable on purpose: the customer's next move
            // differs. A paused kitchen may take orders again in ten minutes;
            // a deactivated restaurant will not.
            return $refuse(ApiErrorCode::RestaurantNotAcceptingOrders);
        }

        if ($trip === null || $trip->selectedRoute === null) {
            // No journey, no arrival, no honest window. Refusing here rather
            // than planning from the restaurant's clock alone, because a pickup
            // time the customer cannot reach is worse than no pickup time.
            return $refuse(ApiErrorCode::RouteNotReady, refresh: true);
        }

        $arrival = $this->arrival->estimate($trip, $restaurant, $now);

        if ($arrival === null) {
            // The provider found the route and could not place this restaurant
            // on it. The cart's restaurant is no longer on the road being
            // taken, which is a planning refusal and not a zero-minute drive.
            return $refuse(ApiErrorCode::RestaurantOutsideRoute, refresh: true);
        }

        if (! $arrival->isFresh) {
            // Stale: refuse and say so. V1 does not silently re-route on the
            // customer's behalf — a routing call is billed, and one triggered by
            // opening a screen is a cost nobody asked for. The screen offers
            // Refresh journey, which goes through Module 06's existing service.
            return $refuse(ApiErrorCode::RouteStale, refresh: true, arrival: $arrival);
        }

        $earliestReadyAt = $this->earliestReadyAt($now, $preparation, $buffer, $lead);

        $horizonAt = $now->addMinutes(max(1, (int) config('foodonthego.pickup.max_horizon_minutes')));

        $all = $this->windows->generate(
            $restaurant->loadMissing('openingHours'),
            $earliestReadyAt,
            $horizonAt,
        );

        if ($all === []) {
            return $refuse(ApiErrorCode::NoFeasiblePickupWindow, arrival: $arrival);
        }

        // max(arrival, ready). Food is not cooked an hour early to sit under a
        // lamp, and a customer is not sent to a counter before the kitchen has
        // started. Rounded FORWARD onto the slot grid by the generator, never
        // back: rounding back would recommend a time the kitchen cannot meet.
        $centre = $arrival->arrivalAt->max($earliestReadyAt);

        $recommended = $this->firstAtOrAfter($all, $centre);

        return new PickupPlan(
            serverNow: $now,
            arrival: $arrival,
            preparation: $preparation,
            bufferMinutes: $buffer,
            minimumLeadMinutes: $lead,
            earliestReadyAt: $earliestReadyAt,
            recommended: $recommended,
            windows: $this->offered($all, $recommended),
            allWindows: $all,
            fingerprint: $fingerprint,
            timezone: $zone,
            requiresRouteRefresh: false,
            refusal: null,
        );
    }

    /**
     * The earliest the food can be in a bag on the counter.
     *
     *   now + preparation + buffer,   then at least   now + minimum lead
     *
     * The buffer is packing, bagging and handing over. It is applied exactly
     * once, it is a duration and never a charge, and it reaches no total.
     *
     * The lead time is a floor, not an addition. A kitchen needs a moment to
     * see an order at all — but a dish that already takes forty minutes does not
     * take fifty because of it.
     */
    private function earliestReadyAt(
        CarbonImmutable $now,
        PreparationEstimate $preparation,
        int $buffer,
        int $lead,
    ): CarbonImmutable {
        return $now
            ->addMinutes($preparation->minutes + $buffer)
            ->max($now->addMinutes($lead));
    }

    /**
     * The restaurant's own handover time, or the platform's.
     *
     * Null is not zero. Null means nobody has set this and the platform default
     * applies; zero means this kitchen hands over the instant the food is done,
     * which is a claim an operator may make and the platform must not make for
     * them. The same distinction the tax rate draws, for the same reason — which
     * is why the check is `!== null` and not a truthiness test.
     */
    private function bufferMinutes(?Restaurant $restaurant): int
    {
        $own = $restaurant?->operational_buffer_minutes;

        if ($own !== null) {
            return max(0, (int) $own);
        }

        return max(0, (int) config('foodonthego.pickup.operational_buffer_minutes'));
    }

    /**
     * @param  list<PickupWindow>  $windows
     */
    private function firstAtOrAfter(array $windows, CarbonImmutable $moment): ?PickupWindow
    {
        foreach ($windows as $window) {
            if ($window->startAt >= $moment) {
                return $window;
            }
        }

        // Every window falls before the customer could get there — they arrive
        // after the restaurant's last pickup of the day. There are still
        // options to show, and none of them is a recommendation: suggesting one
        // would be suggesting a counter the customer will not reach in time.
        return null;
    }

    /**
     * Which windows to actually offer.
     *
     * A screen of forty time chips is not a choice, it is a spreadsheet, so the
     * list is capped. **Which** end it is capped from matters more than the cap:
     * taking the first N from the earliest-ready time would hand back a column
     * of windows that all fall before the customer can arrive. The list
     * therefore starts at the recommendation and runs forward from it, and when
     * there is no recommendation — arrival is past every window — it is the last
     * N, the ones nearest to being reachable.
     *
     * @param  list<PickupWindow>  $windows
     * @return list<PickupWindow>
     */
    private function offered(array $windows, ?PickupWindow $recommended): array
    {
        $max = max(1, (int) config('foodonthego.pickup.max_options'));

        if ($recommended === null) {
            return array_slice($windows, -$max);
        }

        $from = 0;

        foreach ($windows as $index => $window) {
            if ($window->startAt == $recommended->startAt) {
                $from = $index;

                break;
            }
        }

        return array_slice($windows, $from, $max);
    }

    private function zone(?Restaurant $restaurant): string
    {
        $zone = (string) ($restaurant?->timezone ?: '');

        try {
            CarbonImmutable::now($zone);

            return $zone;
        } catch (\Throwable) {
            return (string) config('foodonthego.discovery.default_timezone');
        }
    }
}
