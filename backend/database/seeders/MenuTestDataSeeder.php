<?php

declare(strict_types=1);

namespace Database\Seeders;

use App\Enums\MenuItemDietaryType;
use App\Enums\MenuItemStockStatus;
use App\Models\MenuCategory;
use App\Models\MenuItem;
use App\Models\MenuItemVariant;
use App\Models\MenuModifierGroup;
use App\Models\MenuModifierOption;
use App\Models\Restaurant;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * A real menu for the controlled test restaurants.
 *
 * Every fixture here exists because some rule needs a state somebody can look
 * at: a sold-out dish, a withdrawn dish, a withdrawn category, a dish with no
 * description, no image, no prep time and no dietary type, a free item, a
 * five-figure price, a name long enough to wrap, and a section that is only
 * served in the morning.
 *
 * Names carry the [TEST] marker their restaurants do. A development seed that
 * cannot be told from production content is a seed that eventually reaches a
 * customer.
 */
final class MenuTestDataSeeder extends Seeder
{
    public function run(): void
    {
        if (app()->environment('production')) {
            throw new \RuntimeException(
                'Test menus must never be seeded into production.',
            );
        }

        $this->clearPrevious();

        $spice = $this->restaurant('[TEST] Highway Spice Kitchen');

        if ($spice === null) {
            // The discovery fixtures have not been seeded. Nothing to attach a
            // menu to, and inventing a restaurant here would put a partner in
            // the database that no other seeder knows about.
            $this->command?->warn(
                'Discovery fixtures are missing — run DiscoveryTestRestaurantSeeder first.',
            );

            return;
        }

        // --- Starters ---------------------------------------------------------
        $starters = $this->category($spice, 'Starters', 0);

        $this->item($starters, 'Paneer Tikka', 24_900, [
            'description' => 'Cottage cheese marinated in yoghurt and spices, '
                .'cooked in the tandoor.',
            'preparation_minutes' => 15,
            'dietary' => MenuItemDietaryType::Vegetarian,
            'spice_level' => 2,
            'image' => self::placeholder('paneer-tikka'),
            'order' => 0,
        ]);

        $this->item($starters, 'Chicken Seekh Kebab', 32_900, [
            'description' => 'Minced chicken with green chilli and coriander.',
            'preparation_minutes' => 20,
            'dietary' => MenuItemDietaryType::NonVegetarian,
            'spice_level' => 3,
            'image' => self::placeholder('seekh-kebab'),
            'order' => 1,
        ]);

        // Sold out, and deliberately still visible. A traveller deciding where
        // to stop wants to know the restaurant makes it at all.
        $this->item($starters, 'Tandoori Mushroom', 27_900, [
            'description' => 'Button mushrooms in a yoghurt and ajwain marinade.',
            'preparation_minutes' => 15,
            'dietary' => MenuItemDietaryType::Vegetarian,
            'stock' => MenuItemStockStatus::SoldOut,
            'order' => 2,
        ]);

        // Everything optional, missing. No description, no image, no prep time,
        // no dietary type. Four sections of the card must omit themselves.
        $this->item($starters, 'Papad', 4_900, ['order' => 3]);

        // Withdrawn from the menu. Must never appear, by list or by id.
        $this->item($starters, 'Discontinued Kebab', 19_900, [
            'description' => 'Taken off the menu.',
            'active' => false,
            'order' => 4,
        ]);

        // --- Main Course ------------------------------------------------------
        $mains = $this->category($spice, 'Main Course', 1);

        $this->item($mains, 'Dal Makhani', 29_900, [
            'description' => 'Black lentils simmered overnight with butter and cream.',
            'preparation_minutes' => 25,
            'dietary' => MenuItemDietaryType::Vegetarian,
            'image' => self::placeholder('dal-makhani'),
            'order' => 0,
        ]);

        $this->item($mains, 'Paneer Butter Masala', 34_900, [
            'description' => 'Cottage cheese in a tomato and cashew gravy.',
            'preparation_minutes' => 20,
            'dietary' => MenuItemDietaryType::Vegetarian,
            'image' => self::placeholder('paneer-butter-masala'),
            'order' => 1,
        ]);

        // A name long enough to wrap on a 320 dp screen, and legitimate.
        $this->item(
            $mains,
            'Paneer Tikka Masala with Roasted Capsicum & House Spice Blend',
            39_900,
            [
                'description' => 'Tandoori paneer folded into a slow-cooked gravy '
                    .'with roasted capsicum, finished with the house blend of '
                    .'twelve spices and a spoon of cream.',
                'preparation_minutes' => 30,
                'dietary' => MenuItemDietaryType::Vegetarian,
                'spice_level' => 2,
                'order' => 2,
            ],
        );

        $this->item($mains, 'Vegan Chana Masala', 26_900, [
            'description' => 'Chickpeas in an onion and tomato masala. No dairy.',
            'preparation_minutes' => 20,
            'dietary' => MenuItemDietaryType::Vegan,
            'order' => 3,
        ]);

        // --- Breads -----------------------------------------------------------
        $breads = $this->category($spice, 'Breads', 2);

        $this->item($breads, 'Tandoori Roti', 3_900, [
            'dietary' => MenuItemDietaryType::Vegetarian,
            'preparation_minutes' => 5,
            'order' => 0,
        ]);

        $this->item($breads, 'Butter Naan', 6_900, [
            'dietary' => MenuItemDietaryType::Vegetarian,
            'preparation_minutes' => 8,
            'order' => 1,
        ]);

        $this->item($breads, 'Egg Paratha', 11_900, [
            'description' => 'Stuffed paratha with a folded egg.',
            'dietary' => MenuItemDietaryType::Egg,
            'preparation_minutes' => 12,
            'order' => 2,
        ]);

        // --- Beverages --------------------------------------------------------
        $beverages = $this->category($spice, 'Beverages', 3);

        $this->item($beverages, 'Masala Chai', 4_900, [
            'description' => 'Brewed with ginger, cardamom and clove.',
            'preparation_minutes' => 5,
            'dietary' => MenuItemDietaryType::Vegetarian,
            'image' => self::placeholder('masala-chai'),
            'order' => 0,
        ]);

        // A free item. Legitimate, and a formatter that assumes a price is
        // non-zero would print nothing at all.
        $this->item($beverages, 'Table Water', 0, [
            'description' => 'Filtered, on request.',
            'dietary' => MenuItemDietaryType::Vegan,
            'order' => 1,
        ]);

        // Five figures. The grouping separator has to be right somewhere.
        $this->item($beverages, 'Celebration Hamper', 1_299_900, [
            'description' => 'Sweets and dry fruit, boxed. Order a day ahead.',
            'preparation_minutes' => 60,
            'dietary' => MenuItemDietaryType::Vegetarian,
            'order' => 2,
        ]);

        // --- Breakfast, served in the morning only ----------------------------
        //
        // A time-limited section. It exists so the rule is exercised rather
        // than only unit-tested — at four in the afternoon it is simply absent.
        $breakfast = $this->category($spice, 'Breakfast', 4, [
            'from' => '06:00:00',
            'until' => '11:00:00',
        ]);

        $this->item($breakfast, 'Aloo Paratha', 12_900, [
            'description' => 'Two, with butter and curd.',
            'preparation_minutes' => 15,
            'dietary' => MenuItemDietaryType::Vegetarian,
            'order' => 0,
        ]);

        // --- A withdrawn category ---------------------------------------------
        //
        // Off the menu, with a live item inside it. Neither may appear — and
        // the item must not leak through the item endpoint either, which is
        // what makes this fixture worth having.
        $desserts = $this->category($spice, 'Desserts', 5, ['active' => false]);

        $this->item($desserts, 'Gulab Jamun', 14_900, [
            'description' => 'Two pieces, warm.',
            'dietary' => MenuItemDietaryType::Vegetarian,
            'order' => 0,
        ]);

        // --- A second restaurant, for the cross-restaurant test ----------------
        $bites = $this->restaurant('[TEST] Rajasthan Highway Bites');

        if ($bites !== null) {
            $snacks = $this->category($bites, 'Snacks', 0);

            $this->item($snacks, 'Pyaaz Kachori', 8_900, [
                'description' => 'Flaky pastry with a spiced onion filling.',
                'preparation_minutes' => 10,
                'dietary' => MenuItemDietaryType::Vegetarian,
                'order' => 0,
            ]);
        }

        // --- A restaurant with no menu ----------------------------------------
        //
        // [TEST] Bare Bones Stop gets nothing at all, so the empty-menu state is
        // a fixture rather than a branch nobody exercises.

        $this->seedCustomization($spice);
    }

    /**
     * Sizes and questions, on the dishes that have them (Module 11).
     *
     * Deliberately uneven: Paneer Tikka is fully configurable, Dal Makhani has
     * questions but no sizes, and Papad has neither. A screen that only ever
     * meets the rich case is a screen whose empty branches nobody has looked
     * at.
     */
    private function seedCustomization(Restaurant $spice): void
    {
        $paneer = $this->itemNamed($spice, 'Paneer Tikka');
        $dal = $this->itemNamed($spice, 'Dal Makhani');
        $chai = $this->itemNamed($spice, 'Masala Chai');
        $mushroom = $this->itemNamed($spice, 'Tandoori Mushroom');

        if ($paneer === null) {
            return;
        }

        // --- Sizes ------------------------------------------------------------
        //
        // Absolute prices: Large *is* ₹329, not ₹329 more. Regular is the
        // configured default, so the screen opens on a price somebody chose to
        // show rather than on the first database row.
        $this->variant($paneer, 'Regular', 24_900, ['default' => true, 'order' => 0]);
        $this->variant($paneer, 'Large', 32_900, ['preparation_minutes' => 20, 'order' => 1]);

        // Sold out today, and still on the screen. A customer who came for the
        // family size learns why rather than wondering.
        $this->variant($paneer, 'Family (serves 4)', 54_900, [
            'available' => false,
            'preparation_minutes' => 30,
            'order' => 2,
        ]);

        // Chai has sizes and **no default**, so choosing one is required. This
        // is the fixture behind the "Choose a size to continue" refusal.
        if ($chai !== null) {
            $this->variant($chai, '150 ml', 4_900, ['order' => 0]);
            $this->variant($chai, '250 ml', 6_900, ['order' => 1]);
        }

        // --- Questions --------------------------------------------------------
        //
        // Written once against the restaurant and attached to several dishes,
        // which is the whole reason groups are not columns on an item.
        $spiceLevel = $this->group($spice, 'Spice level', 1, 1, [
            'description' => 'How hot would you like it?',
            'order' => 0,
        ]);

        $this->option($spiceLevel, 'Mild', 0, ['default' => true, 'order' => 0]);
        $this->option($spiceLevel, 'Medium', 0, ['order' => 1]);
        $this->option($spiceLevel, 'Hot', 0, ['order' => 2]);

        // Optional, multi-select, and the group add-ons live in. There is no
        // separate addon model — see 26-menu-item-customization.md.
        $extras = $this->group($spice, 'Add extras', 0, 2, [
            'description' => 'Choose up to 2.',
            'order' => 1,
        ]);

        $this->option($extras, 'Extra Paneer', 6_000, ['order' => 0]);
        $this->option($extras, 'Extra Cheese', 4_000, ['order' => 1]);
        $this->option($extras, 'Jalapeños', 2_000, ['order' => 2]);

        // Sold out today. Shown disabled, and refused if a tampered request
        // names it anyway.
        $this->option($extras, 'Extra Cashew', 8_000, ['available' => false, 'order' => 3]);

        // A two-to-four group, so the "choose at least 2" message is a fixture
        // rather than a branch only a unit test has seen.
        $sides = $this->group($spice, 'Pick your sides', 2, 4, [
            'description' => 'Choose 2 to 4.',
            'order' => 2,
        ]);

        $this->option($sides, 'Mint chutney', 0, ['order' => 0]);
        $this->option($sides, 'Onion salad', 0, ['order' => 1]);
        $this->option($sides, 'Green chilli', 0, ['order' => 2]);
        $this->option($sides, 'Lemon wedge', 0, ['order' => 3]);

        $this->attach($paneer, $spiceLevel, 0);
        $this->attach($paneer, $extras, 1);

        // Dal Makhani: questions, no sizes. The screen must not invent a
        // "Regular" for it.
        if ($dal !== null) {
            $this->attach($dal, $spiceLevel, 0);
        }

        // Tandoori Mushroom is sold out at the item level and still carries a
        // question, so the sold-out refusal is tested on a configurable dish
        // rather than only on a plain one.
        if ($mushroom !== null) {
            $this->attach($mushroom, $spiceLevel, 0);
        }
    }

    private function itemNamed(Restaurant $restaurant, string $name): ?MenuItem
    {
        return MenuItem::query()
            ->where('restaurant_id', $restaurant->id)
            ->where('name', $name)
            ->first();
    }

    /** @param array<string, mixed> $options */
    private function variant(
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
            'currency' => 'INR',
            'preparation_minutes' => $options['preparation_minutes'] ?? null,
            'is_active' => $options['active'] ?? true,
            'is_available' => $options['available'] ?? true,
            'is_default' => $options['default'] ?? false,
            'display_order' => $options['order'] ?? 0,
        ])->save();

        return $variant;
    }

    /** @param array<string, mixed> $options */
    private function group(
        Restaurant $restaurant,
        string $name,
        int $min,
        int $max,
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

    /** @param array<string, mixed> $options */
    private function option(
        MenuModifierGroup $group,
        string $name,
        int $deltaMinor,
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
            'currency' => 'INR',
            'is_active' => $options['active'] ?? true,
            'is_available' => $options['available'] ?? true,
            'is_default' => $options['default'] ?? false,
            'display_order' => $options['order'] ?? 0,
        ])->save();

        return $option;
    }

    private function attach(MenuItem $item, MenuModifierGroup $group, int $order): void
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

    /** Removes anything this seeder created before, so re-running is safe. */
    private function clearPrevious(): void
    {
        $ids = Restaurant::query()
            ->where('name', 'like', '[TEST]%')
            ->pluck('id');

        if ($ids->isEmpty()) {
            return;
        }

        // Order matters throughout: every one of these tables is held to the
        // next by a composite foreign key, and deleting upwards fails.
        DB::table('menu_item_modifier_group')->whereIn('restaurant_id', $ids)->delete();
        DB::table('menu_modifier_options')->whereIn('restaurant_id', $ids)->delete();
        DB::table('menu_modifier_groups')->whereIn('restaurant_id', $ids)->delete();
        DB::table('menu_item_variants')->whereIn('restaurant_id', $ids)->delete();
        DB::table('menu_items')->whereIn('restaurant_id', $ids)->delete();
        DB::table('menu_categories')->whereIn('restaurant_id', $ids)->delete();
    }

    private function restaurant(string $name): ?Restaurant
    {
        return Restaurant::query()->where('name', $name)->first();
    }

    /** @param array<string, mixed> $options */
    private function category(
        Restaurant $restaurant,
        string $name,
        int $order,
        array $options = [],
    ): MenuCategory {
        $category = new MenuCategory;

        $category->forceFill([
            'uuid' => (string) Str::uuid(),
            'restaurant_id' => $restaurant->id,
            'name' => $name,
            'display_order' => $order,
            'is_active' => $options['active'] ?? true,
            'available_from' => $options['from'] ?? null,
            'available_until' => $options['until'] ?? null,
        ])->save();

        return $category;
    }

    /** @param array<string, mixed> $options */
    private function item(
        MenuCategory $category,
        string $name,
        int $priceMinor,
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
            'currency' => 'INR',
            'image_url' => $options['image'] ?? null,
            'thumbnail_url' => $options['image'] ?? null,
            'preparation_minutes' => $options['preparation_minutes'] ?? null,
            'dietary_type' => ($options['dietary'] ?? null)?->value,
            'spice_level' => $options['spice_level'] ?? null,
            'is_active' => $options['active'] ?? true,
            'stock_status' => ($options['stock'] ?? MenuItemStockStatus::InStock)->value,
            'display_order' => $options['order'] ?? 0,
        ])->save();

        return $item;
    }

    /**
     * A one-pixel PNG as a data URI.
     *
     * The same reasoning as the restaurant fixtures: a stock photograph shown
     * under a dish's name is a claim about food nobody has cooked, a link to
     * somebody's real site borrows their bandwidth, and a broken URL would make
     * every fixture exercise the failure path instead of the normal one.
     */
    private static function placeholder(string $suffix): string
    {
        return 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8'
            .'z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='
            .'#'.$suffix;
    }
}
