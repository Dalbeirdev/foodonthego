<?php

declare(strict_types=1);

namespace Tests\Unit;

use App\Enums\DiscoverySort;
use App\Exceptions\ApiException;
use App\Services\Discovery\AvailabilityFilter;
use App\Services\Discovery\DiscoveryQuery;
use Illuminate\Http\Request;
use Tests\TestCase;

/**
 * What a client is allowed to ask for.
 *
 * The security boundary of this module. Everything downstream trusts this object
 * completely — the refiner does no validation of its own — so anything that gets
 * past here is what the rest of the code will act on.
 */
final class DiscoveryQueryTest extends TestCase
{
    private function query(array $params): DiscoveryQuery
    {
        return DiscoveryQuery::fromRequest(Request::create('/', 'GET', $params));
    }

    private function assertRejects(array $params, string $field): void
    {
        try {
            $this->query($params);
        } catch (ApiException $e) {
            // Named, not merely refused: a client with a bug needs to know which
            // parameter it got wrong.
            $this->assertArrayHasKey($field, $e->details['fields'] ?? []);

            return;
        }

        $this->fail("expected {$field} to be rejected");
    }

    public function test_an_empty_request_is_an_unfiltered_query(): void
    {
        $query = $this->query([]);

        $this->assertFalse($query->isRefined());
        $this->assertSame(DiscoverySort::Recommended, $query->sort);
        $this->assertSame(1, $query->page);
    }

    // --- search --------------------------------------------------------------

    public function test_a_search_is_trimmed_and_its_whitespace_collapsed(): void
    {
        // What a paste, a phone keyboard, or a hesitant typist produces.
        $this->assertSame(
            'highway spice',
            $this->query(['search' => "  highway   \t spice \n "])->search,
        );
    }

    public function test_a_search_shorter_than_the_minimum_is_no_search_at_all(): void
    {
        // Not an error — it is somebody who has typed one letter so far. One
        // character matches most of the corridor and costs a full request.
        $this->assertNull($this->query(['search' => 'h'])->search);
        $this->assertNull($this->query(['search' => '  '])->search);
        $this->assertSame('hi', $this->query(['search' => 'hi'])->search);
    }

    public function test_an_oversized_search_is_refused_rather_than_truncated(): void
    {
        // Truncating would answer a question nobody asked and hide the client's
        // bug.
        $this->assertRejects(['search' => str_repeat('a', 101)], 'search');
    }

    public function test_a_search_of_exactly_the_maximum_length_is_accepted(): void
    {
        $this->assertNotNull($this->query(['search' => str_repeat('a', 100)])->search);
    }

    // --- slugs ---------------------------------------------------------------

    public function test_slugs_are_deduplicated_and_sorted(): void
    {
        // So that two requests meaning the same thing *are* the same thing, and
        // share a cache entry.
        $this->assertSame(
            ['north_indian', 'south_indian'],
            $this->query(['cuisines' => 'south_indian,north_indian,south_indian'])->cuisines,
        );
    }

    public function test_reordered_filters_produce_the_same_fingerprint(): void
    {
        $one = $this->query(['facilities' => 'parking,restroom']);
        $two = $this->query(['facilities' => 'restroom,parking']);

        $this->assertSame($one->fingerprint(), $two->fingerprint());
    }

    public function test_a_display_label_is_not_an_identifier(): void
    {
        // Filtering by "North Indian" would break the first time somebody fixes
        // the label's capitalisation, and cannot survive translation at all.
        $this->assertRejects(['cuisines' => 'North Indian'], 'cuisines');
    }

    public function test_a_slug_that_could_only_be_an_attack_is_refused(): void
    {
        foreach ([
            "' OR 1=1--",
            'parking; DROP TABLE restaurants',
            '../../etc/passwd',
            '<script>alert(1)</script>',
            'parking%00',
        ] as $attempt) {
            $this->assertRejects(['facilities' => $attempt], 'facilities');
        }
    }

    public function test_too_many_filter_values_are_refused(): void
    {
        // There are eight cuisines in the whole database. A request naming a
        // hundred is not a customer.
        $many = implode(',', array_map(
            static fn (int $i): string => "cuisine_{$i}",
            range(1, 30),
        ));

        $this->assertRejects(['cuisines' => $many], 'cuisines');
    }

    // --- numbers -------------------------------------------------------------

    public function test_a_negative_detour_is_refused(): void
    {
        $this->assertRejects(['max_detour_seconds' => '-500'], 'max_detour_seconds');
    }

    public function test_a_detour_beyond_the_business_maximum_is_refused(): void
    {
        // A customer cannot filter for stops the platform has already decided
        // are not stops on this journey.
        $max = (int) config('foodonthego.discovery.max_detour_duration_seconds');

        $this->assertRejects(['max_detour_seconds' => (string) ($max + 1)], 'max_detour_seconds');
        $this->assertSame($max, $this->query(['max_detour_seconds' => (string) $max])->maxDetourSeconds);
    }

    public function test_a_non_numeric_detour_is_refused(): void
    {
        $this->assertRejects(['max_detour_seconds' => '10 minutes'], 'max_detour_seconds');
    }

    public function test_price_levels_are_one_to_four(): void
    {
        $this->assertSame([1, 2], $this->query(['price_levels' => '2,1'])->priceLevels);
        $this->assertRejects(['price_levels' => '0'], 'price_levels');
        $this->assertRejects(['price_levels' => '9'], 'price_levels');
        $this->assertRejects(['price_levels' => 'cheap'], 'price_levels');
    }

    public function test_a_rating_outside_the_scale_is_refused(): void
    {
        $this->assertRejects(['min_rating' => '7'], 'min_rating');
        $this->assertRejects(['min_rating' => '-1'], 'min_rating');
        $this->assertSame(4.0, $this->query(['min_rating' => '4'])->minRating);
    }

    // --- sort ----------------------------------------------------------------

    public function test_an_unknown_sort_is_refused(): void
    {
        // The value can only ever become an enum case with a hand-written
        // comparator behind it. It never reaches a column name.
        $this->assertRejects(['sort' => 'destroy_database'], 'sort');
        $this->assertRejects(['sort' => 'name; DROP TABLE restaurants'], 'sort');
    }

    public function test_a_sort_this_product_cannot_honestly_offer_is_refused(): void
    {
        // Rating sorting over data that does not exist would produce an
        // arbitrary order presented as "Highest rated", which is a lie about
        // restaurants.
        $this->assertRejects(['sort' => 'highest_rated'], 'sort');
    }

    public function test_every_available_sort_is_accepted(): void
    {
        foreach (DiscoverySort::cases() as $sort) {
            if (! $sort->isAvailable()) {
                continue;
            }

            $this->assertSame($sort, $this->query(['sort' => $sort->value])->sort);
        }
    }

    // --- pagination ----------------------------------------------------------

    public function test_a_page_size_is_bounded(): void
    {
        $this->assertRejects(['per_page' => '999'], 'per_page');
        $this->assertRejects(['per_page' => '0'], 'per_page');
        $this->assertRejects(['per_page' => '-1'], 'per_page');
        $this->assertSame(10, $this->query(['per_page' => '10'])->perPage);
    }

    public function test_availability_is_one_of_two_documented_values(): void
    {
        $this->assertSame(
            AvailabilityFilter::AcceptingOrders,
            $this->query(['availability' => 'accepting_orders'])->availability,
        );

        $this->assertRejects(['availability' => 'open_24_hours'], 'availability');
    }

    public function test_the_fingerprint_distinguishes_everything_that_matters(): void
    {
        $base = $this->query(['cuisines' => 'cafe']);

        foreach ([
            ['cuisines' => 'bakery'],
            ['cuisines' => 'cafe', 'facilities' => 'parking'],
            ['cuisines' => 'cafe', 'sort' => 'lowest_detour'],
            ['cuisines' => 'cafe', 'page' => '2'],
            ['cuisines' => 'cafe', 'search' => 'spice'],
            ['cuisines' => 'cafe', 'per_page' => '5'],
        ] as $different) {
            $this->assertNotSame(
                $base->fingerprint(),
                $this->query($different)->fingerprint(),
                'a cache key that ignores '.implode(',', array_keys($different))
                    .' serves one filter\'s results for another\'s request',
            );
        }
    }

    public function test_the_query_reports_itself_as_the_server_understood_it(): void
    {
        $applied = $this->query([
            'search' => ' Cafe ',
            'facilities' => 'restroom,parking',
            'sort' => 'lowest_detour',
        ])->toApiArray();

        // The fastest way for a client to notice a parameter it got wrong.
        $this->assertSame('Cafe', $applied['search']);
        $this->assertSame(['parking', 'restroom'], $applied['facilities']);
        $this->assertSame('lowest_detour', $applied['sort']);
    }
}
