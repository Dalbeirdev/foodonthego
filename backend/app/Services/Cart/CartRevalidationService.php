<?php

declare(strict_types=1);

namespace App\Services\Cart;

use App\Enums\CartRevalidationFinding;
use App\Exceptions\ApiException;
use App\Models\Cart;
use App\Models\CartItem;
use App\Models\Trip;
use App\Services\Restaurant\RestaurantDetailService;
use App\Support\Money;
use Carbon\CarbonImmutable;

/**
 * Whether a cart still means what it said.
 *
 * The snapshot on a line answers *"what did I choose"*. This answers *"what do
 * I owe"*. Keeping those separate is what stops a renamed dish rewriting
 * history and a stale price becoming a charge.
 *
 * **Nothing here writes.** Not a price, not a quantity, not a status. Every
 * method below reads live menu rows, compares them to the line, and reports.
 * The customer decides what happens next, because a total that corrects itself
 * between the screen and the payment is the thing customers do not forgive.
 *
 * Every line is checked, and a line that fails does not stop the ones after it.
 * A customer who has to fix three things wants to be told about three things,
 * not the first one three times.
 *
 * No routing provider is called. The restaurant's ordering state comes from
 * Module 07's cached discovery result, exactly as adding to the cart does.
 */
final class CartRevalidationService
{
    public function __construct(
        private readonly RestaurantDetailService $detail,
        private readonly CartLineRepricer $repricer,
        private readonly CartTotalsService $totals,
    ) {}

    public function revalidate(Trip $trip, Cart $cart, ?CarbonImmutable $now = null): CartRevalidation
    {
        $now ??= CarbonImmutable::now();

        $accepting = $this->isAcceptingOrders($trip, $cart, $now);

        $lines = [];
        $liveSubtotal = 0;
        $priceable = true;

        foreach ($cart->items as $line) {
            $verdict = $this->verdictFor($cart, $line);

            $lines[] = $verdict;

            if ($verdict->priceNow === null) {
                $priceable = false;

                continue;
            }

            $liveSubtotal += $verdict->priceNow->minor * (int) $line->quantity;
        }

        return new CartRevalidation(
            lines: $lines,
            restaurantAcceptingOrders: $accepting,

            // Withheld the moment one line cannot be priced. A total worked out
            // around a missing dish describes a cart nobody has.
            totalsIfAccepted: $priceable
                ? $this->totals->totalsForSubtotal($cart, $liveSubtotal)
                : null,
        );
    }

    /**
     * One line, checked against the menu as it stands.
     *
     * The check is Module 11's validator and Module 11's pricing service, run
     * over the stored line. Writing a second set of availability rules for this
     * screen would produce a cart that revalidates clean and then refuses at
     * the counter.
     */
    private function verdictFor(Cart $cart, CartItem $line): CartLineVerdict
    {
        $wasPaid = Money::fromMinor((int) $line->unit_price_minor, (string) $line->currency);

        $restaurant = $cart->restaurant;

        if ($restaurant === null) {
            return new CartLineVerdict(
                cartItemId: (string) $line->uuid,
                name: (string) $line->item_name_snapshot,
                variantName: $line->variant_name_snapshot,
                quantity: (int) $line->quantity,
                finding: CartRevalidationFinding::ItemUnavailable,
                priceWhenAdded: $wasPaid,
                priceNow: null,
                message: 'This restaurant is no longer available.',
            );
        }

        try {
            $priced = $this->repricer->priceNow($restaurant, $line, (int) $line->quantity);
        } catch (ApiException $e) {
            // The refusal an add would have given, turned into something a cart
            // screen can render. The original code travels with it, so the
            // screen can be specific where the finding is coarse.
            return new CartLineVerdict(
                cartItemId: (string) $line->uuid,
                name: (string) $line->item_name_snapshot,
                variantName: $line->variant_name_snapshot,
                quantity: (int) $line->quantity,
                finding: CartRevalidationFinding::forErrorCode($e->errorCode),
                priceWhenAdded: $wasPaid,
                priceNow: null,
                message: $e->getMessage(),
                sourceCode: $e->errorCode->value,
            );
        }

        $nowCosts = $priced->unitPrice;

        $finding = match (true) {
            $nowCosts->minor > $wasPaid->minor => CartRevalidationFinding::PriceIncreased,
            $nowCosts->minor < $wasPaid->minor => CartRevalidationFinding::PriceDecreased,
            default => null,
        };

        return new CartLineVerdict(
            cartItemId: (string) $line->uuid,
            name: (string) $line->item_name_snapshot,
            variantName: $line->variant_name_snapshot,
            quantity: (int) $line->quantity,
            finding: $finding,
            priceWhenAdded: $wasPaid,
            priceNow: $nowCosts,

            // No message on a settled line. A screen that has to filter out
            // "nothing wrong" strings is a screen somebody will get wrong.
            message: match ($finding) {
                CartRevalidationFinding::PriceIncreased => 'The price of this item has gone up.',
                CartRevalidationFinding::PriceDecreased => 'This item now costs less.',
                default => null,
            },
        );
    }

    /**
     * Whether the kitchen would take this order right now.
     *
     * The same question the add path asks, through the same cached discovery
     * result — so a restaurant that has paused, closed, been suspended or
     * fallen off this journey's route answers the same on both screens.
     *
     * A refusal from that path is an answer, not an error: "not accepting
     * orders" is exactly what a customer needs to be told, and throwing here
     * would replace a cart screen listing four fixable problems with one error
     * page naming none of them.
     */
    private function isAcceptingOrders(Trip $trip, Cart $cart, CarbonImmutable $now): bool
    {
        $uuid = $cart->restaurant?->uuid;

        if (! is_string($uuid) || $uuid === '') {
            return false;
        }

        try {
            return $this->detail->orderingContext($trip, $uuid, $now)->ordering->canOrder();
        } catch (ApiException) {
            return false;
        }
    }
}
