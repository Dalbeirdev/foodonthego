<?php

declare(strict_types=1);

namespace App\Services\Pickup;

use App\Enums\PickupSelectionStatus;
use App\Models\Cart;
use Carbon\CarbonImmutable;

/**
 * What has actually become of a customer's pickup choice.
 *
 * **Only two of the four statuses are ever written down.** A cart stores what
 * the customer chose — `NONE` or `SELECTED` — and that is a fact about their
 * intent which nothing outside their own action should change. `STALE` and
 * `INVALID` are conclusions about that intent held up against the world, and
 * they are computed here, every time they are asked for.
 *
 * Storing them would be storing a derived value, and a derived value goes out
 * of date the moment the thing it was derived from moves. A column reading
 * `SELECTED` while the restaurant has since edited its hours is not wrong
 * because somebody forgot to run a job — it is wrong because a column cannot
 * know. The comparison is cheap and the plan is being built anyway.
 */
final class PickupSelectionEvaluator
{
    /**
     * The effective status, against a plan built for this moment.
     *
     * The plan is passed in rather than built here: every caller already has
     * one, and building a second would be doing the same arithmetic twice and
     * risking two answers.
     */
    public function statusFor(Cart $cart, PickupPlan $plan, CarbonImmutable $now): PickupSelectionStatus
    {
        $stored = $cart->pickup_selection_status ?? PickupSelectionStatus::None;

        if ($stored !== PickupSelectionStatus::Selected) {
            return PickupSelectionStatus::None;
        }

        $start = $cart->requested_pickup_start_at;
        $end = $cart->requested_pickup_end_at;

        if ($start === null || $end === null) {
            // SELECTED with no window is a row that contradicts itself. Read as
            // nothing chosen, because that is the state the customer can act
            // on, and never as a valid selection.
            return PickupSelectionStatus::None;
        }

        $fingerprint = (string) ($cart->pickup_planning_fingerprint ?? '');

        if ($fingerprint === '' || ! hash_equals($plan->fingerprint, $fingerprint)) {
            return PickupSelectionStatus::Stale;
        }

        // Stale is checked before invalid, deliberately. When the facts have
        // moved, "we need to re-check this" is the honest thing to say; calling
        // it invalid would be a judgement made against a plan the selection was
        // never held to.
        if ($plan->refusal !== null) {
            return PickupSelectionStatus::Invalid;
        }

        if ($start <= $now) {
            // The moment has passed. Nothing about the cart is wrong; the clock
            // moved, which is the most ordinary way a plan expires.
            //
            // Subsumed by the membership test below in every shipped
            // configuration — a generated window never starts before the food
            // is ready, so a window in the past has already fallen out of the
            // feasible list. It survives for the one case that is not covered:
            // preparation, buffer and lead all configured to nought make
            // "earliest ready" equal to now, and a window starting exactly now
            // is feasible by that arithmetic and gone by the time anybody
            // walks in.
            return PickupSelectionStatus::Invalid;
        }

        foreach ($plan->allWindows as $window) {
            if ($window->startAt->equalTo($start) && $window->endAt->equalTo($end)) {
                return PickupSelectionStatus::Selected;
            }
        }

        return PickupSelectionStatus::Invalid;
    }
}
