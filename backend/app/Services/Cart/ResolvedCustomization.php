<?php

declare(strict_types=1);

namespace App\Services\Cart;

use App\Models\MenuItem;
use App\Models\MenuItemVariant;
use App\Models\MenuModifierGroup;
use App\Models\MenuModifierOption;

/**
 * A customer's selection, turned into the rows it actually refers to.
 *
 * The output of {@see CustomizationValidator}: every uuid in the request has
 * been looked up, proved to belong where the customer said it did, and proved
 * to be something they may still choose. Downstream code takes models, not
 * strings, so there is no second place where an id might be trusted.
 */
final readonly class ResolvedCustomization
{
    /**
     * @param  list<array{group: MenuModifierGroup, option: MenuModifierOption}>  $modifiers
     */
    public function __construct(
        public MenuItem $item,
        public ?MenuItemVariant $variant,
        public array $modifiers,
        public int $quantity,
        public ?string $specialInstructions,
        public string $fingerprint,
    ) {}
}
