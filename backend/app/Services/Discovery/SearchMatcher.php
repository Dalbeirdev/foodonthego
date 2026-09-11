<?php

declare(strict_types=1);

namespace App\Services\Discovery;

/**
 * Whether a restaurant matches what somebody typed, and how well.
 *
 * Matching happens over three customer-facing fields and no others: the
 * restaurant's name, its declared cuisines, and its city. Owner names, internal
 * notes, tax identifiers and every other private column are not searchable —
 * not filtered out afterwards, but never looked at, which is the only version of
 * that guarantee worth having.
 *
 * ## Why substring rather than full-text
 *
 * At pilot scale the corridor has already narrowed the set to a few dozen
 * restaurants before this runs, so matching is over tens of rows in memory.
 * MySQL full-text would bring stemming, a stopword list and a minimum word
 * length — "Cafe" is four characters and would survive, but a search for a
 * two-letter dish would not — and none of that is worth a behaviour nobody can
 * predict. The reversal condition is written down in
 * `docs/23-restaurant-search-filters-ranking.md`.
 *
 * ## Why it scores rather than merely matching
 *
 * A search for "Highway Spice" that ranks a restaurant in Highway Town above
 * *Highway Spice Kitchen* is a worse answer than no search. The score is what
 * feeds the ranking, and it is ordered so that an exact name beats a name
 * prefix, which beats a name substring, which beats a cuisine, which beats a
 * city.
 */
final class SearchMatcher
{
    /** An exact name. Nothing outranks this. */
    private const EXACT_NAME = 1.0;

    /** The name starts with what was typed: "Highway Spice" → "Highway Spice Kitchen". */
    private const NAME_PREFIX = 0.9;

    /** Every typed word appears in the name, in any order. */
    private const NAME_ALL_TERMS = 0.75;

    /** The name contains the phrase somewhere. */
    private const NAME_SUBSTRING = 0.6;

    /** A declared cuisine matches: "South Indian". */
    private const CUISINE_EXACT = 0.55;

    private const CUISINE_PARTIAL = 0.4;

    /** The town it is in. The weakest signal, and deliberately below cuisine. */
    private const CITY = 0.2;

    /**
     * 0.0 for no match at all; higher is a better match.
     *
     * @param  list<string>  $cuisines
     */
    public function score(string $search, string $name, array $cuisines, ?string $city): float
    {
        $needle = $this->normalise($search);

        if ($needle === '') {
            return 0.0;
        }

        $haystack = $this->normalise($name);

        if ($haystack === $needle) {
            return self::EXACT_NAME;
        }

        if (str_starts_with($haystack, $needle)) {
            return self::NAME_PREFIX;
        }

        if (str_contains($haystack, $needle)) {
            return self::NAME_SUBSTRING;
        }

        // Every word, in any order: "spice highway" still finds Highway Spice
        // Kitchen. Checked after the phrase tests so that a phrase match always
        // scores higher than a scattered one.
        $terms = array_filter(explode(' ', $needle));

        if ($terms !== [] && $this->containsAll($haystack, $terms)) {
            return self::NAME_ALL_TERMS;
        }

        $best = 0.0;

        foreach ($cuisines as $cuisine) {
            $normalised = $this->normalise($cuisine);

            if ($normalised === $needle) {
                $best = max($best, self::CUISINE_EXACT);
            } elseif (str_contains($normalised, $needle) || $this->containsAll($normalised, $terms)) {
                $best = max($best, self::CUISINE_PARTIAL);
            }
        }

        if ($best > 0.0) {
            return $best;
        }

        if ($city !== null && str_contains($this->normalise($city), $needle)) {
            return self::CITY;
        }

        return 0.0;
    }

    /**
     * Casefolded, accent-insensitive, whitespace-collapsed.
     *
     * `mb_strtolower` rather than `strtolower`, because the latter is
     * byte-oriented and mangles anything outside ASCII — and a product shipping
     * in India will meet restaurant names that are not ASCII. Punctuation
     * becomes a space so that "Rajesh's" and "Rajeshs" both find each other.
     */
    private function normalise(string $value): string
    {
        $value = mb_strtolower(trim($value), 'UTF-8');

        // Decompose, then drop the combining marks, so "café" and "cafe" are the
        // same word.
        //
        // **Not** `iconv('UTF-8', 'ASCII//TRANSLIT')`, which is the obvious way
        // to do this and is wrong for this product: it maps anything with no
        // ASCII equivalent to a question mark, so "शर्मा ढाबा" becomes "?????
        // ?????" and every restaurant named in Devanagari collapses to the same
        // unsearchable string. Caught by a test, in a codebase shipping in
        // India, which is where it would have mattered.
        //
        // Applied identically to the search term and to the restaurant, so
        // whatever it does to a script it does to both and matching survives.
        if (class_exists(\Normalizer::class)) {
            $decomposed = \Normalizer::normalize($value, \Normalizer::FORM_D);

            if (is_string($decomposed)) {
                $value = (string) preg_replace('/\p{Mn}+/u', '', $decomposed);
            }
        }

        // An apostrophe is removed rather than replaced, because it elides
        // rather than separates: "Rajesh's" is one word. Replacing it with a
        // space made the matching asymmetric — somebody typing "rajeshs" could
        // not find "Rajesh's Dhaba", which is the more common direction, since
        // people leave apostrophes out far more often than they put them in.
        $value = str_replace(["'", "\u{2019}", '`'], '', $value);

        // Everything else becomes a space, which is also what makes a SQL or
        // glob wildcard inert here: "%" is not a pattern, it is a character that
        // gets removed, and "%spice%" searches for "spice".
        $value = (string) preg_replace('/[^\p{L}\p{N}]+/u', ' ', $value);

        return trim((string) preg_replace('/\s+/u', ' ', $value));
    }

    /** @param list<string> $terms */
    private function containsAll(string $haystack, array $terms): bool
    {
        if ($terms === []) {
            return false;
        }

        foreach ($terms as $term) {
            if (! str_contains($haystack, $term)) {
                return false;
            }
        }

        return true;
    }
}
