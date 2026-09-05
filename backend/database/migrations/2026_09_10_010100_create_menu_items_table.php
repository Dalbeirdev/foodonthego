<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The things a customer can order.
 *
 * Three decisions worth stating.
 *
 * **Money is an integer.** `base_price_minor` is paise, not rupees, and not a
 * float. A binary floating-point number cannot represent 0.10 exactly, and a
 * menu price that has been through one is a bill that does not add up. The
 * currency is stored beside it rather than assumed, because "the amount is 24900"
 * is meaningless without it.
 *
 * **`restaurant_id` is denormalised.** It is reachable through the category, and
 * it is stored here anyway — because it is half of the composite foreign key
 * below, which is what makes a cross-restaurant item impossible rather than
 * merely unlikely.
 *
 * **Active and in-stock are different columns.** An item withdrawn from the
 * menu and an item that has run out today are different facts with different
 * lifetimes: the first is invisible, the second is visible and marked sold out,
 * because a customer deciding where to stop wants to know the dish exists.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('menu_items', function (Blueprint $table): void {
            $table->id();
            $table->uuid()->unique();

            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('menu_category_id')->constrained()->cascadeOnDelete();

            $table->string('name', 180);
            $table->text('description')->nullable();

            // Paise. `unsigned` so a negative price cannot be stored at all —
            // the formatter never has to defend against one because the column
            // will not hold it.
            $table->unsignedInteger('base_price_minor');
            $table->char('currency', 3)->default('INR');

            // Delivery URLs, like restaurant media. Nothing in the customer API
            // composes a storage path.
            $table->string('image_url', 2048)->nullable();
            $table->string('thumbnail_url', 2048)->nullable();

            // Item-level metadata, and only that. It is **not** a pickup ETA:
            // that belongs to a later module and involves the route, the
            // kitchen's workload and the whole order. Null where the operator
            // has not said, and never filled in from the restaurant's default,
            // which would turn a restaurant-wide guess into a claim about a
            // dish.
            $table->unsignedSmallInteger('preparation_minutes')->nullable();

            // Structured, or absent. Never inferred from a name: "Paneer" is
            // not a promise, and a customer who avoids egg cannot act on our
            // guess.
            $table->string('dietary_type', 20)->nullable();
            $table->unsignedTinyInteger('spice_level')->nullable();

            $table->boolean('is_active')->default(true);
            $table->string('stock_status', 20)->default('IN_STOCK');

            $table->unsignedSmallInteger('display_order')->default(0);

            $table->timestamps();

            // The customer query: one category's live items, in order.
            $table->index(['menu_category_id', 'is_active', 'display_order'], 'menu_items_visible_index');

            // Menu search, and the restaurant-wide item lookup behind the
            // item-preview endpoint.
            $table->index(['restaurant_id', 'is_active'], 'menu_items_restaurant_index');
            $table->index('name', 'menu_items_name_index');

            // The rule this table exists to make unbreakable: an item's
            // category must belong to the item's restaurant. A plain foreign
            // key on `menu_category_id` alone would happily let Restaurant A's
            // item point at Restaurant B's category.
            $table->foreign(['menu_category_id', 'restaurant_id'], 'menu_items_category_same_restaurant')
                ->references(['id', 'restaurant_id'])
                ->on('menu_categories')
                ->cascadeOnDelete();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('menu_items');
    }
};
