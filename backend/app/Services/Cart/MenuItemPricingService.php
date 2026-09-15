<?php

declare(strict_types=1);

namespace App\Services\Cart;

use App\Enums\ApiErrorCode;
use App\Exceptions\ApiException;
use App\Support\Money;

/**
 * What a configured dish costs.
 *
 * **The only place in the application that decides a price.** The controller
 * does not, the model does not, and the client certainly does not — the client
 * shows a preview so the screen feels responsive, and this class is what the
 * customer is actually charged by.
 *
 * The formula:
 *
 *     variant price (or the item's base price, when there are no sizes)
 *   + each chosen option's delta
 *   = unit price
 *   × quantity
 *   = line total
 *
 * All of it in integer minor units, from rows read in the same request. There
 * is no floating point anywhere in the path, and nothing is read from the
 * request body except *which* rows to read.
 */
final class MenuItemPricingService
{
    /**
     * @throws ApiException
     */
    public function price(ResolvedCustomization $resolved): PricedCustomization
    {
        $base = $this->baseOf($resolved);
        $currency = $base->currency;

        $unitMinor = $base->minor;
        $additions = [];

        foreach ($resolved->modifiers as $pair) {
            $delta = $pair['option']->priceDelta();

            if ($delta === null) {
                // A corrupt price on an option the customer has chosen. The add
                // is refused rather than quietly treated as free — a dish
                // costing less than it should is still a dish nobody can
                // defend at the counter.
                throw $this->unpriceable();
            }

            if ($delta->currency !== $currency) {
                // Two currencies in one dish. Impossible through the UI and
                // conceivable through a bad import, and adding them would
                // produce a number with no meaning.
                throw $this->unpriceable();
            }

            $unitMinor += $delta->minor;

            // Free options are listed too. "Mild — no charge" is worth seeing:
            // it confirms the choice landed, and its absence from a breakdown
            // reads like it did not.
            $additions[] = [
                'group' => (string) $pair['group']->name,
                'name' => (string) $pair['option']->name,
                'amount' => $delta,
            ];
        }

        $unitPrice = Money::fromMinor($unitMinor, $currency);

        return new PricedCustomization(
            base: $base,
            additions: $additions,
            unitPrice: $unitPrice,
            quantity: $resolved->quantity,
            lineTotal: Money::fromMinor($unitMinor * $resolved->quantity, $currency),
            baseLabel: $resolved->variant?->name ?? $resolved->item->name,
        );
    }

    /**
     * The dish's own price: the chosen size's, or the item's.
     *
     * A variant price is **absolute**, so it replaces the base rather than
     * adding to it. That is the whole reason the column is absolute — see the
     * migration.
     *
     * @throws ApiException
     */
    private function baseOf(ResolvedCustomization $resolved): Money
    {
        $price = $resolved->variant?->price() ?? $resolved->item->price();

        if ($price === null) {
            throw $this->unpriceable();
        }

        return $price;
    }

    private function unpriceable(): ApiException
    {
        // Deliberately vague to the customer and specific in the logs: the
        // detail is a data fault on our side, and reciting it on a menu screen
        // helps nobody.
        return new ApiException(
            ApiErrorCode::ItemUnavailable,
            'That item is not available right now.',
        );
    }

    /**
     * Whether the customer may be charged this, given what they were shown.
     *
     * The one rule: **never more than the figure on their screen.** If the
     * dish has gone up since the page loaded, the add is refused and the new
     * price is returned, so the customer agrees to it before it is charged. If
     * it has gone *down*, it proceeds at the lower price — nobody needs a
     * confirmation dialogue to be charged less.
     *
     * The client's quoted figure is never used to price anything. Sending a
     * high one gets the real price; sending a low one gets a refusal.
     *
     * @throws ApiException
     */
    public function assertQuoteStillHolds(
        PricedCustomization $priced,
        ?int $quotedUnitPriceMinor,
    ): void {
        if ($quotedUnitPriceMinor === null) {
            // The client did not say what it showed. Nothing to compare
            // against, and the server's price stands.
            return;
        }

        if ($priced->unitPrice->minor <= $quotedUnitPriceMinor) {
            return;
        }

        throw new ApiException(
            ApiErrorCode::PriceUpdated,
            'The price of this item has changed. Review it before adding.',
            [
                'quoted_unit_price' => [
                    'amount_minor' => $quotedUnitPriceMinor,
                    'currency' => $priced->unitPrice->currency,
                ],
                'current_unit_price' => $priced->unitPrice->toApiArray(),
                'current_line_total' => $priced->lineTotal->toApiArray(),
            ],
        );
    }
}
