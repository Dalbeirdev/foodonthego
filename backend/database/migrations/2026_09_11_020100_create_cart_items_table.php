<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * One configured dish in a cart.
 *
 * **Prices here are the server's, never the client's.** `unit_price_minor` is
 * what `MenuItemPricingService` calculated at the moment the line was written,
 * from rows it read itself. Nothing in the request body reaches these columns.
 *
 * **Names are snapshots.** A restaurant may rename "Paneer Tikka" to "Tandoori
 * Paneer" tomorrow, and a cart that then displayed the new name would be
 * telling the customer they chose something they did not. The foreign keys stay
 * so the live row is still reachable; the snapshot is what the screen shows.
 *
 * The snapshot is **not** a licence to charge a stale price. Module 12
 * revalidates before an order exists, and this module already refuses a stale
 * price at the moment of adding. The snapshot answers "what did I choose", not
 * "what do I owe".
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('cart_items', function (Blueprint $table): void {
            $table->id();
            $table->uuid()->unique();

            $table->foreignId('cart_id')->constrained()->cascadeOnDelete();

            // Carried so the composite keys below can exist: a line cannot hold
            // a dish from a restaurant other than its cart's.
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();

            $table->foreignId('menu_item_id')->constrained()->cascadeOnDelete();
            // Nullable — a dish with no sizes has no variant — and deliberately
            // without a single-column foreign key of its own. The composite one
            // below is the whole constraint; adding a second key over the same
            // column with a different delete action makes the behaviour depend
            // on which one MySQL happens to apply.
            $table->unsignedBigInteger('menu_item_variant_id')->nullable();

            $table->string('item_name_snapshot', 180);
            $table->string('variant_name_snapshot', 120)->nullable();

            // The configured price of one, and of all of them. Both stored
            // rather than one derived, because a later reader must be able to
            // see the figure that was actually agreed rather than recompute it
            // from a quantity that may since have changed.
            $table->unsignedInteger('unit_price_minor');
            $table->unsignedInteger('line_total_minor');
            $table->char('currency', 3)->default('INR');

            $table->unsignedSmallInteger('quantity');

            $table->string('special_instructions', 500)->nullable();

            // A hash of the canonical configuration — item, variant, the sorted
            // option ids, and the note. Two taps that produce the same
            // configuration produce the same fingerprint, so "add the same
            // thing again" increments a quantity instead of growing a second
            // identical row. Sorting is what makes cheese-then-jalapeño equal
            // jalapeño-then-cheese.
            $table->char('configuration_hash', 64);

            $table->timestamps();

            $table->index(['cart_id', 'id'], 'cart_items_cart_index');

            // One line per distinct configuration in a cart. The service merges
            // rather than duplicating, and this is what makes that true even
            // when two requests race.
            $table->unique(['cart_id', 'configuration_hash'], 'cart_items_configuration_unique');

            $table->unique(['id', 'cart_id'], 'cart_items_id_cart_unique');
        });

        Schema::table('cart_items', function (Blueprint $table): void {
            // The line's restaurant is its cart's restaurant.
            $table->foreign(['cart_id', 'restaurant_id'], 'cart_items_cart_same_restaurant')
                ->references(['id', 'restaurant_id'])
                ->on('carts')
                ->cascadeOnDelete();

            // The dish belongs to that restaurant.
            $table->foreign(['menu_item_id', 'restaurant_id'], 'cart_items_item_same_restaurant')
                ->references(['id', 'restaurant_id'])
                ->on('menu_items')
                ->cascadeOnDelete();

            // And the variant belongs to that dish. Three composite keys, and
            // between them a cart line holding somebody else's "Large" is not a
            // bug that can be written.
            //
            // Cascading rather than nulling: `SET NULL` needs every column in
            // the key nullable and `menu_item_id` is not, and nulling would in
            // any case leave a line claiming a plain dish at the price of a
            // large one. A deleted variant takes the line with it — which is
            // rare, because withdrawing a size is `is_active`, not a delete.
            $table->foreign(['menu_item_variant_id', 'menu_item_id'], 'cart_items_variant_same_item')
                ->references(['id', 'menu_item_id'])
                ->on('menu_item_variants')
                ->cascadeOnDelete();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('cart_items');
    }
};
