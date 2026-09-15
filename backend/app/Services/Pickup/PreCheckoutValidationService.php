<?php

declare(strict_types=1);

namespace App\Services\Pickup;

use App\Enums\ApiErrorCode;
use App\Enums\CartRevalidationFinding;
use App\Enums\PickupSelectionStatus;
use App\Enums\PreCheckoutIssue;
use App\Models\Cart;
use App\Models\Trip;
use App\Services\Cart\CartRevalidation;
use App\Services\Cart\CartRevalidationService;
use Carbon\CarbonImmutable;

/**
 * The last check before a checkout that does not exist yet.
 *
 * Module 12 asks whether the cart still means what it said. This asks that and
 * then whether the pickup time still stands, and turns both into one answer the
 * customer can act on.
 *
 * **It creates nothing and changes nothing.** No order, no payment, no
 * reservation, no held capacity, not even the cart's selection status — the
 * stored status records what the customer chose, and this service reports what
 * has become of it without writing that conclusion back. A validator that
 * corrected the thing it was validating would be a validator whose second run
 * disagrees with its first.
 *
 * It calls no routing provider either. Everything here is rows this platform
 * already holds, plus arithmetic.
 */
final class PreCheckoutValidationService
{
    public function __construct(
        private readonly CartRevalidationService $revalidation,
        private readonly PickupPlanningService $planning,
        private readonly PickupSelectionEvaluator $evaluator,
    ) {}

    public function validate(Trip $trip, Cart $cart, ?CarbonImmutable $now = null): PreCheckoutValidation
    {
        $now ??= CarbonImmutable::now();

        $revalidation = $this->revalidation->revalidate($trip, $cart, $now);
        $plan = $this->planning->plan($cart, $now);
        $status = $this->evaluator->statusFor($cart, $plan, $now);

        $issues = [
            ...$this->cartIssues($cart, $revalidation),
            ...$this->planIssues($plan),
            ...$this->selectionIssues($status, $plan),
        ];

        return new PreCheckoutValidation(
            revalidation: $revalidation,
            plan: $plan,
            selectionStatus: $status,
            issues: array_values($issues),
        );
    }

    /**
     * What Module 12 found, expressed as things standing in the way.
     *
     * One issue per kind rather than one per line. The line-by-line detail is
     * already in the revalidation block of the same response, and repeating it
     * here would give a screen two lists of the same problems to keep in step.
     *
     * @return list<array{issue: PreCheckoutIssue, message: string}>
     */
    private function cartIssues(Cart $cart, CartRevalidation $revalidation): array
    {
        if (! $cart->isActive() || $cart->items->isEmpty()) {
            return [$this->issue(PreCheckoutIssue::CartEmpty, 'Your cart is empty.')];
        }

        $issues = [];

        $unavailable = 0;
        $risen = 0;
        $fallen = 0;

        foreach ($revalidation->lines as $line) {
            if ($line->blocksOrdering()) {
                $unavailable++;

                continue;
            }

            $risen += $line->finding === CartRevalidationFinding::PriceIncreased ? 1 : 0;
            $fallen += $line->finding === CartRevalidationFinding::PriceDecreased ? 1 : 0;
        }

        if ($unavailable > 0) {
            $issues[] = $this->issue(
                PreCheckoutIssue::LineUnavailable,
                $unavailable === 1
                    ? 'One item in your cart is no longer available.'
                    : $unavailable.' items in your cart are no longer available.',
            );
        }

        if ($risen > 0) {
            // Blocking, and the specification is explicit about it: never yes
            // over a price rise the customer has not seen.
            $issues[] = $this->issue(
                PreCheckoutIssue::PriceIncreased,
                $risen === 1
                    ? 'The price of one item has gone up since you added it.'
                    : 'The prices of '.$risen.' items have gone up since you added them.',
            );
        }

        if ($fallen > 0) {
            $issues[] = $this->issue(
                PreCheckoutIssue::PriceDecreased,
                $fallen === 1
                    ? 'One item now costs less than when you added it.'
                    : $fallen.' items now cost less than when you added them.',
            );
        }

        if (! $revalidation->restaurantAcceptingOrders) {
            $issues[] = $this->issue(
                PreCheckoutIssue::RestaurantNotAcceptingOrders,
                'This restaurant has paused new orders.',
            );
        }

        return $issues;
    }

    /**
     * Why no plan could be made, when none could.
     *
     * A paused kitchen appears in both halves of this service — the cart's
     * revalidation notices it and so does the planner — and it is reported once.
     * Two entries saying the same thing is a screen listing a problem twice.
     *
     * @return list<array{issue: PreCheckoutIssue, message: string}>
     */
    private function planIssues(PickupPlan $plan): array
    {
        return match ($plan->refusal) {
            null, ApiErrorCode::CartEmpty, ApiErrorCode::RestaurantNotAcceptingOrders => [],

            ApiErrorCode::RestaurantUnavailable => [$this->issue(
                PreCheckoutIssue::RestaurantUnavailable,
                'This restaurant is no longer available.',
            )],

            ApiErrorCode::RestaurantOutsideRoute => [$this->issue(
                PreCheckoutIssue::RestaurantOffRoute,
                'This restaurant is no longer on your journey.',
            )],

            ApiErrorCode::RouteStale, ApiErrorCode::RouteNotReady => [$this->issue(
                PreCheckoutIssue::RouteStale,
                'Refresh your journey to get current pickup times.',
            )],

            ApiErrorCode::NoFeasiblePickupWindow => [$this->issue(
                PreCheckoutIssue::NoFeasiblePickupWindow,
                'There are no pickup times available for this order.',
            )],

            // A refusal nobody has mapped still blocks. The safe reading of a
            // reason this service does not recognise is that the pickup cannot
            // be planned — never that it can.
            default => [$this->issue(
                PreCheckoutIssue::NoFeasiblePickupWindow,
                'There are no pickup times available for this order.',
            )],
        };
    }

    /**
     * @return list<array{issue: PreCheckoutIssue, message: string}>
     */
    private function selectionIssues(PickupSelectionStatus $status, PickupPlan $plan): array
    {
        // Nothing to say about a selection when no pickup could be planned at
        // all. The customer's problem is the plan, and stacking "and your
        // pickup time is invalid" on top of "this restaurant has closed" is
        // noise dressed as thoroughness.
        if ($plan->refusal !== null && $plan->refusal !== ApiErrorCode::CartEmpty) {
            return [];
        }

        return match ($status) {
            PickupSelectionStatus::Selected => [],

            PickupSelectionStatus::None => [$this->issue(
                PreCheckoutIssue::NoPickupTimeSelected,
                'Choose a pickup time.',
            )],

            PickupSelectionStatus::Stale => [$this->issue(
                PreCheckoutIssue::PickupTimeStale,
                'Your order has changed since you chose a pickup time. Please choose again.',
            )],

            PickupSelectionStatus::Invalid => [$this->issue(
                PreCheckoutIssue::PickupTimeInvalid,
                'That pickup time is no longer available. Please choose again.',
            )],
        };
    }

    /**
     * @return array{issue: PreCheckoutIssue, message: string}
     */
    private function issue(PreCheckoutIssue $issue, string $message): array
    {
        return ['issue' => $issue, 'message' => $message];
    }
}
