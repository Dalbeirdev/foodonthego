<?php

declare(strict_types=1);

namespace App\Support\Address;

/**
 * Composes the single-line form of an address from its parts.
 *
 * It exists so the one-line version is derived rather than typed twice: a client
 * that composed its own would drift from the server's the first time somebody
 * edited a field, and the trip planner will read this string.
 *
 * When Google Places is connected, its `formatted_address` replaces this — the
 * composed form is the fallback, not the target.
 */
final class AddressFormatter
{
    /**
     * @param  array<string, mixed>  $parts
     */
    public static function compose(array $parts): string
    {
        // Landmark is deliberately absent. It helps somebody *find* the door and
        // is shown next to the address, but "Near the metro station" inside a
        // one-line address is noise in a list and useless to a geocoder.
        $ordered = [
            $parts['address_line_1'] ?? null,
            $parts['address_line_2'] ?? null,
            $parts['city'] ?? null,
            self::regionWithPostcode($parts),
            $parts['country_code'] ?? null,
        ];

        $clean = [];
        foreach ($ordered as $piece) {
            $piece = trim((string) ($piece ?? ''));
            if ($piece !== '') {
                $clean[] = $piece;
            }
        }

        return implode(', ', $clean);
    }

    /**
     * "Delhi 110016" rather than "Delhi, 110016".
     *
     * The postcode belongs to the region on every address label in every country
     * that uses both, and splitting them with a comma reads as two fields.
     *
     * @param  array<string, mixed>  $parts
     */
    private static function regionWithPostcode(array $parts): string
    {
        $state = trim((string) ($parts['state'] ?? ''));
        $postal = trim((string) ($parts['postal_code'] ?? ''));

        return trim($state.' '.$postal);
    }
}
