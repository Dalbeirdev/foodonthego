<?php

declare(strict_types=1);

namespace App\Services\Menu;

use App\Models\MenuCategory;
use App\Models\MenuItem;

/** One category, and the items of it the customer may see. */
final readonly class MenuSection
{
    /** @param list<MenuItem> $items */
    public function __construct(
        public MenuCategory $category,
        public array $items,
    ) {}

    /** @return array<string, mixed> */
    public function toApiArray(): array
    {
        $items = [];

        foreach ($this->items as $item) {
            $rendered = $item->toCustomerArray($this->category);

            // Null means the row could not be rendered honestly — today, only a
            // price that will not parse. One bad record drops out; the rest of
            // the menu is unaffected.
            if ($rendered !== null) {
                $items[] = $rendered;
            }
        }

        return [
            'id' => $this->category->uuid,
            'name' => $this->category->name,
            'description' => $this->description(),
            'items' => $items,
        ];
    }

    private function description(): ?string
    {
        $description = trim((string) $this->category->description);

        return $description === '' ? null : $description;
    }
}
