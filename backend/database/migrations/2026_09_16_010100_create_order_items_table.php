<?php

declare(strict_types=1);

/**
 * The dishes, as they were, at the price they were.
 *
 * These columns look almost exactly like `cart_items`, and one difference
 * matters more than all the similarities: **an order line does not cascade from
 * the menu.** In the cart, deleting a menu item takes its lines with it, which
 * is right — an unbuyable dish should not sit in a basket. Here it would delete
 * evidence of a sale. `menu_item_id` is therefore nullable and nulled on
 * delete, and the snapshot columns beside it carry the truth on their own.
 *
 * That is why the snapshots are not a convenience. A year from now the dish may
 * be renamed, repriced, or gone, and this row must still render the receipt the
 * customer agreed to. Nothing here is ever resolved back through a foreign key
 * to find out what something was called or what it cost.
 */

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('order_items', function (Blueprint $table): void {
            $table->id();
            $table->uuid()->unique();

            $table->foreignId('order_id')->constrained()->cascadeOnDelete();

            // Carried so the composite key below can exist: a line cannot hold a
            // dish from a restaurant other than its order's.
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();

            // Provenance, not authority. Null once the menu row is gone; the
            // snapshots below still say what was sold.
            $table->foreignId('menu_item_id')->nullable()->constrained()->nullOnDelete();
            $table->unsignedBigInteger('menu_item_variant_id')->nullable();

            $table->string('item_name_snapshot', 180);
            $table->string('variant_name_snapshot', 120)->nullable();

            $table->unsignedInteger('unit_price_minor');
            $table->unsignedInteger('line_total_minor');
            $table->char('currency', 3)->default('INR');

            $table->unsignedSmallInteger('quantity');

            $table->string('special_instructions', 500)->nullable();

            $table->unsignedSmallInteger('display_order')->default(0);

            $table->timestamps();

            $table->index(['order_id', 'display_order'], 'order_items_order_index');
            $table->unique(['id', 'order_id'], 'order_items_id_order_unique');

            // The line's restaurant is its order's restaurant.
            $table->foreign(['order_id', 'restaurant_id'], 'order_items_order_same_restaurant')
                ->references(['id', 'restaurant_id'])
                ->on('orders')
                ->cascadeOnDelete();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('order_items');
    }
};
