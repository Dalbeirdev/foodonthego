<?php

declare(strict_types=1);

namespace App\Http\Controllers\Api\V1\Customer;

use App\Enums\ApiErrorCode;
use App\Enums\PickupSelectionStatus;
use App\Exceptions\ApiException;
use App\Http\Responses\ApiResponse;
use App\Models\Cart;
use App\Models\User;
use App\Services\Cart\CartService;
use App\Services\Cart\CartTotalsService;
use App\Services\Pickup\PickupOptionSelectionService;
use App\Services\Pickup\PickupOptionStore;
use App\Services\Pickup\PickupPlan;
use App\Services\Pickup\PickupPlanningService;
use App\Services\Pickup\PickupSelectionEvaluator;
use App\Services\Pickup\PreCheckoutValidationService;
use App\Services\Trip\TripService;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Choosing when to collect.
 *
 * Two endpoints. One asks the server what is possible; the other agrees to one
 * of the answers. Between them the client holds an opaque id and no times it
 * could act on — **it never sends a timestamp, and there is no request field
 * here that a customer could edit into a pickup time of their choosing.**
 *
 * Options is a POST rather than a GET, and deliberately: it is a calculation
 * over live state whose result is short-lived and whose side effect is writing
 * that result down. Cacheable it is not, and a GET would invite a client, a
 * proxy or a browser to treat it as though it were.
 *
 * Neither endpoint calls a routing provider. Generating options, switching
 * between them and agreeing to one all read data this platform already holds;
 * the only provider call in this area is a journey refresh the customer asked
 * for, which is Module 06's endpoint and not this one.
 *
 * Ownership is proved the same way as everywhere else: the journey in the path
 * must belong to the caller, and the cart is read from the journey rather than
 * named by the request.
 */
final class PickupController
{
    public function __construct(
        private readonly TripService $trips,
        private readonly CartService $carts,
        private readonly CartTotalsService $totals,
        private readonly PickupPlanningService $planning,
        private readonly PickupOptionStore $options,
        private readonly PickupOptionSelectionService $selection,
        private readonly PickupSelectionEvaluator $evaluator,
        private readonly PreCheckoutValidationService $preCheckout,
    ) {}

    /**
     * What pickup times this cart could have.
     *
     * Returns the arithmetic as well as the answers — travel, cooking, the
     * handover buffer — because a list of times with no explanation is a list a
     * customer has to take on trust, and the first one that looks wrong is the
     * one that loses them.
     *
     * A refusal comes back as a normal response with `is_feasible` false and a
     * reason, not an error: "you would arrive after they close" is information
     * the screen should render, not a failure it should apologise for. The
     * exceptions are the conditions that need the customer to go and do
     * something else first, which are raised as errors so a client cannot show
     * an empty list and leave them there.
     *
     * @throws ApiException
     */
    public function options(Request $request, string $trip): JsonResponse
    {
        [$customer, $cart] = $this->cartOrFail($request, $trip);

        $plan = $this->planning->plan($cart, CarbonImmutable::now());

        if ($plan->refusal === ApiErrorCode::CartEmpty) {
            throw new ApiException(
                ApiErrorCode::CartEmpty,
                'Your cart is empty.',
            );
        }

        return ApiResponse::ok($this->payload($cart, $plan));
    }

    /**
     * Agrees to one of them.
     *
     * The body carries `pickup_option_id` and nothing else. Every condition is
     * checked again by {@see PickupOptionSelectionService} — the option's owner,
     * its cart, the facts it was planned under, and whether the window is still
     * one the kitchen can honour — because the plan that produced it was true
     * when it was produced and this is a different moment.
     *
     * No order is created. No payment is created. No capacity is reserved. Four
     * columns on a cart record what the customer would like, and Module 14 will
     * check all of it again before anybody is charged.
     *
     * @throws ApiException
     */
    public function select(Request $request, string $trip): JsonResponse
    {
        [$customer, $cart] = $this->cartOrFail($request, $trip);

        $selected = $this->selection->select(
            $customer,
            $cart,
            $this->readOptionId($request),
            CarbonImmutable::now(),
        );

        // Re-planned so the response describes the world as it is after the
        // selection rather than as it was before it, and so the alternatives a
        // customer sees beside their choice are current.
        $reloaded = $selected->fresh(['items.menuItem', 'items.variant', 'items.modifiers', 'restaurant.openingHours', 'trip.selectedRoute', 'customer'])
            ?? $selected;

        return ApiResponse::ok(
            $this->payload($reloaded, $this->planning->plan($reloaded, CarbonImmutable::now())),
        );
    }

    /**
     * Whether this cart could be paid for, if there were anywhere to pay.
     *
     * Module 12's revalidation and Module 13's pickup layer, in one answer,
     * with `ready_for_checkout` computed by the server and every reason it is
     * not listed beside it.
     *
     * **A POST, and it writes nothing.** The verb is not about side effects
     * here — it is about caching: this is a point-in-time go/no-go, and a GET
     * invites a client, a proxy or a browser to reuse a yes that was true a
     * minute ago. Module 12's `revalidate` reports facts and is a GET; this
     * renders a judgement, and a stale judgement is the one that gets somebody
     * to a payment screen for a kitchen that has closed.
     *
     * No order is created, no payment is created, nothing is reserved, and the
     * cart's stored selection is not corrected on the customer's behalf.
     *
     * @throws ApiException
     */
    public function preCheckout(Request $request, string $trip): JsonResponse
    {
        /** @var User $customer */
        $customer = $request->user();

        $found = $this->trips->ownedByOrFail($customer, $trip);

        $cart = $this->carts->activeCartWithLines($customer, $found);

        if ($cart === null) {
            throw new ApiException(
                ApiErrorCode::CartNotFound,
                'You do not have a cart on this journey.',
            );
        }

        $cart->setRelation('trip', $found);
        $cart->loadMissing(['restaurant.openingHours', 'customer']);

        $now = CarbonImmutable::now();

        $validation = $this->preCheckout->validate($found, $cart, $now);

        return ApiResponse::ok([
            'cart' => $cart->toCustomerArray($this->totals->totalsFor($cart)),
            'revalidation' => $validation->revalidation->toApiArray(),
            'pickup' => [
                ...$validation->plan->toApiArray(),
                'selection' => $this->selectionArray($cart, $validation->selectionStatus),
            ],

            // The authoritative answer, and the whole reason this endpoint
            // exists. A client must render it, never derive its own.
            ...$validation->toApiArray(),
        ]);
    }

    /**
     * The cart on this journey, or a refusal.
     *
     * @return array{0: User, 1: Cart}
     *
     * @throws ApiException
     */
    private function cartOrFail(Request $request, string $trip): array
    {
        /** @var User $customer */
        $customer = $request->user();

        $found = $this->trips->ownedByOrFail($customer, $trip);

        $cart = $this->carts->activeCartWithLines($customer, $found);

        if ($cart === null) {
            throw new ApiException(
                ApiErrorCode::CartNotFound,
                'You do not have a cart on this journey.',
            );
        }

        $cart->setRelation('trip', $found);
        $cart->loadMissing(['restaurant.openingHours', 'customer']);

        return [$customer, $cart];
    }

    /**
     * One response shape for both handlers.
     *
     * The cart travels with it because both screens show the order beside the
     * time, and a client that had to fetch the cart separately would render the
     * two a request apart — which is how a customer sees a pickup time for an
     * order they have already changed.
     *
     * Option ids are minted fresh on every call, including after a selection.
     * They are meant to lapse, and re-using the previous call's ids would keep
     * a menu of times alive long after the plan that produced it.
     *
     * @return array<string, mixed>
     */
    private function payload(Cart $cart, PickupPlan $plan): array
    {
        $ids = $this->options->put($cart, $plan);

        $options = [];

        foreach ($plan->windows as $index => $window) {
            $options[] = [
                'id' => $ids[$index],
                ...$window->toApiArray(),
                'is_recommended' => $plan->recommended !== null
                    && $window->startAt->equalTo($plan->recommended->startAt),
            ];
        }

        $recommended = null;

        foreach ($options as $option) {
            if ($option['is_recommended'] === true) {
                $recommended = $option['id'];

                break;
            }
        }

        return [
            'cart' => $cart->toCustomerArray($this->totals->totalsFor($cart)),
            'pickup' => [
                ...$plan->toApiArray(),
                'selection' => $this->selectionArray(
                    $cart,
                    $this->evaluator->statusFor($cart, $plan, $plan->serverNow),
                ),
                'recommended_option_id' => $recommended,
                'options' => $options,
            ],
        ];
    }

    /**
     * What the customer has chosen so far, if anything.
     *
     * The stored fingerprint is NOT returned. It is an internal comparison
     * value; publishing it would tell a client what the server hashes and
     * invite one to try reproducing it, and no screen has any use for it.
     *
     * @return array<string, mixed>
     */
    private function selectionArray(Cart $cart, PickupSelectionStatus $status): array
    {
        return [
            // The DERIVED status, not the stored column. A cart reading
            // SELECTED while the restaurant has since edited its hours is not
            // wrong because a job failed to run — a column cannot know. See
            // {@see PickupSelectionEvaluator}.
            'status' => $status->value,
            'start_at' => $cart->requested_pickup_start_at?->toIso8601String(),
            'end_at' => $cart->requested_pickup_end_at?->toIso8601String(),
            'timezone' => $cart->pickup_timezone,
            'selected_at' => $cart->pickup_selected_at?->toIso8601String(),
        ];
    }

    /**
     * The option id from the body.
     *
     * Strict about the type. A client that sends an array, a number or nothing
     * at all has a bug, and coercing it would turn that bug into a lookup
     * against a key built from whatever it happened to send.
     *
     * @throws ApiException
     */
    private function readOptionId(Request $request): string
    {
        $value = $request->input('pickup_option_id');

        if (! is_string($value) || $value === '') {
            throw new ApiException(
                ApiErrorCode::ValidationFailed,
                'Choose a pickup time.',
                ['pickup_option_id' => ['A pickup time must be chosen.']],
            );
        }

        return $value;
    }
}
