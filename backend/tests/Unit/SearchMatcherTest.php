<?php

declare(strict_types=1);

namespace Tests\Unit;

use App\Services\Discovery\SearchMatcher;
use PHPUnit\Framework\TestCase;

/**
 * What "matches" means, and what "matches better" means.
 *
 * The ordering assertions matter more than the boolean ones. A search for
 * "Highway Spice" that finds Highway Spice Kitchen but ranks a restaurant in
 * Highway Town above it is a worse answer than no search at all.
 */
final class SearchMatcherTest extends TestCase
{
    private SearchMatcher $matcher;

    protected function setUp(): void
    {
        parent::setUp();

        $this->matcher = new SearchMatcher;
    }

    private function score(
        string $search,
        string $name = 'Highway Spice Kitchen',
        array $cuisines = ['North Indian', 'Vegetarian'],
        ?string $city = 'Behror',
    ): float {
        return $this->matcher->score($search, $name, $cuisines, $city);
    }

    public function test_an_exact_name_is_the_strongest_possible_match(): void
    {
        $this->assertSame(1.0, $this->score('Highway Spice Kitchen'));
    }

    public function test_a_name_prefix_beats_a_name_substring(): void
    {
        $prefix = $this->score('Highway Spice');
        $substring = $this->score('Spice Kitchen');

        $this->assertGreaterThan(0.0, $substring);
        $this->assertGreaterThan($substring, $prefix);
    }

    public function test_a_name_match_beats_a_cuisine_match(): void
    {
        // Somebody typing a restaurant's name is asking for that restaurant.
        $byName = $this->score('Highway');
        $byCuisine = $this->score('North Indian');

        $this->assertGreaterThan($byCuisine, $byName);
    }

    public function test_a_cuisine_match_beats_a_town_match(): void
    {
        // The trap this ordering exists for: a weak locality match must never
        // outrank a real cuisine match.
        $byCuisine = $this->score('Vegetarian');
        $byCity = $this->score('Behror');

        $this->assertGreaterThan(0.0, $byCity);
        $this->assertGreaterThan($byCity, $byCuisine);
    }

    public function test_case_and_surrounding_whitespace_are_irrelevant(): void
    {
        $this->assertSame($this->score('HIGHWAY SPICE'), $this->score('highway spice'));
        $this->assertGreaterThan(0.0, $this->score('  highway spice  '));
    }

    public function test_words_in_any_order_still_match_the_name(): void
    {
        // "spice highway" is somebody remembering the words but not the order.
        $this->assertGreaterThan(0.0, $this->score('spice highway'));

        // And it scores below the phrase, which is the stronger evidence.
        $this->assertGreaterThan($this->score('spice highway'), $this->score('highway spice'));
    }

    public function test_accents_and_punctuation_do_not_prevent_a_match(): void
    {
        $this->assertGreaterThan(0.0, $this->matcher->score('cafe', 'Café Rajasthan', [], null));
        $this->assertGreaterThan(0.0, $this->matcher->score('rajeshs', "Rajesh's Dhaba", [], null));
        $this->assertGreaterThan(0.0, $this->matcher->score("rajesh's", 'Rajeshs Dhaba', [], null));
    }

    public function test_an_unrelated_search_matches_nothing(): void
    {
        $this->assertSame(0.0, $this->score('Sushi Palace XYZ'));
        $this->assertSame(0.0, $this->score('biryani'));
    }

    public function test_a_partial_cuisine_word_matches(): void
    {
        // "indian" should find North Indian.
        $this->assertGreaterThan(0.0, $this->score('indian'));
    }

    public function test_a_restaurant_with_no_cuisines_or_city_is_handled(): void
    {
        $this->assertSame(0.0, $this->matcher->score('indian', 'Plain Dhaba', [], null));
        $this->assertGreaterThan(0.0, $this->matcher->score('plain', 'Plain Dhaba', [], null));
    }

    public function test_an_empty_search_matches_nothing_rather_than_everything(): void
    {
        // A blank search must never become a wildcard.
        $this->assertSame(0.0, $this->score(''));
        $this->assertSame(0.0, $this->score('   '));
    }

    public function test_a_search_of_only_punctuation_matches_nothing(): void
    {
        $this->assertSame(0.0, $this->score('!!!'));
        $this->assertSame(0.0, $this->score('%%'));
    }

    public function test_a_wildcard_is_a_literal_not_a_pattern(): void
    {
        // Matching happens in PHP over values already loaded, so a SQL or glob
        // wildcard is never a pattern. What matters is that it cannot match
        // *everything*: "%" alone is punctuation and finds nothing, and
        // "%spice%" is simply a search for "spice".
        $this->assertSame(0.0, $this->score('%'));
        $this->assertSame(0.0, $this->score('_'));
        $this->assertSame($this->score('spice'), $this->score('%spice%'));
        $this->assertSame(0.0, $this->score('%sushi%'));
    }

    public function test_unicode_is_handled_without_mangling(): void
    {
        // `strtolower` is byte-oriented and would corrupt this; `mb_strtolower`
        // does not. A product shipping in India will meet names like these.
        $this->assertGreaterThan(0.0, $this->matcher->score('ढाबा', 'शर्मा ढाबा', [], null));
        $this->assertSame(0.0, $this->matcher->score('ढाबा', 'Highway Spice', [], null));
    }
}
