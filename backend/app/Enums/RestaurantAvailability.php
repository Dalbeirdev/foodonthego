<?php

declare(strict_types=1);

namespace App\Enums;

/**
 * What a customer is told about whether they can actually stop here.
 *
 * This is a *presentation* of two independent facts — the opening hours say the
 * doors are open, and the restaurant says it is taking orders — and the order of
 * the cases below is the order they are resolved in. A restaurant that is open
 * but paused is {@see NotAcceptingOrders}, never {@see Open}: showing "Open" to
 * somebody who is about to drive forty kilometres for food nobody will cook is
 * the single worst thing this module could do.
 *
 * {@see OpeningSoon} and {@see ClosingSoon} exist because a traveller an hour
 * away cares about a restaurant that opens in thirty minutes. They are computed
 * against the *restaurant's* clock, never the device's.
 */
enum RestaurantAvailability: string
{
    case Open = 'OPEN';
    case ClosingSoon = 'CLOSING_SOON';
    case OpeningSoon = 'OPENING_SOON';
    case Closed = 'CLOSED';

    /** Open by the clock, but not taking orders right now. */
    case NotAcceptingOrders = 'NOT_ACCEPTING_ORDERS';

    /** No usable opening-hours data. Not a claim that it is shut. */
    case Unknown = 'UNKNOWN';

    /** @return list<string> */
    public static function values(): array
    {
        return array_map(static fn (self $case): string => $case->value, self::cases());
    }

    /** Whether a customer could order here now, if the rest of the app existed. */
    public function isActionable(): bool
    {
        return $this === self::Open || $this === self::ClosingSoon;
    }
}
