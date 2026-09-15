<?php

declare(strict_types=1);

namespace App\Services\Menu;

use App\Models\Restaurant;
use Carbon\CarbonImmutable;

/**
 * A restaurant's menu, ready to send.
 *
 * The two counts are the point, and they are the menu equivalent of Module 08's
 * two totals. `visibleItemCount` is how many items this restaurant has on its
 * menu at all; `matchedItemCount` is how many the customer's search left. An
 * empty screen with the first at zero means "no menu yet"; an empty screen with
 * the first at forty means "your search found nothing", and those need
 * different words and different buttons.
 */
final readonly class CustomerMenu
{
    /** @param list<MenuSection> $sections */
    public function __construct(
        public Restaurant $restaurant,
        public array $sections,
        public MenuQuery $query,
        public int $visibleItemCount,
        public int $matchedItemCount,
        public CarbonImmutable $generatedAt,
    ) {}

    /** The restaurant has published nothing a customer may see. */
    public function isEmpty(): bool
    {
        return $this->visibleItemCount === 0;
    }

    /** There is a menu; the search left none of it. */
    public function isSearchEmpty(): bool
    {
        return $this->matchedItemCount === 0
            && $this->visibleItemCount > 0
            && $this->query->hasSearch();
    }

    /** @return array<string, mixed> */
    public function toApiArray(): array
    {
        return [
            'categories' => array_map(
                static fn (MenuSection $section): array => $section->toApiArray(),
                $this->sections,
            ),
            'meta' => [
                'category_count' => count($this->sections),
                'item_count' => $this->matchedItemCount,

                // How many were on the menu before the customer searched, so an
                // empty screen can tell the two empty states apart.
                'visible_item_count' => $this->visibleItemCount,
                'search_empty' => $this->isSearchEmpty(),
                'menu_empty' => $this->isEmpty(),

                // The query as the server understood it — the fastest way for a
                // client to notice a parameter it thought it sent and did not.
                'applied' => $this->query->toApiArray(),

                // So an offline screen can say how old what it is showing is,
                // rather than implying the prices are live.
                'generated_at' => $this->generatedAt->utc()->toIso8601String(),
            ],
        ];
    }
}
