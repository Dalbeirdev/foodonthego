<?php

declare(strict_types=1);

namespace App\Support\Address;

/**
 * Per-country postal-code rules.
 *
 * The important design point is what happens for a country not in the table:
 * the code is accepted if it is a plausible length. Rejecting it would mean an
 * address in an unlisted country cannot be saved at all, which is a worse
 * failure than storing a postcode we could not check — and the launch market is
 * covered exactly.
 *
 * "Six digits" is an Indian rule, not a universal one. The UK's are alphanumeric
 * and contain a space; Ireland's Eircodes are seven alphanumerics; several
 * countries have none. Hard-coding India's shape globally is the mistake this
 * class exists to avoid.
 */
final class PostalCode
{
    /**
     * @var array<string, array{pattern: string, example: string, required: bool}>
     */
    private const RULES = [
        // PIN code: six digits, and the first may not be 0.
        'IN' => ['pattern' => '/^[1-9]\d{5}$/', 'example' => '110016', 'required' => true],
        // The UAE has no postal code system in general use.
        'AE' => ['pattern' => '/^.{0,10}$/', 'example' => '', 'required' => false],
        // Outward + inward, with an optional space.
        'GB' => ['pattern' => '/^[A-Z]{1,2}\d[A-Z\d]?\s?\d[A-Z]{2}$/i', 'example' => 'SW1A 1AA', 'required' => true],
        // ZIP, with the optional +4.
        'US' => ['pattern' => '/^\d{5}(-\d{4})?$/', 'example' => '10001', 'required' => true],
    ];

    public static function isRequiredFor(string $countryCode): bool
    {
        return self::RULES[strtoupper($countryCode)]['required'] ?? false;
    }

    /** Whether [$value] is a plausible postal code in [$countryCode]. */
    public static function isValid(string $countryCode, ?string $value): bool
    {
        $value = trim((string) $value);
        $country = strtoupper($countryCode);

        if ($value === '') {
            return ! self::isRequiredFor($country);
        }

        $rule = self::RULES[$country] ?? null;

        if ($rule === null) {
            // Unknown country: a length sanity check and nothing more. Long
            // enough for every real format, short enough that the column holds it.
            return mb_strlen($value) <= 16;
        }

        return preg_match($rule['pattern'], $value) === 1;
    }

    /** An example to put in an error message, or null when there is no rule. */
    public static function exampleFor(string $countryCode): ?string
    {
        $example = self::RULES[strtoupper($countryCode)]['example'] ?? '';

        return $example === '' ? null : $example;
    }

    public static function hasRuleFor(string $countryCode): bool
    {
        return isset(self::RULES[strtoupper($countryCode)]);
    }
}
