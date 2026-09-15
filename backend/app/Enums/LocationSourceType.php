<?php

declare(strict_types=1);

namespace App\Enums;

/**
 * Where a chosen place came from.
 *
 * Recorded because the three sources carry different trust. A saved address was
 * entered by the customer and may never have been geocoded; a place-search
 * result came from an external provider with its own identifier; a current
 * location came from the device's own sensors and is the only one where the
 * coordinates are the primary fact rather than a lookup of one.
 *
 * Module 06 will care: a corridor drawn from a device fix and one drawn from a
 * geocoded postal address have different error bars.
 */
enum LocationSourceType: string
{
    case CurrentLocation = 'CURRENT_LOCATION';
    case SavedAddress = 'SAVED_ADDRESS';
    case PlaceSearch = 'PLACE_SEARCH';

    /** @return list<string> */
    public static function values(): array
    {
        return array_map(static fn (self $case): string => $case->value, self::cases());
    }
}
