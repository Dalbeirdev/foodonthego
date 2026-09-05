<?php

declare(strict_types=1);

namespace App\Services\Cart;

use App\Models\Cart;
use App\Models\CartItem;

/** What happened when a dish was added. */
final readonly class CartAddition
{
    public function __construct(
        public Cart $cart,
        public CartItem $item,
        public PricedCustomization $priced,
        /** True when this went into a line the customer already had. */
        public bool $merged,
    ) {}

    /** @return array<string, mixed> */
    public function toApiArray(): array
    {
        return [
            'cart_id' => $this->cart->uuid,
            'cart_item_id' => $this->item->uuid,
            'merged_with_existing_line' => $this->merged,
            'quantity' => (int) $this->item->quantity,
            'unit_price' => $this->item->unitPrice()?->toApiArray(),
            'line_total' => $this->item->lineTotal()?->toApiArray(),
            'breakdown' => $this->priced->toApiArray(),
            'cart' => [
                'id' => $this->cart->uuid,
                'restaurant_id' => $this->cart->restaurant?->uuid,
                'item_count' => $this->cart->itemCount(),
                'line_count' => $this->cart->items->count(),

                // A subtotal and never a total: there are no taxes, fees or
                // charges in this module, and calling it a total would promise
                // a figure nobody has calculated.
                'subtotal' => [
                    'amount_minor' => $this->cart->subtotalMinor(),
                    'currency' => $this->cart->currency,
                ],
            ],
        ];
    }
}
