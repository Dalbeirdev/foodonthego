<?php

declare(strict_types=1);

namespace App\Enums;

/**
 * Whether the kitchen can make this today.
 *
 * Separate from `is_active`, and the distinction matters to a customer.
 * `is_active = false` means the dish is off the menu — invisible, as though it
 * did not exist. Sold out means it exists, they know what it is, and they
 * cannot have it right now: worth showing, because a traveller deciding where
 * to stop wants to know the restaurant makes it at all.
 */
enum MenuItemStockStatus: string
{
    case InStock = 'IN_STOCK';

    /** Out today. Reversible, and usually by this evening. */
    case SoldOut = 'SOLD_OUT';

    public function isOrderable(): bool
    {
        return $this === self::InStock;
    }

    /** @return list<string> */
    public static function values(): array
    {
        return array_map(static fn (self $case): string => $case->value, self::cases());
    }
}
