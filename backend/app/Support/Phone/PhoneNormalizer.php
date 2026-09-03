<?php

declare(strict_types=1);

namespace App\Support\Phone;

/**
 * Turns whatever a human typed into E.164, or rejects it.
 *
 * Deliberately a small table of supported countries rather than libphonenumber:
 * the launch market is India, the rules that matter are "which countries do we
 * serve" and "is this a plausible mobile number there", and a 200-country
 * metadata dependency answers neither. The table is the place to add a market.
 *
 * Nothing here is the last word — the backend re-validates, and the database
 * uniqueness constraint is what actually guarantees one account per number.
 */
final class PhoneNormalizer
{
    /**
     * Supported calling codes and their national-number rules.
     *
     * @var array<string, array{min: int, max: int, mobilePrefixes: array<int, string>, iso: string, name: string}>
     */
    private const COUNTRIES = [
        // India: 10 digits, mobile numbers begin 6-9.
        '91' => ['min' => 10, 'max' => 10, 'mobilePrefixes' => ['6', '7', '8', '9'], 'iso' => 'IN', 'name' => 'India'],
        // Kept deliberately short. Adding a market is a line here plus a test.
        '971' => ['min' => 9, 'max' => 9, 'mobilePrefixes' => ['5'], 'iso' => 'AE', 'name' => 'United Arab Emirates'],
        '44' => ['min' => 10, 'max' => 10, 'mobilePrefixes' => ['7'], 'iso' => 'GB', 'name' => 'United Kingdom'],
        '1' => ['min' => 10, 'max' => 10, 'mobilePrefixes' => [], 'iso' => 'US', 'name' => 'United States'],
    ];

    public const DEFAULT_COUNTRY_CODE = '91';

    /**
     * Normalizes an arbitrary input to a [PhoneNumber], or null if it is not a
     * number we can serve.
     *
     * @param  string|null  $defaultCountryCode  Applied when the input carries no `+`.
     */
    public static function normalize(?string $input, ?string $defaultCountryCode = null): ?PhoneNumber
    {
        if ($input === null) {
            return null;
        }

        $trimmed = trim($input);
        if ($trimmed === '') {
            return null;
        }

        // Reject anything that is not digits, spaces, dashes, brackets or a
        // leading plus. Letters in a phone number are either a typo or an attempt
        // to smuggle something into a log line.
        if (preg_match('/^\+?[0-9\s\-().]+$/', $trimmed) !== 1) {
            return null;
        }

        $hasPlus = str_starts_with($trimmed, '+');
        $digits = preg_replace('/\D/', '', $trimmed) ?? '';

        if ($digits === '') {
            return null;
        }

        if ($hasPlus) {
            return self::splitInternational($digits);
        }

        $country = $defaultCountryCode ?? self::DEFAULT_COUNTRY_CODE;

        // A leading 0 is the national trunk prefix in most of the table; it is not
        // part of the number itself. "09876543210" and "9876543210" are the same
        // subscriber, and treating them as different accounts is a real bug.
        $national = ltrim($digits, '0');
        if ($national === '') {
            return null;
        }

        // Somebody typed "919876543210" without the plus.
        if (! isset(self::COUNTRIES[$country])) {
            return null;
        }
        $rules = self::COUNTRIES[$country];
        if (strlen($national) > $rules['max'] && str_starts_with($national, $country)) {
            return self::splitInternational($national);
        }

        return self::build($country, $national);
    }

    private static function splitInternational(string $digits): ?PhoneNumber
    {
        // array_map to string is not decoration: PHP silently converts a numeric
        // string array key to an int, so array_keys(self::COUNTRIES) returns
        // [91, 971, 44, 1] as integers and every string function below would
        // reject them.
        $codes = array_map(static fn (int|string $code): string => (string) $code, array_keys(self::COUNTRIES));

        // Longest calling code first, so '1' never shadows '91' or '971'.
        usort($codes, static fn (string $a, string $b): int => strlen($b) <=> strlen($a));

        foreach ($codes as $code) {
            if (str_starts_with($digits, $code)) {
                return self::build($code, substr($digits, strlen($code)));
            }
        }

        return null;
    }

    private static function build(string $countryCode, string $nationalNumber): ?PhoneNumber
    {
        if (! isset(self::COUNTRIES[$countryCode])) {
            return null;
        }

        $rules = self::COUNTRIES[$countryCode];
        $length = strlen($nationalNumber);

        if ($length < $rules['min'] || $length > $rules['max']) {
            return null;
        }

        if ($rules['mobilePrefixes'] !== [] && ! in_array($nationalNumber[0], $rules['mobilePrefixes'], true)) {
            return null;
        }

        return new PhoneNumber(
            e164: '+'.$countryCode.$nationalNumber,
            countryCode: $countryCode,
            nationalNumber: $nationalNumber,
        );
    }

    /** @return array<int, array{code: string, iso: string, name: string}> */
    public static function supportedCountries(): array
    {
        $countries = [];
        foreach (self::COUNTRIES as $code => $rules) {
            // Cast for the same reason as in splitInternational(): these keys come
            // back as ints. Left uncast, the country picker would receive
            // {"code": 91} and a client comparing against "91" would never match.
            $countries[] = ['code' => (string) $code, 'iso' => $rules['iso'], 'name' => $rules['name']];
        }

        return $countries;
    }

    public static function isSupportedCountry(string $countryCode): bool
    {
        return isset(self::COUNTRIES[$countryCode]);
    }
}
