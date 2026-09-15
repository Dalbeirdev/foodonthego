<?php

declare(strict_types=1);

namespace App\Services\Discovery;

use App\Enums\DiscoverySort;
use App\Models\Restaurant;

/**
 * Search, filter, sort and paginate — over a set that is already eligible.
 *
 * ## The order of operations is the security model
 *
 * This runs **after** {@see RestaurantDiscoveryService} has established which
 * restaurants a customer may see on this route, and it can only ever remove from
 * that set. There is no path here that reads the database, so there is no path
 * by which a search term reintroduces a suspended restaurant: searching for
 * "Suspended Dhaba" returns nothing, because the row was gone before this class
 * was called.
 *
 * That is not a check performed here. It is a property of where this sits, which
 * is a much stronger guarantee than a check somebody could forget.
 *
 * ## Why it is in memory
 *
 * The route corridor has already reduced the country to a few dozen restaurants,
 * and the route figures every filter needs — detour, distance ahead, availability
 * — are derived per request rather than stored. Pushing filters into SQL would
 * mean either persisting derived values per customer per route, or fetching the
 * set and filtering it anyway. At this scale the second is measured in
 * microseconds.
 *
 * The reversal condition is written down in
 * `docs/23-restaurant-search-filters-ranking.md`: when a corridor routinely
 * yields hundreds of eligible restaurants, the cuisine and facility filters move
 * into the candidate query and the rest stay here.
 */
final class DiscoveryRefiner
{
    public function __construct(
        private readonly SearchMatcher $matcher,
        private readonly DiscoveryRankingService $ranking,
    ) {}

    public function refine(DiscoveryResult $discovered, DiscoveryQuery $query): RefinedDiscovery
    {
        $all = $discovered->restaurants;

        // 1. Search. Rescores as it goes: a restaurant's relevance to what
        //    somebody typed is not knowable until they type it.
        $matched = $query->hasSearch()
            ? $this->applySearch($all, (string) $query->search)
            : $all;

        // 2. Filters. Each group narrows what the last one left.
        $filtered = $this->applyFilters($matched, $query);

        // 3. Sort.
        $sorted = $this->applySort($filtered, $query->sort);

        // 4. Paginate. Last, so a page is a page of the answer rather than a
        //    page of the candidates.
        $total = count($sorted);
        $offset = ($query->page - 1) * $query->perPage;
        $page = array_slice($sorted, $offset, $query->perPage);

        return new RefinedDiscovery(
            discovery: $discovered,
            query: $query,
            restaurants: array_values($page),
            total: $total,
            // Counted before filtering, so an empty screen can distinguish "this
            // route has nothing on it" from "your filters removed everything" —
            // two states that need different words and different buttons.
            eligibleTotal: count($all),
            facets: $this->facets($all),
        );
    }

    /**
     * @param  list<DiscoveredRestaurant>  $restaurants
     * @return list<DiscoveredRestaurant>
     */
    private function applySearch(array $restaurants, string $search): array
    {
        $matched = [];

        foreach ($restaurants as $found) {
            $relevance = $this->matcher->score(
                $search,
                $found->restaurant->name,
                $found->restaurant->cuisineNames(),
                $found->restaurant->city,
            );

            if ($relevance <= 0.0) {
                continue;
            }

            $matched[] = $found->rescored(
                $this->ranking->score(
                    $found->availability,
                    $found->detour,
                    $found->projection->proximityMetres,
                    $found->restaurant->rating_average,
                    $found->requiresBacktracking,
                    $relevance,
                ),
                $relevance,
            );
        }

        return $matched;
    }

    /**
     * @param  list<DiscoveredRestaurant>  $restaurants
     * @return list<DiscoveredRestaurant>
     */
    private function applyFilters(array $restaurants, DiscoveryQuery $query): array
    {
        return array_values(array_filter(
            $restaurants,
            fn (DiscoveredRestaurant $found): bool => $this->passes($found, $query),
        ));
    }

    /**
     * **OR within a group, AND across groups.**
     *
     * "North Indian or South Indian" is one question; "and it must have parking"
     * is another. Facilities are the deliberate exception: selecting Parking and
     * Restroom means a restaurant with **both**, because somebody who ticks two
     * facilities is stating two requirements rather than offering a choice.
     */
    private function passes(DiscoveredRestaurant $found, DiscoveryQuery $query): bool
    {
        $restaurant = $found->restaurant;

        // Cuisine — OR.
        if ($query->cuisines !== []) {
            $slugs = $restaurant->cuisines->pluck('slug')->all();

            if (array_intersect($query->cuisines, $slugs) === []) {
                return false;
            }
        }

        // Facilities — AND.
        if ($query->facilities !== []) {
            $slugs = $restaurant->facilities->pluck('slug')->all();

            if (array_diff($query->facilities, $slugs) !== []) {
                return false;
            }
        }

        // Price — OR. A restaurant that has never declared a price level is not
        // "cheap"; it is unknown, and an unknown does not satisfy a request for
        // a specific one.
        if ($query->priceLevels !== []) {
            if ($restaurant->price_level === null
                || ! in_array((int) $restaurant->price_level, $query->priceLevels, true)) {
                return false;
            }
        }

        if ($query->availability !== null
            && ! $query->availability->matches($found->availability)) {
            return false;
        }

        // Detour. A restaurant whose detour could not be established does **not**
        // satisfy a limit on it: we cannot assert that an unknown is under ten
        // minutes, and guessing in the customer's favour is how somebody ends up
        // twenty minutes off their route.
        if ($query->maxDetourSeconds !== null) {
            if ($found->detour === null
                || $found->detour->extraDurationSeconds > $query->maxDetourSeconds) {
                return false;
            }
        }

        if ($query->maxDistanceAheadMetres !== null
            && $found->projection->alongRouteMetres > $query->maxDistanceAheadMetres) {
            return false;
        }

        // Rating. Accepted, validated, and correct — an unrated restaurant does
        // not satisfy "4 stars and above", because it has not earned four stars;
        // it has earned nothing yet. Today that means the filter empties the
        // list, which is the honest answer while no restaurant has a rating.
        if ($query->minRating !== null) {
            if ($restaurant->rating_average === null
                || (float) $restaurant->rating_average < $query->minRating) {
                return false;
            }
        }

        return true;
    }

    /**
     * @param  list<DiscoveredRestaurant>  $restaurants
     * @return list<DiscoveredRestaurant>
     */
    private function applySort(array $restaurants, DiscoverySort $sort): array
    {
        // Every comparator ends in a uuid comparison. Without it, two
        // restaurants with the same detour swap places between requests — a
        // paginated list that reorders itself under the customer duplicates one
        // row and hides another.
        $tieBreak = static fn (DiscoveredRestaurant $a, DiscoveredRestaurant $b): int => strcmp(
            $a->restaurant->uuid,
            $b->restaurant->uuid,
        );

        // Every comparator carries `requiresBacktracking` immediately after its
        // primary key, so a stop that means turning round is never offered ahead
        // of an equivalent stop the customer is already driving towards.
        //
        // It is not enough to rely on the primary key for this. A price sort
        // where every restaurant declares the same level is decided entirely by
        // the tie-breakers, and the first version of this put "Behind you" at
        // the top of the list — the same defect M07-B01 fixed in journey order,
        // reintroduced through a different door.
        $comparator = match ($sort) {
            DiscoverySort::Recommended => static fn (
                DiscoveredRestaurant $a,
                DiscoveredRestaurant $b,
            ): int => [$b->relevanceScore, $a->requiresBacktracking, $a->projection->alongRouteMetres]
                <=> [$a->relevanceScore, $b->requiresBacktracking, $b->projection->alongRouteMetres]
                    ?: $tieBreak($a, $b),

            // An unknown detour sorts last rather than first. PHP would
            // otherwise treat null as zero and put every unmeasured restaurant
            // at the top of a list ordered by cheapest stop.
            DiscoverySort::LowestDetour => static fn (
                DiscoveredRestaurant $a,
                DiscoveredRestaurant $b,
            ): int => [$a->detour?->extraDurationSeconds ?? PHP_INT_MAX, $a->requiresBacktracking, $a->projection->alongRouteMetres]
                <=> [$b->detour?->extraDurationSeconds ?? PHP_INT_MAX, $b->requiresBacktracking, $b->projection->alongRouteMetres]
                    ?: $tieBreak($a, $b),

            // Here backtracking *is* the primary key: "turn round" is never the
            // soonest chance to stop.
            DiscoverySort::SoonestAlongRoute => static fn (
                DiscoveredRestaurant $a,
                DiscoveredRestaurant $b,
            ): int => [$a->requiresBacktracking, $a->projection->alongRouteMetres]
                <=> [$b->requiresBacktracking, $b->projection->alongRouteMetres]
                    ?: $tieBreak($a, $b),

            // An undeclared price sorts last: it is not cheap, it is unknown.
            DiscoverySort::PriceLowToHigh => static fn (
                DiscoveredRestaurant $a,
                DiscoveredRestaurant $b,
            ): int => [$a->restaurant->price_level ?? PHP_INT_MAX, $a->requiresBacktracking, $a->projection->alongRouteMetres]
                <=> [$b->restaurant->price_level ?? PHP_INT_MAX, $b->requiresBacktracking, $b->projection->alongRouteMetres]
                    ?: $tieBreak($a, $b),

            // Refused by DiscoverySort::isAvailable() long before here.
            DiscoverySort::HighestRated => static fn (
                DiscoveredRestaurant $a,
                DiscoveredRestaurant $b,
            ): int => [(float) ($b->restaurant->rating_average ?? 0), $a->requiresBacktracking]
                <=> [(float) ($a->restaurant->rating_average ?? 0), $b->requiresBacktracking]
                    ?: $tieBreak($a, $b),
        };

        usort($restaurants, $comparator);

        return $restaurants;
    }

    /**
     * The filter options that mean something for *this* route.
     *
     * Offering "EV Charging" on a road where nothing has it is a control that can
     * only ever empty the screen. The counts are computed from the eligible set
     * before filters are applied, so a customer who has already chosen North
     * Indian still sees how many restaurants have parking rather than watching
     * every other option collapse to zero.
     *
     * @param  list<DiscoveredRestaurant>  $restaurants
     * @return array<string, mixed>
     */
    private function facets(array $restaurants): array
    {
        $cuisines = [];
        $facilities = [];
        $prices = [];
        $availability = ['open_now' => 0, 'accepting_orders' => 0];
        $withRating = 0;

        foreach ($restaurants as $found) {
            $restaurant = $found->restaurant;

            foreach ($restaurant->cuisines as $cuisine) {
                $cuisines[$cuisine->slug] ??= ['slug' => $cuisine->slug, 'label' => $cuisine->cuisine, 'count' => 0];
                $cuisines[$cuisine->slug]['count']++;
            }

            foreach ($restaurant->facilities as $facility) {
                $facilities[$facility->slug] ??= ['slug' => $facility->slug, 'label' => $facility->facility, 'count' => 0];
                $facilities[$facility->slug]['count']++;
            }

            if ($restaurant->price_level !== null) {
                $level = (int) $restaurant->price_level;
                $prices[$level] = ($prices[$level] ?? 0) + 1;
            }

            if (AvailabilityFilter::OpenNow->matches($found->availability)) {
                $availability['open_now']++;
            }

            if (AvailabilityFilter::AcceptingOrders->matches($found->availability)) {
                $availability['accepting_orders']++;
            }

            if ($restaurant->rating_average !== null) {
                $withRating++;
            }
        }

        ksort($cuisines);
        ksort($facilities);
        ksort($prices);

        return [
            'cuisines' => array_values($cuisines),
            'facilities' => array_values($facilities),
            'price_levels' => array_map(
                static fn (int $level, int $count): array => ['level' => $level, 'count' => $count],
                array_keys($prices),
                array_values($prices),
            ),
            'availability' => [
                ['value' => AvailabilityFilter::OpenNow->value, 'label' => AvailabilityFilter::OpenNow->label(), 'count' => $availability['open_now']],
                ['value' => AvailabilityFilter::AcceptingOrders->value, 'label' => AvailabilityFilter::AcceptingOrders->label(), 'count' => $availability['accepting_orders']],
            ],
            // The client renders no rating control at all when this is false, so
            // a filter that cannot work is never offered. It becomes true on its
            // own the day a reviews module writes the first rating.
            'rating_available' => $withRating > 0,
            'sorts' => array_values(array_map(
                static fn (DiscoverySort $sort): array => [
                    'value' => $sort->value,
                    'label' => $sort->label(),
                    'available' => $sort->isAvailable(),
                    'unavailable_reason' => $sort->unavailableReason(),
                ],
                DiscoverySort::cases(),
            )),
            'max_detour_seconds' => (int) config('foodonthego.discovery.max_detour_duration_seconds'),
        ];
    }
}
