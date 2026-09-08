<?php

declare(strict_types=1);

namespace App\Http\Controllers\Api\V1\Customer;

use App\Enums\ApiErrorCode;
use App\Exceptions\ApiException;
use App\Http\Responses\ApiResponse;
use App\Models\Cart;
use App\Models\CheckoutQuote;
use App\Models\Trip;
use App\Models\User;
use App\Services\Cart\CartService;
use App\Services\Checkout\CheckoutPreparation;
use App\Services\Checkout\CheckoutPreparationService;
use App\Services\Pickup\PickupPlanningService;
use App\Services\Pickup\PickupSelectionEvaluator;
use App\Services\Trip\TripService;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * The last screen before money, and the module that stops one step short of it.
 *
 * Two endpoints. `prepare` answers "what is being bought, when, and for how
 * much"; `validate` answers "is all of that still true". Both are POSTs, and
 * for the reason recorded in docs/05-api-standards.md: these render a
 * point-in-time judgement, and a cached yes is somebody at a payment screen for
 * a kitchen that has shut.
 *
 * **Neither reads money from the request.** A body carrying
 * `payable_total_minor`, `items_subtotal_minor`, `tax_minor` or `discount_minor`
 * parses to exactly the same thing as a body without them, because nothing here
 * or below looks for those keys. That is not "the server validates what it is
 * sent" — there is nowhere to send it.
 *
 * Nothing here creates an order, a payment, or a Razorpay object. Module 15
 * owns that boundary and this module does not reach across it.
 */
final class CheckoutController
{
    public function __construct(
        private readonly TripService $trips,
        private readonly CartService $carts,
        private readonly CheckoutPreparationService $checkout,
        private readonly PickupPlanningService $planning,
        private readonly PickupSelectionEvaluator $evaluator,
    ) {}

    /**
     * Prepares this cart's checkout, or refreshes it.
     *
     * @throws ApiException
     */
    public function prepare(Request $request, string $trip): JsonResponse
    {
        [$customer, $found, $cart] = $this->context($request, $trip);

        $now = CarbonImmutable::now();

        $preparation = $this->checkout->prepare($customer, $found, $cart, $now);

        return ApiResponse::ok($this->payload($cart, $preparation, $now));
    }

    /**
     * Whether this exact quote could still be paid for.
     *
     * @throws ApiException
     */
    public function validate(Request $request, string $trip, string $checkout): JsonResponse
    {
        [$customer, $found, $cart] = $this->context($request, $trip);

        $quote = $this->quoteOrFail($customer, $cart, $checkout);

        $now = CarbonImmutable::now();

        $preparation = $this->checkout->validateQuote($customer, $found, $cart, $quote, $now);

        return ApiResponse::ok($this->payload($cart, $preparation, $now));
    }

    /**
     * The quote named in the path, if it is this customer's and this cart's.
     *
     * Scoped by customer **and** cart in the query itself rather than fetched
     * and then compared. A lookup that finds the row first has already decided
     * the row exists, and the difference between "not yours" and "not real" is
     * exactly what an attacker is trying to learn.
     *
     * **Both clauses, and each is sufficient on its own.** That is deliberate
     * rather than sloppy, and it was measured: removing both opens the hole and
     * the ownership test fails; removing either one leaves the other closing
     * it. Do not delete one as redundant — the redundancy is the point, and the
     * test proves the pair rather than each half.
     *
     * @throws ApiException
     */
    private function quoteOrFail(User $customer, Cart $cart, string $uuid): CheckoutQuote
    {
        $quote = CheckoutQuote::query()
            ->where('uuid', $uuid)
            ->where('customer_id', $customer->id)
            ->where('cart_id', $cart->id)
            ->first();

        if ($quote === null) {
            throw new ApiException(
                ApiErrorCode::CheckoutQuoteNotFound,
                'That checkout is no longer available. Please try again.',
            );
        }

        return $quote;
    }

    /**
     * @return array{0: User, 1: Trip, 2: Cart}
     *
     * @throws ApiException
     */
    private function context(Request $request, string $trip): array
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

        return [$customer, $found, $cart];
    }

    /**
     * One response shape for both handlers.
     *
     * The whole purchase in one body — restaurant, journey, pickup, items,
     * money — because a checkout screen that had to assemble this from four
     * requests would render four moments side by side, and the customer would
     * be asked to agree to the combination.
     *
     * @return array<string, mixed>
     */
    private function payload(Cart $cart, CheckoutPreparation $preparation, CarbonImmutable $now): array
    {
        $plan = $this->planning->plan($cart, $now);
        $quote = $preparation->quote;

        return [
            'checkout_id' => $quote?->uuid,
            'status' => $preparation->status->value,
            'currency' => $cart->currency,

            'restaurant' => [
                'id' => $cart->restaurant?->uuid,
                'name' => $cart->restaurant?->name,
            ],

            // The journey, as context rather than as data to act on. No
            // geometry: a checkout screen showing a polyline would be the
            // heaviest response in the app for a line of text.
            'journey' => [
                'id' => $cart->trip?->uuid,
                // The place names, not the coordinates. A checkout line reads
                // "Delhi to Jaipur"; latitude and longitude on this screen
                // would be data the customer cannot check and did not ask for.
                // Name, then city, then the formatted address. A journey line
                // reading "None to None" is worse than a long one: the customer
                // is being asked to confirm a purchase, and a blank where the
                // destination should be is the sort of thing that stops them.
                'origin' => $this->placeLabel(
                    $cart->trip?->origin_name,
                    $cart->trip?->origin_city,
                    $cart->trip?->origin_formatted_address,
                ),
                'destination' => $this->placeLabel(
                    $cart->trip?->destination_name,
                    $cart->trip?->destination_city,
                    $cart->trip?->destination_formatted_address,
                ),
            ],

            'pickup' => [
                ...$plan->toApiArray(),
                'selection' => [
                    'status' => $this->evaluator->statusFor($cart, $plan, $now)->value,
                    'start_at' => $this->local($cart->requested_pickup_start_at, $cart->pickup_timezone),
                    'end_at' => $this->local($cart->requested_pickup_end_at, $cart->pickup_timezone),
                    'timezone' => $cart->pickup_timezone,
                ],
            ],

            'items' => $cart->items
                ->map(static fn ($item): array => $item->toCustomerArray())
                ->all(),

            'commercial' => $preparation->breakdown->toApiArray(),

            'expires_at' => $quote?->expires_at?->toIso8601String(),

            // The authoritative answer, computed by the backend in one place. A
            // client renders it and must never derive its own.
            'ready_for_payment' => $preparation->readyForPayment(),

            'validation' => $preparation->validation->toApiArray(),
        ];
    }

    /** The first of these a customer could actually read. */
    private function placeLabel(?string ...$candidates): ?string
    {
        foreach ($candidates as $candidate) {
            if (is_string($candidate) && trim($candidate) !== '') {
                return $candidate;
            }
        }

        return null;
    }

    /**
     * A stored UTC instant, on the counter's clock.
     *
     * The rule Module 13 arrived at the hard way, applied here from the start:
     * one response, one clock. A checkout showing the pickup window in UTC
     * beside options in the restaurant's zone is the same moment rendered twice,
     * hours apart.
     */
    private function local(?CarbonImmutable $instant, ?string $zone): ?string
    {
        if ($instant === null) {
            return null;
        }

        return (($zone ?? '') === '' ? $instant : $instant->setTimezone($zone))->toIso8601String();
    }
}
