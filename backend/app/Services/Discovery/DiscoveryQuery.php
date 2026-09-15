<?php

declare(strict_types=1);

namespace App\Services\Discovery;

use App\Enums\ApiErrorCode;
use App\Enums\DiscoverySort;
use App\Exceptions\ApiException;
use Illuminate\Http\Request;

/**
 * What the customer asked for, validated once and then trusted.
 *
 * A value object rather than a bag of request parameters threaded through four
 * services. Everything is normalised on construction — trimmed, lowercased,
 * deduplicated, sorted — so that two requests meaning the same thing *are* the
 * same thing: `facilities=parking,restroom` and `facilities=restroom,parking`
 * produce identical objects and therefore identical cache keys.
 *
 * Nothing here can reach the database as text. Slugs are matched against values
 * the database itself generated; every number is cast and bounded; the sort is
 * an enum. There is no path by which a query string becomes SQL.
 */
final readonly class DiscoveryQuery
{
    /** Long enough for a restaurant's full name, short enough to bound the work. */
    public const MAX_SEARCH_LENGTH = 100;

    /**
     * Below this, a search is not run at all.
     *
     * One character matches most of the corridor and tells the customer
     * nothing, while costing a full request per keystroke. Two is the point at
     * which a search starts to mean something.
     */
    public const MIN_SEARCH_LENGTH = 2;

    /**
     * How many values one filter group may carry.
     *
     * There are eight cuisines and four facilities in the whole database. A
     * request naming a hundred is not a customer.
     */
    public const MAX_FILTER_VALUES = 25;

    public const MAX_PER_PAGE = 50;

    /**
     * @param  list<string>  $cuisines  slugs; OR within the group
     * @param  list<string>  $facilities  slugs; AND within the group
     * @param  list<int>  $priceLevels  1-4; OR within the group
     */
    private function __construct(
        public ?string $search,
        public array $cuisines,
        public array $facilities,
        public array $priceLevels,
        public ?AvailabilityFilter $availability,
        public ?int $maxDetourSeconds,
        public ?int $maxDistanceAheadMetres,
        public ?float $minRating,
        public DiscoverySort $sort,
        public int $page,
        public int $perPage,
    ) {}

    /** An unfiltered query — what Module 07 asked for, in Module 08's shape. */
    public static function unfiltered(): self
    {
        return new self(
            search: null,
            cuisines: [],
            facilities: [],
            priceLevels: [],
            availability: null,
            maxDetourSeconds: null,
            maxDistanceAheadMetres: null,
            minRating: null,
            sort: DiscoverySort::Recommended,
            page: 1,
            perPage: (int) config('foodonthego.discovery.result_limit'),
        );
    }

    /**
     * Reads and validates a request.
     *
     * Every failure is a 422 naming the parameter. Nothing is silently ignored
     * or silently clamped: a client sending `max_detour_seconds=-500` has a bug,
     * and answering it with a full unfiltered list hides that bug from whoever
     * has to find it. Module 05 learned this the expensive way, when a filter
     * the server did not recognise was quietly dropped and every list came back
     * unfiltered while looking perfectly healthy.
     *
     * @throws ApiException
     */
    public static function fromRequest(Request $request): self
    {
        $search = self::readSearch($request);

        $maxDetour = self::readBoundedInt(
            $request,
            'max_detour_seconds',
            1,
            (int) config('foodonthego.discovery.max_detour_duration_seconds'),
        );

        $maxAhead = self::readBoundedInt($request, 'max_distance_ahead_meters', 1, 5_000_000);

        return new self(
            search: $search,
            cuisines: self::readSlugs($request, 'cuisines'),
            facilities: self::readSlugs($request, 'facilities'),
            priceLevels: self::readPriceLevels($request),
            availability: self::readAvailability($request),
            maxDetourSeconds: $maxDetour,
            maxDistanceAheadMetres: $maxAhead,
            minRating: self::readRating($request),
            sort: self::readSort($request),
            page: max(1, (int) $request->integer('page', 1)),
            perPage: self::readPerPage($request),
        );
    }

    public function hasSearch(): bool
    {
        return $this->search !== null;
    }

    public function hasFilters(): bool
    {
        return $this->cuisines !== []
            || $this->facilities !== []
            || $this->priceLevels !== []
            || $this->availability !== null
            || $this->maxDetourSeconds !== null
            || $this->maxDistanceAheadMetres !== null
            || $this->minRating !== null;
    }

    public function isRefined(): bool
    {
        return $this->hasSearch() || $this->hasFilters();
    }

    /**
     * A stable identity for this query, for a cache key.
     *
     * Built from the normalised values rather than from the query string, which
     * is what makes reordered and differently-spaced requests share a cache
     * entry. Page and per-page are included: page 2 is not page 1.
     */
    public function fingerprint(): string
    {
        return md5(serialize([
            $this->search,
            $this->cuisines,
            $this->facilities,
            $this->priceLevels,
            $this->availability?->value,
            $this->maxDetourSeconds,
            $this->maxDistanceAheadMetres,
            $this->minRating,
            $this->sort->value,
            $this->page,
            $this->perPage,
        ]));
    }

    /** @return array<string, mixed> the query as the server understood it */
    public function toApiArray(): array
    {
        return [
            'search' => $this->search,
            'cuisines' => $this->cuisines,
            'facilities' => $this->facilities,
            'price_levels' => $this->priceLevels,
            'availability' => $this->availability?->value,
            'max_detour_seconds' => $this->maxDetourSeconds,
            'max_distance_ahead_meters' => $this->maxDistanceAheadMetres,
            'min_rating' => $this->minRating,
            'sort' => $this->sort->value,
        ];
    }

    // --- reading -------------------------------------------------------------

    private static function readSearch(Request $request): ?string
    {
        $raw = $request->query('search');

        if (! is_string($raw)) {
            return null;
        }

        // Collapse every run of whitespace — including the tab a paste brings
        // and the non-breaking space a phone keyboard produces — to one space.
        $clean = trim((string) preg_replace('/\s+/u', ' ', $raw));

        if ($clean === '') {
            return null;
        }

        if (mb_strlen($clean) > self::MAX_SEARCH_LENGTH) {
            throw self::invalid('search', 'A search may be at most '
                .self::MAX_SEARCH_LENGTH.' characters.');
        }

        // Shorter than the minimum is not an error — it is a customer who has
        // typed one letter so far — so it is treated as no search at all rather
        // than as a request to reject.
        return mb_strlen($clean) < self::MIN_SEARCH_LENGTH ? null : $clean;
    }

    /** @return list<string> */
    private static function readSlugs(Request $request, string $key): array
    {
        $raw = $request->query($key);

        if (! is_string($raw) || trim($raw) === '') {
            return [];
        }

        $values = array_filter(array_map('trim', explode(',', $raw)), fn (string $v): bool => $v !== '');

        foreach ($values as $value) {
            // Exactly the shape the database's own generated slugs take. A value
            // that cannot be one is not a value that exists, and saying so is
            // more useful than returning an empty list.
            if (preg_match('/^[a-z0-9_]{1,60}$/', $value) !== 1) {
                throw self::invalid($key, "\"{$value}\" is not a valid identifier.");
            }
        }

        return self::bounded(array_values(array_unique($values)), $key);
    }

    /** @return list<int> */
    private static function readPriceLevels(Request $request): array
    {
        $raw = $request->query('price_levels');

        if (! is_string($raw) || trim($raw) === '') {
            return [];
        }

        $levels = [];

        foreach (explode(',', $raw) as $value) {
            $value = trim($value);

            if ($value === '') {
                continue;
            }

            if (preg_match('/^[1-4]$/', $value) !== 1) {
                throw self::invalid('price_levels', 'Price levels are 1 to 4.');
            }

            $levels[] = (int) $value;
        }

        $levels = array_values(array_unique($levels));
        sort($levels);

        return self::bounded($levels, 'price_levels');
    }

    private static function readAvailability(Request $request): ?AvailabilityFilter
    {
        $raw = $request->query('availability');

        if (! is_string($raw) || trim($raw) === '') {
            return null;
        }

        return AvailabilityFilter::tryFrom(trim($raw))
            ?? throw self::invalid('availability', 'Unknown availability filter.');
    }

    private static function readRating(Request $request): ?float
    {
        $raw = $request->query('min_rating');

        if (! is_string($raw) || trim($raw) === '') {
            return null;
        }

        if (! is_numeric($raw)) {
            throw self::invalid('min_rating', 'A minimum rating must be a number.');
        }

        $rating = (float) $raw;

        if ($rating < 0.0 || $rating > 5.0) {
            throw self::invalid('min_rating', 'A minimum rating is between 0 and 5.');
        }

        // Accepted and validated even though no restaurant has a rating yet, so
        // the contract is settled before the reviews module arrives. The filter
        // is advertised as unavailable in the response metadata; a client that
        // sends it anyway gets an honest empty result rather than a 404 on a
        // parameter that will exist next quarter.
        return $rating;
    }

    private static function readSort(Request $request): DiscoverySort
    {
        $raw = $request->query('sort');

        if (! is_string($raw) || trim($raw) === '') {
            return DiscoverySort::Recommended;
        }

        $sort = DiscoverySort::tryFrom(trim($raw));

        if ($sort === null) {
            throw self::invalid('sort', 'Unknown sort order.');
        }

        // An allow-list by construction: `sort=destroy_database` never becomes a
        // column name, because the only thing a sort value can become is an enum
        // case with a hand-written comparator behind it.
        if (! $sort->isAvailable()) {
            throw self::invalid('sort', "Sorting by \"{$sort->value}\" is not available yet.");
        }

        return $sort;
    }

    private static function readPerPage(Request $request): int
    {
        $raw = $request->query('per_page');

        if (! is_string($raw) || trim($raw) === '') {
            return (int) config('foodonthego.discovery.result_limit');
        }

        if (preg_match('/^\d+$/', trim($raw)) !== 1) {
            throw self::invalid('per_page', 'A page size must be a whole number.');
        }

        $perPage = (int) $raw;

        if ($perPage < 1 || $perPage > self::MAX_PER_PAGE) {
            throw self::invalid('per_page', 'A page size is between 1 and '.self::MAX_PER_PAGE.'.');
        }

        return $perPage;
    }

    private static function readBoundedInt(Request $request, string $key, int $min, int $max): ?int
    {
        $raw = $request->query($key);

        if (! is_string($raw) || trim($raw) === '') {
            return null;
        }

        if (preg_match('/^-?\d+$/', trim($raw)) !== 1) {
            throw self::invalid($key, 'This must be a whole number.');
        }

        $value = (int) $raw;

        if ($value < $min || $value > $max) {
            throw self::invalid($key, "This must be between {$min} and {$max}.");
        }

        return $value;
    }

    /**
     * @param  list<mixed>  $values
     * @return list<mixed>
     */
    private static function bounded(array $values, string $key): array
    {
        if (count($values) > self::MAX_FILTER_VALUES) {
            throw self::invalid($key, 'At most '.self::MAX_FILTER_VALUES.' values.');
        }

        sort($values);

        return $values;
    }

    private static function invalid(string $field, string $message): ApiException
    {
        return new ApiException(
            ApiErrorCode::ValidationFailed,
            'The filters could not be understood.',
            ['fields' => [$field => [$message]]],
        );
    }
}
