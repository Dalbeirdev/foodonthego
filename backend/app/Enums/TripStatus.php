<?php

declare(strict_types=1);

namespace App\Enums;

/**
 * The states a journey can be in *as far as Module 05 can honestly observe*.
 *
 * There are deliberately only two. A journey that is being travelled, has
 * arrived, or has finished are all claims about the physical world, and this
 * module has no way to know any of them: there is no GPS, no route, and no
 * arrival signal. Adding `ON_THE_ROAD` here would mean either asking the
 * customer to tell us something we then could not verify, or inventing it — and
 * the restaurant queue is eventually sorted by expected arrival, so an invented
 * travel state is an invented cooking time.
 *
 * Module 09 owns the corridor and the movement along it, and will add the
 * states it can actually establish.
 *
 * "Past" is therefore not a status. It is `departure_at` being behind us, which
 * is a fact about the clock rather than a claim about the traveller.
 */
enum TripStatus: string
{
    case Planned = 'PLANNED';
    case Cancelled = 'CANCELLED';

    /** @return list<string> */
    public static function values(): array
    {
        return array_map(static fn (self $case): string => $case->value, self::cases());
    }

    public function label(): string
    {
        return match ($this) {
            self::Planned => 'Planned',
            self::Cancelled => 'Cancelled',
        };
    }

    /** Whether a journey in this state can still be changed by its owner. */
    public function isOpen(): bool
    {
        return $this === self::Planned;
    }
}
