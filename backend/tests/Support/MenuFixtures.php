<?php

declare(strict_types=1);

namespace Tests\Support;

use App\Enums\MenuItemDietaryType;
use App\Enums\MenuItemStockStatus;
use App\Models\MenuCategory;
use App\Models\MenuItem;
use App\Models\MenuItemVariant;
use App\Models\MenuModifierGroup;
use App\Models\MenuModifierOption;
use App\Models\Restaurant;
use Illuminate\Support\Facades\DB;
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

    /**
     * A size of a dish (Module 11). The price is absolute.
     *
     * @param  array<string, mixed>  $options
     */
    public static function variant(
        MenuItem $item,
        string $name,
        int $priceMinor,
        array $options = [],
    ): MenuItemVariant {
        $variant = new MenuItemVariant;

        $variant->forceFill([
            'uuid' => (string) Str::uuid(),
            'menu_item_id' => $item->id,
            'restaurant_id' => $item->restaurant_id,
            'name' => $name,
            'description' => $options['description'] ?? null,
            'price_minor' => $priceMinor,
            'currency' => $options['currency'] ?? 'INR',
            'preparation_minutes' => $options['preparation_minutes'] ?? null,
            'is_active' => $options['active'] ?? true,
            'is_available' => $options['available'] ?? true,
            'is_default' => $options['default'] ?? false,
            'display_order' => $options['order'] ?? 0,
        ])->save();

        return $variant;
    }

    /**
     * A question the kitchen asks. `min` and `max` are the whole rule.
     *
     * @param  array<string, mixed>  $options
     */
    public static function group(
        Restaurant $restaurant,
        string $name,
        int $min = 0,
        int $max = 1,
        array $options = [],
    ): MenuModifierGroup {
        $group = new MenuModifierGroup;

        $group->forceFill([
            'uuid' => (string) Str::uuid(),
            'restaurant_id' => $restaurant->id,
            'name' => $name,
            'description' => $options['description'] ?? null,
            'min_select' => $min,
            'max_select' => $max,
            'is_required' => $min >= 1,
            'is_active' => $options['active'] ?? true,
            'display_order' => $options['order'] ?? 0,
        ])->save();

        return $group;
    }

    /**
     * One answer. The price is a delta, and never negative.
     *
     * @param  array<string, mixed>  $options
     */
    public static function option(
        MenuModifierGroup $group,
        string $name,
        int $deltaMinor = 0,
        array $options = [],
    ): MenuModifierOption {
        $option = new MenuModifierOption;

        $option->forceFill([
            'uuid' => (string) Str::uuid(),
            'menu_modifier_group_id' => $group->id,
            'restaurant_id' => $group->restaurant_id,
            'name' => $name,
            'description' => $options['description'] ?? null,
            'price_delta_minor' => $deltaMinor,
            'currency' => $options['currency'] ?? 'INR',
            'is_active' => $options['active'] ?? true,
            'is_available' => $options['available'] ?? true,
            'is_default' => $options['default'] ?? false,
            'display_order' => $options['order'] ?? 0,
        ])->save();

        return $option;
    }

    /** Asks a question about a dish. */
    public static function attach(MenuItem $item, MenuModifierGroup $group, int $order = 0): void
    {
        DB::table('menu_item_modifier_group')->insert([
            'menu_item_id' => $item->id,
            'menu_modifier_group_id' => $group->id,
            'restaurant_id' => $item->restaurant_id,
            'display_order' => $order,
            'created_at' => now(),
            'updated_at' => now(),
        ]);
    }

    /**
     * A fully configurable dish: two sizes with a default, one required
     * single-select group, one optional multi-select group with paid options.
     *
     * @return array{
     *     item: MenuItem,
     *     regular: MenuItemVariant,
     *     large: MenuItemVariant,
     *     spice: MenuModifierGroup,
     *     mild: MenuModifierOption,
     *     hot: MenuModifierOption,
     *     extras: MenuModifierGroup,
     *     cheese: MenuModifierOption,
     *     jalapeno: MenuModifierOption
     * }
     */
    public static function configurableItem(Restaurant $restaurant): array
    {
        $category = self::category($restaurant, 'Starters', 0);
        $item = self::item($category, 'Paneer Tikka', 24_900, [
            'description' => 'Cottage cheese in the tandoor.',
            'preparation_minutes' => 15,
            'dietary' => MenuItemDietaryType::Vegetarian,
        ]);

        $regular = self::variant($item, 'Regular', 24_900, ['default' => true, 'order' => 0]);
        $large = self::variant($item, 'Large', 32_900, ['order' => 1]);

        $spice = self::group($restaurant, 'Spice level', 1, 1, ['order' => 0]);
        $mild = self::option($spice, 'Mild', 0, ['default' => true, 'order' => 0]);
        self::option($spice, 'Medium', 0, ['order' => 1]);
        $hot = self::option($spice, 'Hot', 0, ['order' => 2]);

        $extras = self::group($restaurant, 'Add extras', 0, 2, ['order' => 1]);
        $cheese = self::option($extras, 'Extra Cheese', 4_000, ['order' => 0]);
        $jalapeno = self::option($extras, 'Jalapeños', 2_000, ['order' => 1]);

        self::attach($item, $spice, 0);
        self::attach($item, $extras, 1);

        return [
            'item' => $item->fresh(['variants', 'modifierGroups.options']) ?? $item,
            'regular' => $regular,
            'large' => $large,
            'spice' => $spice,
            'mild' => $mild,
            'hot' => $hot,
            'extras' => $extras,
            'cheese' => $cheese,
            'jalapeno' => $jalapeno,
        ];
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
