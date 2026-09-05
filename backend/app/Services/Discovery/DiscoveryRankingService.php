<?php

declare(strict_types=1);

namespace App\Services\Discovery;

use App\Enums\RestaurantAvailability;

/**
 * The order restaurants are offered in.
 *
 * Deterministic and explainable, by rule: the same inputs give the same order,
 * every term is a number somebody can point at, and there is no model. A
 * traveller asking "why is this one first" deserves an answer, and "the
 * recommender said so" is not one.
 *
 * ## The formula
 *
 * A score in [0, 1], the weighted sum of four terms:
 *
 * | Term             | Weight | What it rewards                               |
 * | ---------------- | -----: | --------------------------------------------- |
 * | Detour           |   0.45 | Costing little to stop at                     |
 * | Availability     |   0.30 | Being open, and taking orders                 |
 * | Proximity        |   0.15 | Sitting close to the road                     |
 * | Quality          |   0.10 | Being well rated, where a rating exists       |
 * | Search relevance |   0.60 | Being what the customer actually asked for    |
 *
 * The weights live in `config('foodonthego.discovery.weights')`, not here, and
 * the score is normalised by their sum — so they are shares rather than
 * magnitudes and can be retuned without a release.
 *
 * Search relevance is the largest of them and is applied **only** when the
 * customer typed something. Somebody who searched "Highway Spice" is asking for
 * one restaurant, not for the most convenient stop that happens to match.
 *
 * Detour dominates on purpose. It is the whole reason this is a route product
 * rather than a nearby-restaurants product: the stop that costs four minutes
 * beats the one that costs eighteen, whatever else is true of them.
 *
 * Availability is second and heavily weighted because a closed restaurant is not
 * a stop today, however convenient it is.
 *
 * Quality is last and lightest, and it is *not* the sort order — sorting by
 * rating is what a generic listings app does, and it would put a five-star
 * restaurant forty minutes off the route above a good one on it. Today it is
 * inert in any case: there is no reviews module, so every real row's rating is
 * null and scores 0.5, which affects nothing because it affects everything
 * equally.
 *
 * ## What is deliberately not here
 *
 * Distance ahead. A restaurant 20 km along the route is not better or worse than
 * one 120 km along — it is a different meal — so it does not enter the score at
 * all. It decides the *list order* instead: results come back in journey order,
 * because a traveller reads them as a sequence of chances to stop, and the score
 * decides which restaurants make the list rather than where they sit in it.
 */
final class DiscoveryRankingService
{
    public function __construct(
        private readonly int $maxDetourDurationSeconds,
        private readonly int $corridorMetres,
        /** @var array{detour: float, availability: float, proximity: float, rating: float, search_relevance: float} */
        private readonly array $weights,
    ) {}

    /**
     * @param  ?float  $searchRelevance  0..1 from {@see SearchMatcher}, or null
     *                                   when the customer typed nothing. Null and 0.0 are different: null
     *                                   removes the term from the average, 0.0 is a restaurant that matched
     *                                   nothing — and if it matched nothing it is not in the set at all.
     */
    public function score(
        RestaurantAvailability $availability,
        ?DetourEstimate $detour,
        float $proximityMetres,
        ?string $rating,
        bool $requiresBacktracking,
        ?float $searchRelevance = null,
    ): float {
        // A list of [weight, value] pairs, and deliberately not a map keyed by
        // weight. PHP casts a float array key to an int, so `[0.45 => …, 0.30
        // => …]` is one entry under key 0 holding the last value — which is
        // exactly what the first version of this method did, and every
        // restaurant scored zero.
        $terms = [
            [$this->weights['detour'], $this->detourTerm($detour)],
            [$this->weights['availability'], $this->availabilityTerm($availability)],
            [$this->weights['proximity'], $this->proximityTerm($proximityMetres)],
            [$this->weights['rating'], $this->qualityTerm($rating)],
        ];

        $weighted = 0.0;
        $total = 0.0;

        foreach ($terms as [$weight, $value]) {
            $weighted += $weight * $value;
            $total += $weight;
        }

        // Search relevance joins the average only when there is a search, which
        // is what keeps a searchless result identical to Module 07's ordering
        // rather than subtly reweighted by a term that is always zero.
        if ($searchRelevance !== null) {
            $weight = $this->weights['search_relevance'];
            $weighted += $weight * max(0.0, min(1.0, $searchRelevance));
            $total += $weight;
        }

        // Normalised, so the weights are shares rather than magnitudes: doubling
        // all five changes nothing, and the score stays in [0, 1] whatever
        // somebody puts in the configuration file.
        $score = $total > 0.0 ? $weighted / $total : 0.0;

        // Halved rather than excluded. A restaurant behind the origin is a poor
        // stop for somebody setting off, but it is a real restaurant on a real
        // road and the customer may be standing next to it — so it sinks rather
        // than vanishing.
        return $requiresBacktracking ? $score * 0.5 : $score;
    }

    /**
     * 1.0 for a free stop, falling to 0 at the configured limit.
     *
     * An unknown detour scores 0.35 — below a measured short one, above a
     * measured long one. It is a deliberate statement of ignorance: we will show
     * you this, we cannot tell you what it costs, and we will not put it first.
     */
    private function detourTerm(?DetourEstimate $detour): float
    {
        if ($detour === null) {
            return 0.35;
        }

        if ($this->maxDetourDurationSeconds <= 0) {
            return 1.0;
        }

        $ratio = $detour->extraDurationSeconds / $this->maxDetourDurationSeconds;

        return max(0.0, min(1.0, 1.0 - $ratio));
    }

    private function availabilityTerm(RestaurantAvailability $availability): float
    {
        return match ($availability) {
            RestaurantAvailability::Open => 1.0,
            RestaurantAvailability::ClosingSoon => 0.75,
            RestaurantAvailability::OpeningSoon => 0.5,
            // Open by the clock but not cooking. Below "opens in twenty minutes",
            // because that one becomes actionable and this one may not.
            RestaurantAvailability::NotAcceptingOrders => 0.2,
            RestaurantAvailability::Closed => 0.1,
            // No hours on file. Not a claim either way, scored between.
            RestaurantAvailability::Unknown => 0.3,
        };
    }

    private function proximityTerm(float $proximityMetres): float
    {
        if ($this->corridorMetres <= 0) {
            return 1.0;
        }

        return max(0.0, min(1.0, 1.0 - ($proximityMetres / $this->corridorMetres)));
    }

    /**
     * A missing rating scores exactly the middle.
     *
     * Not zero, which would push every unrated restaurant below every rated one
     * and, with no reviews module, that is all of them. Not one, which would
     * reward having no reviews. The middle says nothing, which is the truth.
     */
    private function qualityTerm(?string $rating): float
    {
        if ($rating === null) {
            return 0.5;
        }

        return max(0.0, min(1.0, ((float) $rating) / 5.0));
    }
}
