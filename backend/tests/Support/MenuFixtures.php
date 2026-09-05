<?php

declare(strict_types=1);

namespace Tests\Support;

use App\Enums\MenuItemDietaryType;
use App\Enums\MenuItemStockStatus;
use App\Models\MenuCategory;
use App\Models\MenuItem;
use App\Models\Restaurant;
use Illuminate\Support\Str;

/**
 * Building a menu a test can reason about.
 *
 * Every field is stated rather than defaulted, because the interesting part of
 * a menu test is usually *which* field is missing.
 */
final class MenuFixtures
{
    /** @param array<string, mixed> $options */
    public static function category(
        Restaurant $restaurant,
        string $name,
        int $order = 0,
        array $options = [],
    ): MenuCategory {
        $category = new MenuCategory;

        $category->forceFill([
            'uuid' => (string) Str::uuid(),
            'restaurant_id' => $restaurant->id,
            'name' => $name,
            'description' => $options['description'] ?? null,
            'display_order' => $order,
            'is_active' => $options['active'] ?? true,
            'available_from' => $options['from'] ?? null,
            'available_until' => $options['until'] ?? null,
        ])->save();

        return $category;
    }

    /** @param array<string, mixed> $options */
    public static function item(
        MenuCategory $category,
        string $name,
        int $priceMinor = 24_900,
        array $options = [],
    ): MenuItem {
        $item = new MenuItem;

        $item->forceFill([
            'uuid' => (string) Str::uuid(),
            'restaurant_id' => $category->restaurant_id,
            'menu_category_id' => $category->id,
            'name' => $name,
            'description' => $options['description'] ?? null,
            'base_price_minor' => $priceMinor,
            'currency' => $options['currency'] ?? 'INR',
            'image_url' => $options['image'] ?? null,
            'thumbnail_url' => $options['thumbnail'] ?? null,
            'preparation_minutes' => $options['preparation_minutes'] ?? null,
            'dietary_type' => self::dietary($options['dietary'] ?? null),
            'spice_level' => $options['spice_level'] ?? null,
            'is_active' => $options['active'] ?? true,
            'stock_status' => ($options['stock'] ?? MenuItemStockStatus::InStock)->value,
            'display_order' => $options['order'] ?? 0,
        ])->save();

        return $item;
    }

    private static function dietary(mixed $value): ?string
    {
        return $value instanceof MenuItemDietaryType ? $value->value : null;
    }

    /**
     * A small, ordinary menu: three categories, six items.
     *
     * @return array{starters: MenuCategory, mains: MenuCategory, drinks: MenuCategory}
     */
    public static function ordinaryMenu(Restaurant $restaurant): array
    {
        $starters = self::category($restaurant, 'Starters', 0);
        self::item($starters, 'Paneer Tikka', 24_900, [
            'description' => 'Cottage cheese in the tandoor.',
            'preparation_minutes' => 15,
            'dietary' => MenuItemDietaryType::Vegetarian,
            'order' => 0,
        ]);
        self::item($starters, 'Chicken Kebab', 32_900, [
            'dietary' => MenuItemDietaryType::NonVegetarian,
            'order' => 1,
        ]);

        $mains = self::category($restaurant, 'Main Course', 1);
        self::item($mains, 'Dal Makhani', 29_900, ['order' => 0]);
        self::item($mains, 'Paneer Butter Masala', 34_900, ['order' => 1]);

        $drinks = self::category($restaurant, 'Beverages', 2);
        self::item($drinks, 'Masala Chai', 4_900, ['order' => 0]);
        self::item($drinks, 'Table Water', 0, ['order' => 1]);

        return ['starters' => $starters, 'mains' => $mains, 'drinks' => $drinks];
    }
}
