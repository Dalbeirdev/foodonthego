<?php

declare(strict_types=1);

namespace App\Services\Cart;

/**
 * Whether a cart still means what it said.
 *
 * The answer to "may I order this", and nothing more. **Revalidation changes
 * no rows.** It does not correct a price, remove a sold-out line or adjust a
 * quantity, because a total that changes itself between the screen and the
 * payment is the thing customers do not forgive.
 */
final readonly class CartRevalidation
{
    /**
     * @param  list<CartLineVerdict>  $lines
     */
    public function __construct(
        public array $lines,
        public bool $restaurantAcceptingOrders,
        public ?CartTotals $totalsIfAccepted,
    ) {}

    /** Whether the customer can proceed to order as things stand. */
    public function canProceed(): bool
    {
        if (! $this->restaurantAcceptingOrders) {
            return false;
        }

        foreach ($this->lines as $line) {
            if ($line->blocksOrdering()) {
                return false;
            }
        }

        return true;
    }

    /** Whether anything at all moved, price changes included. */
    public function isUnchanged(): bool
    {
        foreach ($this->lines as $line) {
            if (! $line->isSettled()) {
                return false;
            }
        }

        return $this->restaurantAcceptingOrders;
    }

    /**
     * @return array<string, mixed>
     */
    public function toApiArray(): array
    {
        return [
            'can_proceed' => $this->canProceed(),
            'unchanged' => $this->isUnchanged(),
            'restaurant_accepting_orders' => $this->restaurantAcceptingOrders,
            'lines' => array_map(
                static fn (CartLineVerdict $line): array => $line->toApiArray(),
                $this->lines,
            ),

            // What the cart would cost if the customer accepted every price
            // change on this screen.
            //
            // Null the moment any line cannot be priced. A total computed
            // around a missing dish is a figure for a cart nobody has: the
            // customer has to decide what happens to that line first, and a
            // number offered before that decision is a guess at what they will
            // choose.
            'totals_if_accepted' => $this->totalsIfAccepted?->toApiArray(),
        ];
    }
}
