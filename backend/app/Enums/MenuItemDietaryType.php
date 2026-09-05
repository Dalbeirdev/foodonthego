<?php

declare(strict_types=1);

namespace App\Enums;

/**
 * What a dish is made of, as the operator declared it.
 *
 * Never inferred. "Paneer Tikka" is not a promise that a dish is vegetarian,
 * "Chicken" in a name is not a guarantee that nothing else is in it, and a
 * customer who avoids egg cannot act on our guess. An item with no declared
 * type shows no indicator at all — which is honest, and is what an operator
 * who has not filled the field in has told us.
 */
enum MenuItemDietaryType: string
{
    case Vegetarian = 'VEGETARIAN';
    case NonVegetarian = 'NON_VEGETARIAN';
    case Vegan = 'VEGAN';
    case Egg = 'EGG';

    public static function tryFromValue(?string $value): ?self
    {
        return $value === null ? null : self::tryFrom($value);
    }

    /** @return list<string> */
    public static function values(): array
    {
        return array_map(static fn (self $case): string => $case->value, self::cases());
    }
}
