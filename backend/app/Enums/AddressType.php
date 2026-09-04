<?php

declare(strict_types=1);

namespace App\Enums;

/**
 * What kind of place a saved address is.
 *
 * Three categories rather than free text, because the trip planner will need to
 * offer "Home" and "Work" as one-tap origins and destinations, and it cannot do
 * that against a string somebody typed. The *display* name is separate — see
 * `CustomerAddress::label` — so a customer can call their Other address
 * "Parents' House" without the category losing meaning.
 */
enum AddressType: string
{
    case Home = 'HOME';
    case Work = 'WORK';
    case Other = 'OTHER';

    /** @return array<int, string> */
    public static function values(): array
    {
        return array_column(self::cases(), 'value');
    }

    /**
     * The default label when the customer does not supply one.
     *
     * Only ever a fallback: a HOME address is called "Home" unless its owner says
     * otherwise. Presentation strings do not live in database logic — this is the
     * seed value written once at creation, not something the UI reads back.
     */
    public function defaultLabel(): string
    {
        return match ($this) {
            self::Home => 'Home',
            self::Work => 'Work',
            self::Other => 'Other',
        };
    }

    /** Whether this type requires the customer to name the place themselves. */
    public function requiresCustomLabel(): bool
    {
        return $this === self::Other;
    }
}
