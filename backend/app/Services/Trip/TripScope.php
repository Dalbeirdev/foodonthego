<?php

declare(strict_types=1);

namespace App\Services\Trip;

/**
 * Which slice of a customer's journeys a list request wants.
 *
 * An enum rather than a free string, so an unrecognised `?scope=` is a
 * validation failure the caller can read, not a silent fall-through to
 * everything — which is the version of this bug that quietly returns cancelled
 * journeys in an "upcoming" list.
 */
enum TripScope: string
{
    case Upcoming = 'upcoming';
    case Past = 'past';
    case Cancelled = 'cancelled';
    case All = 'all';

    /** @return list<string> */
    public static function values(): array
    {
        return array_map(static fn (self $case): string => $case->value, self::cases());
    }
}
