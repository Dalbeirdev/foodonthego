<?php

declare(strict_types=1);

namespace Tests\Unit;

use App\Enums\RestaurantAvailability;
use App\Services\Discovery\DetourEstimate;
use App\Services\Discovery\DiscoveryRankingService;
use PHPUnit\Framework\TestCase;

/**
 * The score, and the promise that it is explainable.
 *
 * Every assertion here is a product statement rather than a numeric one: which
 * of two restaurants should win, and why. A formula nobody can reason about is
 * one nobody can defend when an operator asks why they are fourth.
 */
final class DiscoveryRankingTest extends TestCase
{
    private DiscoveryRankingService $ranking;

    protected function setUp(): void
    {
        parent::setUp();

        // Fifteen minutes and five kilometres, matching the shipped defaults.
        $this->ranking = new DiscoveryRankingService(
            maxDetourDurationSeconds: 900,
            corridorMetres: 5_000,
        );
    }

    private function score(
        ?int $detourSeconds,
        float $proximity = 1_000,
        RestaurantAvailability $availability = RestaurantAvailability::Open,
        ?string $rating = null,
        bool $backtracking = false,
    ): float {
        return $this->ranking->score(
            $availability,
            $detourSeconds === null ? null : new DetourEstimate(1_000, $detourSeconds, 'test'),
            $proximity,
            $rating,
            $backtracking,
        );
    }

    public function test_a_short_detour_beats_a_long_one(): void
    {
        $this->assertGreaterThan($this->score(720), $this->score(120));
    }

    public function test_a_low_detour_beats_a_closer_restaurant_with_a_high_one(): void
    {
        // The example from the specification, and the reason this is a route
        // product: 300 m away and eighteen minutes' driving loses to 1.2 km away
        // and four minutes'.
        $closeButAwkward = $this->score(1_080, proximity: 300);
        $furtherButEasy = $this->score(240, proximity: 1_200);

        $this->assertGreaterThan($closeButAwkward, $furtherButEasy);
    }

    public function test_an_open_restaurant_beats_a_closed_one_all_else_equal(): void
    {
        $this->assertGreaterThan(
            $this->score(240, availability: RestaurantAvailability::Closed),
            $this->score(240, availability: RestaurantAvailability::Open),
        );
    }

    public function test_a_paused_restaurant_ranks_below_one_that_opens_shortly(): void
    {
        // "Opens in twenty minutes" becomes actionable during the drive. "Open
        // but not cooking" may not.
        $this->assertGreaterThan(
            $this->score(240, availability: RestaurantAvailability::NotAcceptingOrders),
            $this->score(240, availability: RestaurantAvailability::OpeningSoon),
        );
    }

    public function test_availability_does_not_outrank_a_far_better_detour(): void
    {
        // Deliberate: a closed restaurant four minutes away is worth seeing
        // above an open one fifteen minutes off the road, because the traveller
        // may be hours from either.
        $openButAwkward = $this->score(900, availability: RestaurantAvailability::Open);
        $closedAndEasy = $this->score(60, availability: RestaurantAvailability::Closed);

        $this->assertGreaterThan($openButAwkward, $closedAndEasy);
    }

    public function test_an_unknown_detour_sits_between_a_good_one_and_a_bad_one(): void
    {
        $unknown = $this->score(null);

        $this->assertLessThan($this->score(120), $unknown);
        $this->assertGreaterThan($this->score(840), $unknown);
    }

    public function test_rating_never_decides_between_two_convenient_stops(): void
    {
        // Sorting by rating is what a generic listings app does. Here a rating
        // is worth a tenth of the score, so it breaks ties and nothing else.
        $wellRatedAwkward = $this->score(900, rating: '5.0');
        $unratedEasy = $this->score(60, rating: null);

        $this->assertGreaterThan($wellRatedAwkward, $unratedEasy);
    }

    public function test_a_missing_rating_is_neither_rewarded_nor_punished(): void
    {
        $unrated = $this->score(300, rating: null);

        $this->assertGreaterThan($this->score(300, rating: '1.0'), $unrated);
        $this->assertLessThan($this->score(300, rating: '5.0'), $unrated);
    }

    public function test_backtracking_halves_the_score(): void
    {
        $forward = $this->score(120);
        $backward = $this->score(120, backtracking: true);

        $this->assertEqualsWithDelta($forward / 2, $backward, 0.0001);
    }

    public function test_a_perfect_stop_scores_near_one_and_a_hopeless_one_near_zero(): void
    {
        $best = $this->ranking->score(
            RestaurantAvailability::Open,
            new DetourEstimate(0, 0, 'test'),
            0.0,
            '5.0',
            false,
        );

        $worst = $this->ranking->score(
            RestaurantAvailability::Closed,
            new DetourEstimate(15_000, 900, 'test'),
            5_000.0,
            '0.0',
            true,
        );

        $this->assertEqualsWithDelta(1.0, $best, 0.001);
        $this->assertLessThan(0.1, $worst);
    }

    public function test_the_same_inputs_always_give_the_same_score(): void
    {
        // Determinism is the whole claim. A score that moves between two calls
        // cannot be explained to anybody.
        $first = $this->score(240, 1_200, RestaurantAvailability::Open, '4.2');
        $second = $this->score(240, 1_200, RestaurantAvailability::Open, '4.2');

        $this->assertSame($first, $second);
    }
}
