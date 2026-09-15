<?php

declare(strict_types=1);

namespace App\Services\Pickup;

use App\Enums\ApiErrorCode;
use App\Enums\PickupSelectionStatus;
use App\Exceptions\ApiException;
use App\Models\Cart;
use App\Models\User;
use Carbon\CarbonImmutable;

/**
 * Agreeing to one of the times the server offered.
 *
 * The request carries an id and nothing else. No timestamp, no duration, no
 * restaurant, no price — so there is nothing in it to tamper with, and the
 * server is not trusting a client with any part of the answer.
 *
 * **Every condition is checked again here.** The plan that produced the option
 * was true when it was produced; between then and now the cart may have gained a
 * slow dish, the restaurant may have stopped taking orders or edited its hours,
 * the route may have aged out, and the window itself may simply have passed. An
 * option is a note of what was offered, never a promise that it still stands.
 *
 * Nothing about this creates an order. It writes four columns on a cart, and
 * Module 14 will revalidate the lot again before anybody is charged.
 */
final class PickupOptionSelectionService
{
    public function __construct(
        private readonly PickupPlanningService $planning,
        private readonly PickupOptionStore $store,
    ) {}

    /**
     * @throws ApiException
     */
    public function select(User $customer, Cart $cart, string $optionId, ?CarbonImmutable $now = null): Cart
    {
        $now = $now ?? CarbonImmutable::now();

        $record = $this->store->find((string) $customer->uuid, $optionId);

        if ($record === null) {
            // Expired, never existed, or somebody else's. One answer for all
            // three: distinguishing them would confirm which ids are real to
            // anybody who tried a few.
            throw new ApiException(
                ApiErrorCode::PickupOptionExpired,
                'That pickup time is no longer available. Please choose again.',
            );
        }

        // The store's keys are already scoped to the customer, so this cannot
        // fail today. It is here because the guarantee it protects — one
        // customer cannot use another's option — is the one the specification
        // calls mandatory, and a guarantee that rests on a single line of key
        // construction rests on one line too few.
        if (! hash_equals((string) $customer->uuid, $record->customerUuid)) {
            throw new ApiException(
                ApiErrorCode::PickupOptionForbidden,
                'That pickup time is no longer available. Please choose again.',
            );
        }

        // The customer's own option, from a different cart or a different
        // journey. A genuine mistake for a client that kept an id too long, and
        // a genuine attempt at reuse otherwise; either way it is refused,
        // because a window costed against one cart says nothing about another.
        if (
            ! hash_equals((string) $cart->uuid, $record->cartUuid)
            || ! hash_equals((string) $cart->trip?->uuid, $record->tripUuid)
            || ! hash_equals((string) $cart->restaurant?->uuid, $record->restaurantUuid)
        ) {
            throw new ApiException(
                ApiErrorCode::PickupOptionForbidden,
                'That pickup time belongs to a different order.',
            );
        }

        $plan = $this->planning->plan($cart, $now);

        if ($plan->refusal !== null) {
            // Whatever now stops a plan being made stops this selection too,
            // and the customer is told the same thing they would have been told
            // asking for options afresh.
            throw new ApiException(
                $plan->refusal,
                $this->refusalMessage($plan->refusal),
            );
        }

        if (! hash_equals($plan->fingerprint, $record->fingerprint)) {
            // The facts moved. The window may well still be fine — but nobody
            // has checked it against what is true now, and a plan nobody has
            // checked is not a plan to take to a checkout.
            throw new ApiException(
                ApiErrorCode::PickupOptionStale,
                'Your order has changed since you chose that pickup time. Please choose again.',
            );
        }

        $chosen = $this->stillOffered($plan, $record);

        if ($chosen === null) {
            throw new ApiException(
                $this->whyNotOffered($plan, $record, $now),
                'That pickup time is no longer available. Please choose again.',
            );
        }

        $this->write($cart, $chosen, $plan);

        $this->store->forget((string) $customer->uuid, $record->token);

        return $cart->refresh();
    }

    /**
     * The chosen window, if the current plan still contains it.
     *
     * Matched against every feasible window rather than the handful that were
     * offered: minutes have passed, the offered list has slid forward, and a
     * window that has merely fallen off the top of it is still one the kitchen
     * can honour.
     */
    private function stillOffered(PickupPlan $plan, PickupOptionRecord $record): ?PickupWindow
    {
        foreach ($plan->allWindows as $window) {
            if ($window->startAt->equalTo($record->startAt) && $window->endAt->equalTo($record->endAt)) {
                return $window;
            }
        }

        return null;
    }

    /**
     * Which kind of no this is.
     *
     * Three codes rather than one, because the customer's next move differs:
     * a time that has simply passed wants the next slot, a time the kitchen can
     * no longer make wants a later one, and a time outside opening hours wants a
     * different day.
     */
    private function whyNotOffered(
        PickupPlan $plan,
        PickupOptionRecord $record,
        CarbonImmutable $now,
    ): ApiErrorCode {
        if ($record->startAt <= $now) {
            return ApiErrorCode::PickupTimeInvalid;
        }

        if ($plan->earliestReadyAt !== null && $record->startAt < $plan->earliestReadyAt) {
            return ApiErrorCode::PickupBeforeReady;
        }

        return ApiErrorCode::PickupOutsideHours;
    }

    /**
     * Records the intent.
     *
     * `forceFill` against columns this method names, never a request array.
     * The customer cannot set the cart's status, its restaurant, its journey,
     * its version, its selection status, the durations behind it, or the
     * fingerprint — every one of those is decided here from server state, and
     * the request contributed a single opaque id.
     *
     * The version is deliberately NOT bumped. Choosing a pickup time changes
     * nothing about the cart's contents, and incrementing it would invalidate
     * the very fingerprint being written in the same statement.
     */
    private function write(Cart $cart, PickupWindow $window, PickupPlan $plan): void
    {
        $cart->forceFill([
            'pickup_selection_status' => PickupSelectionStatus::Selected->value,

            // **Converted to UTC before it is written, explicitly.** The window
            // is carried in the restaurant's own zone, because that is the
            // clock the pickup happens on — and Eloquent writes a zoned
            // date-time by formatting it, not by converting it. A Kolkata
            // window handed straight to a UTC column stores its wall time and
            // is silently five and a half hours out: a pickup at half past one
            // that the database believes is at eight in the morning.
            //
            // The zone is not lost by this. It travels in `pickup_timezone`
            // beside the instants, which is the honest split — an instant is
            // absolute, a clock face is local, and conflating them is how the
            // afternoon becomes the morning.
            'requested_pickup_start_at' => $window->startAt->setTimezone('UTC'),
            'requested_pickup_end_at' => $window->endAt->setTimezone('UTC'),
            'pickup_timezone' => $plan->timezone,
            'pickup_selected_at' => $plan->serverNow->setTimezone('UTC'),
            'pickup_planning_fingerprint' => $plan->fingerprint,
        ])->save();
    }

    private function refusalMessage(ApiErrorCode $code): string
    {
        return match ($code) {
            ApiErrorCode::CartEmpty => 'Your cart is empty.',
            ApiErrorCode::RestaurantNotAcceptingOrders => 'This restaurant has paused new orders.',
            ApiErrorCode::RestaurantUnavailable => 'This restaurant is no longer available.',
            ApiErrorCode::RestaurantOutsideRoute => 'This restaurant is no longer on your journey.',
            ApiErrorCode::RouteStale, ApiErrorCode::RouteNotReady => 'Refresh your journey to get current pickup times.',
            ApiErrorCode::NoFeasiblePickupWindow => 'There are no pickup times available for this order.',
            default => 'That pickup time is no longer available. Please choose again.',
        };
    }
}
