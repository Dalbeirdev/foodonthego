<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The sections a restaurant divides its menu into.
 *
 * Two levels, not three: restaurant → category → item. A menu is a list of
 * lists, and every extra level of nesting is a level a customer has to navigate
 * on a phone at the side of a road.
 *
 * The unique key on `(id, restaurant_id)` looks redundant — `id` is already the
 * primary key — and is the point of the next migration. It is what lets
 * `menu_items` carry a composite foreign key, so a restaurant's item
 * *cannot* be attached to another restaurant's category. That rule is worth a
 * redundant index: enforced in the schema it is impossible, enforced in a
 * service it is one forgotten check away.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('menu_categories', function (Blueprint $table): void {
            $table->id();
            $table->uuid()->unique();

            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();

            $table->string('name', 120);
            $table->text('description')->nullable();

            // The operator's own order. Never alphabetical: a restaurant that
            // puts Breakfast first has a reason, and sorting by name would put
            // Beverages there instead.
            $table->unsignedSmallInteger('display_order')->default(0);

            $table->boolean('is_active')->default(true);

            // Time-of-day availability, in the restaurant's own timezone. Both
            // null means "all day", which is what almost every category is.
            // Stored rather than inferred, and left null rather than guessed:
            // a Breakfast category with invented hours would hide a menu at
            // lunchtime for no reason anybody could explain.
            $table->time('available_from')->nullable();
            $table->time('available_until')->nullable();

            $table->timestamps();

            // The customer query: this restaurant's live categories, in order.
            $table->index(['restaurant_id', 'is_active', 'display_order'], 'menu_categories_visible_index');

            // Not redundant. See the class comment.
            $table->unique(['id', 'restaurant_id'], 'menu_categories_id_restaurant_unique');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('menu_categories');
    }
};
