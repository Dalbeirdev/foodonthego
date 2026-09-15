<?php

declare(strict_types=1);

namespace App\Services\Menu;

use App\Models\MenuCategory;
use App\Models\MenuItem;
use Illuminate\Support\Collection;
use Normalizer;

/**
 * Searching inside one restaurant's menu.
 *
 * **In memory, over items already fetched.** The menu was loaded to be shown;
 * searching it is a filter over what is in hand, not a second trip to the
 * database. Two consequences worth stating: a search cannot reach an item the
 * visibility rules already excluded, because those items were never loaded; and
 * a search term never becomes SQL, because there is no query for it to become
 * part of.
 *
 * That decision is right at pilot scale and is measured rather than assumed —
 * see the large-menu figures in `25-customer-menu-browsing.md`. A menu large
 * enough to change the answer would move this to an indexed query, and the
 * *shape* would not change: the same visibility scopes, applied first.
 */
final class MenuSearch
{
    /**
     * The items of one category that match.
     *
     * Name first, then the category's own name, then the description. A
     * customer searching "Beverages" means the section; one searching "paneer"
     * means the dish; and a description match is a weak last resort rather than
     * a reason to return half the menu.
     *
     * @param  Collection<int, MenuItem>  $items
     * @return Collection<int, MenuItem>
     */
    public function matching(
        Collection $items,
        MenuCategory $category,
        string $term,
    ): Collection {
        $needle = self::normalise($term);

        if ($needle === '') {
            return $items;
        }

        // A category whose own name matches keeps all of its items. Searching
        // "Breads" and being shown three of eight breads, because five of them
        // do not have the word in their name, is worse than useless.
        if (str_contains(self::normalise($category->name), $needle)) {
            return $items;
        }

        return $items->filter(
            static fn (MenuItem $item): bool => self::matches($item, $needle),
        );
    }

    private static function matches(MenuItem $item, string $needle): bool
    {
        if (str_contains(self::normalise((string) $item->name), $needle)) {
            return true;
        }

        $description = $item->customerDescription();

        return $description !== null
            && str_contains(self::normalise($description), $needle);
    }

    /**
     * Case, accents and punctuation folded away.
     *
     * `Normalizer::FORM_D` plus stripping combining marks, so `Café` matches
     * `cafe`. Deliberately **not** `iconv('UTF-8', 'ASCII//TRANSLIT')`, which
     * turns `पनीर टिक्का` into a row of question marks and makes every
     * Devanagari dish match every other — the same trap Module 08 hit and the
     * same fix.
     */
    public static function normalise(string $value): string
    {
        $value = mb_strtolower(trim($value));

        if (class_exists(Normalizer::class)) {
            $decomposed = Normalizer::normalize($value, Normalizer::FORM_D);

            if (is_string($decomposed)) {
                $value = (string) preg_replace('/\p{Mn}+/u', '', $decomposed);
            }
        }

        // Apostrophes are elisions, not separators: "chefs" should find
        // "Chef's Special".
        $value = str_replace(["'", '’', '`'], '', $value);

        $value = (string) preg_replace('/[^\p{L}\p{N}]+/u', ' ', $value);

        return trim((string) preg_replace('/\s+/u', ' ', $value));
    }
}
