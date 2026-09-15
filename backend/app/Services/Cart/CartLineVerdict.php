<?php

declare(strict_types=1);

namespace App\Services\Cart;

use App\Enums\CartRevalidationFinding;
use App\Support\Money;

/**
 * What revalidation found on one cart line.
 *
 * A line with nothing wrong has no finding, and says so with both prices
 * anyway. "Unchanged" is worth stating: a screen that only lists problems
 * leaves the customer wondering whether the rest was checked.
 */
final readonly class CartLineVerdict
{
    public function __construct(
        public string $cartItemId,
        public string $name,
        public ?string $variantName,
        public int $quantity,
        public ?CartRevalidationFinding $finding,
        public Money $priceWhenAdded,
        public ?Money $priceNow,
        public ?string $message = null,
        public ?string $sourceCode = null,
    ) {}

    public function isSettled(): bool
    {
        return $this->finding === null;
    }

    public function blocksOrdering(): bool
    {
        return $this->finding?->blocksOrdering() ?? false;
    }

    /**
     * @return array<string, mixed>
     */
    public function toApiArray(): array
    {
        return [
            'cart_item_id' => $this->cartItemId,
            'name' => $this->name,
            'variant_name' => $this->variantName,
            'quantity' => $this->quantity,
            'finding' => $this->finding?->value,
            'blocks_ordering' => $this->blocksOrdering(),
            'message' => $this->message,

            // The refusal the pricing path would have given, when there was
            // one. The finding is the coarse bucket a screen branches on; this
            // is what lets it say "Choose a spice level" rather than "something
            // about the options changed".
            'source_code' => $this->sourceCode,

            'price_when_added' => $this->priceWhenAdded->toApiArray(),

            // Null when the line cannot be priced at all. Not zero: a dish that
            // cannot be bought does not cost nothing.
            'price_now' => $this->priceNow?->toApiArray(),
        ];
    }
}
