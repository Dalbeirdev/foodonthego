<?php

declare(strict_types=1);

namespace App\Services\Menu;

use App\Models\MenuCategory;
use App\Models\MenuItem;
use App\Models\Restaurant;
use App\Services\Restaurant\RestaurantHoursService;
use Carbon\CarbonImmutable;
use Illuminate\Support\Collection;

/**
 * A restaurant's menu, as a customer may see it.
 *
 * Everything invisible is excluded **in the query**, not filtered afterwards:
 * an inactive category never reaches PHP, so its items cannot leak through a
 * search or a direct lookup that forgot a check. The two relations are
 * scope-guarded at the model as well, which is belt and braces on the one rule
 * that would be embarrassing to get wrong.
 *
 * Two queries, whatever the size of the menu. Not one per category, and
 * certainly not one per item.
 */
final class CustomerMenuService
{
    public function __construct(
        private readonly MenuSearch $search,
        private readonly RestaurantHoursService $hours,
    ) {}

    /**
     * The whole visible menu, in the operator's order.
     */
    public function menu(
        Restaurant $restaurant,
        MenuQuery $query,
        CarbonImmutable $now,
    ): CustomerMenu {
        $localTime = $this->hours->localNow($restaurant, $now)->format('H:i:s');

        /** @var Collection<int, MenuCategory> $categories */
        $categories = MenuCategory::query()
            ->where('restaurant_id', $restaurant->id)
            ->where('is_active', true)
            // One query for every item in the menu, not one per category.
            ->with('items')
            ->orderBy('display_order')
            ->orderBy('id')
            ->get();

        $visibleTotal = 0;
        $matchedTotal = 0;
        $sections = [];

        foreach ($categories as $category) {
            if (! $category->isServedAt($localTime)) {
                // A breakfast section at four in the afternoon. Withheld rather
                // than shown greyed out: the customer cannot order it either
                // way, and a menu full of things they cannot have is harder to
                // read than a shorter one.
                continue;
            }

            /** @var Collection<int, MenuItem> $items */
            $items = $category->items;

            $visibleTotal += $items->count();

            $matching = $query->hasSearch()
                ? $this->search->matching($items, $category, (string) $query->search)
                : $items;

            if ($matching->isEmpty()) {
                // A category with nothing in it is not shown. "Desserts — no
                // items" is a row that answers a question nobody asked.
                continue;
            }

            $matchedTotal += $matching->count();

            $sections[] = new MenuSection($category, $matching->values()->all());
        }

        return new CustomerMenu(
            restaurant: $restaurant,
            sections: $sections,
            query: $query,
            visibleItemCount: $visibleTotal,
            matchedItemCount: $matchedTotal,
            generatedAt: $now,
        );
    }

    /**
     * One item, for the read-only preview.
     *
     * Scoped to the restaurant **and** to visibility, in one query. A caller
     * cannot pass a restaurant it likes with an item it likes and be given the
     * item: the `where` on `restaurant_id` is what makes the cross-restaurant
     * request return nothing rather than something.
     */
    public function item(Restaurant $restaurant, string $itemUuid): ?MenuItem
    {
        return MenuItem::query()
            ->where('restaurant_id', $restaurant->id)
            ->where('uuid', $itemUuid)
            ->where('is_active', true)
            ->whereHas('category', static function ($query): void {
                // An item in a withdrawn category is withdrawn. Otherwise
                // taking a category off the menu would leave its items
                // reachable by anybody who had already seen their ids.
                $query->where('is_active', true);
            })
            ->with('category')
            ->first();
    }

    /**
     * The same item, with everything needed to configure it.
     *
     * A separate method rather than an argument, because the two callers want
     * genuinely different things: the menu list needs a name and a price, and
     * the customization screen needs the sizes, the questions and every
     * answer. Loading the second for the first would be four eager loads
     * nobody renders.
     *
     * Four queries whatever the size of the customization — one for the item,
     * one for its variants, one for its groups, one for all of their options.
     * Not one per group, and not one per option.
     */
    public function itemForCustomization(Restaurant $restaurant, string $itemUuid): ?MenuItem
    {
        return MenuItem::query()
            ->where('restaurant_id', $restaurant->id)
            ->where('uuid', $itemUuid)
            ->where('is_active', true)
            ->whereHas('category', static function ($query): void {
                $query->where('is_active', true);
            })
            ->with(['category', 'variants', 'modifierGroups.options'])
            ->first();
    }
}
