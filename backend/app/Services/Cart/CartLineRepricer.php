<?php

declare(strict_types=1);

namespace App\Services\Cart;

use App\Enums\ApiErrorCode;
use App\Exceptions\ApiException;
use App\Models\CartItem;
use App\Models\CartItemModifier;
use App\Models\Restaurant;
use App\Services\Menu\CustomerMenuService;

/**
 * What a cart line costs *today*.
 *
 * A line carries snapshots — the dish's name, the size's name, the price at the
 * moment it was added — and those snapshots answer "what did I choose". They do
 * not answer "what do I owe". A price that was authoritative on Tuesday is not
 * a licence to charge it on Thursday, so any operation that changes what a
 * customer will pay goes through here and re-reads the live menu rows.
 *
 * The stored line is turned back into a {@see CustomizationSelection} and put
 * through exactly the same validator and pricing service the original add used.
 * That is deliberate: a second implementation of "what does this dish cost"
 * would be a second thing to keep in step with the first, and the day they
 * disagree the customer is charged by whichever one happens to run.
 *
 * The stored unit price is passed as the customer's quote, so a dish that has
 * gone **up** since it was added is refused with `PRICE_UPDATED` and both
 * figures, rather than quietly costing more. One that has gone **down** is
 * repriced at the lower figure without ceremony — nobody needs a dialogue to
 * be charged less.
 *
 * The line's `configuration_hash` is never recomputed from what this produces.
 * A line added without naming a size (the server picked the default) would
 * fingerprint differently once the size is spelled out, and rewriting the hash
 * would split one line into two the next time the same dish was added.
 */
final class CartLineRepricer
{
    public function __construct(
        private readonly CustomerMenuService $menu,
        private readonly CustomizationValidator $validator,
        private readonly MenuItemPricingService $pricing,
    ) {}

    /**
     * Prices this line at `$quantity`, against the menu as it stands.
     *
     * @throws ApiException
     */
    public function reprice(Restaurant $restaurant, CartItem $line, int $quantity): PricedCustomization
    {
        $selection = $this->selectionFor($line, $quantity);

        $menuItem = $this->menu->itemForCustomization($restaurant, $selection->itemUuid);

        if ($menuItem === null) {
            // Withdrawn from the menu, or its category was. The line stays in
            // the cart and stays visible — the customer removes it, we do not.
            throw new ApiException(
                ApiErrorCode::ItemUnavailable,
                '"'.$line->item_name_snapshot.'" is no longer on the menu.',
                ['cart_item_id' => $line->uuid],
            );
        }

        $resolved = $this->validator->validate($menuItem, $selection);
        $priced = $this->pricing->price($resolved);

        $this->pricing->assertQuoteStillHolds($priced, $selection->quotedUnitPriceMinor);

        return $priced;
    }

    /**
     * The stored line, expressed as the selection that would produce it.
     *
     * Public because price revalidation asks the same question of every line
     * without intending to change anything, and building this twice is how the
     * two answers start to differ.
     *
     * @throws ApiException
     */
    public function selectionFor(CartItem $line, int $quantity): CustomizationSelection
    {
        $itemUuid = $line->menuItem?->uuid;

        if (! is_string($itemUuid) || $itemUuid === '') {
            throw new ApiException(
                ApiErrorCode::ItemUnavailable,
                '"'.$line->item_name_snapshot.'" is no longer on the menu.',
                ['cart_item_id' => $line->uuid],
            );
        }

        $optionUuids = [];

        foreach ($line->modifiers as $modifier) {
            $optionUuids[] = $this->optionUuidOrFail($line, $modifier);
        }

        return CustomizationSelection::of(
            itemUuid: $itemUuid,
            variantUuid: $line->variant?->uuid,
            optionUuids: $optionUuids,
            quantity: $quantity,
            specialInstructions: $line->special_instructions,

            // Not a price to charge. The figure the customer last agreed to,
            // which is what the pricing service compares its own answer against.
            quotedUnitPriceMinor: (int) $line->unit_price_minor,
        );
    }

    /**
     * @throws ApiException
     */
    private function optionUuidOrFail(CartItem $line, CartItemModifier $modifier): string
    {
        $uuid = $modifier->option?->uuid;

        if (is_string($uuid) && $uuid !== '') {
            return $uuid;
        }

        // The option row is gone. Dropping it silently would reprice the dish
        // *without* something the customer chose and charge less for a plate
        // that arrives different from the one they configured, which is worse
        // than refusing.
        throw new ApiException(
            ApiErrorCode::ModifierUnavailable,
            '"'.$modifier->option_name_snapshot.'" is no longer available.',
            [
                'cart_item_id' => $line->uuid,
                'option_name' => $modifier->option_name_snapshot,
            ],
        );
    }
}
