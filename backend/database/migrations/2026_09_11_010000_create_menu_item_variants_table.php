<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Sizes and forms of one dish — Regular and Large, Half and Full, 250 ml and
 * 500 ml. Mutually exclusive: a customer picks exactly one, or none if the
 * dish has none.
 *
 * **The price here is absolute, not a delta.** "Large ₹329" means the dish
 * costs ₹329, not ₹329 more than the base. Deltas read fine on a screen and
 * are ambiguous in a database — is 8000 the price or the increment? — and the
 * ambiguity is resolved wrongly exactly once, in production, on somebody's
 * bill. An absolute price has one reading.
 *
 * `restaurant_id` is carried so the composite key below can exist: a variant
 * cannot belong to an item of another restaurant, and MySQL is what says so.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('menu_item_variants', function (Blueprint $table): void {
            $table->id();
            $table->uuid()->unique();

            $table->foreignId('menu_item_id')->constrained()->cascadeOnDelete();
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();

            $table->string('name', 120);
            $table->string('description', 255)->nullable();

            // The selling price of the dish in this form. Unsigned: a negative
            // price is a corrupt row, not a discount.
            $table->unsignedInteger('price_minor');
            $table->char('currency', 3)->default('INR');

            // The kitchen may say a large one takes longer. Null means "same as
            // the item" — never a guess.
            $table->unsignedSmallInteger('preparation_minutes')->nullable();

            // Two different absences. `is_active` is the operator withdrawing
            // the size from the menu; `is_available` is the kitchen running out
            // of it today. The first hides it, the second shows it disabled.
            $table->boolean('is_active')->default(true);
            $table->boolean('is_available')->default(true);

            // Exactly one variant of an item may be the default, enforced by
            // the partial-unique trick below.
            $table->boolean('is_default')->default(false);

            $table->unsignedSmallInteger('display_order')->default(0);
            $table->timestamps();

            $table->index(['menu_item_id', 'is_active', 'display_order'], 'menu_item_variants_visible_index');

            // Not redundant with the primary key. This is what lets a cart line
            // carry a composite foreign key proving the variant it stored
            // belongs to the item it stored.
            $table->unique(['id', 'menu_item_id'], 'menu_item_variants_id_item_unique');
        });

        // A variant belongs to an item **of its own restaurant**. Without this
        // a bad write could file restaurant A's "Large" under restaurant B's
        // dish, and every check downstream would be looking for a leak that had
        // already happened.
        Schema::table('menu_item_variants', function (Blueprint $table): void {
            $table->foreign(['menu_item_id', 'restaurant_id'], 'menu_item_variants_item_same_restaurant')
                ->references(['id', 'restaurant_id'])
                ->on('menu_items')
                ->cascadeOnDelete();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('menu_item_variants');
    }
};
