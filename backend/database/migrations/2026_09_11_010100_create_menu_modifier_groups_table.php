<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * A question the kitchen asks about a dish: "Choose your spice level",
 * "Add extras", "Choose a bread".
 *
 * **There is one customization system, not two.** Add-ons are modifier groups —
 * "Add extras · Optional · choose up to 3" with paid options inside it. A
 * separate addon table would be a second model with its own validation, its own
 * pricing path and its own snapshot table, doing the job this one already does.
 * The one thing a separate addon model would buy — per-addon quantities — is
 * not something any real restaurant configuration here needs, and the schema
 * does not preclude adding it later.
 *
 * Groups belong to a **restaurant**, not to an item, so "Spice level" can be
 * written once and attached to eleven dishes. The attachment is the pivot table
 * in the next migration.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('menu_modifier_groups', function (Blueprint $table): void {
            $table->id();
            $table->uuid()->unique();

            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();

            $table->string('name', 120);
            $table->string('description', 255)->nullable();

            // The selection rule, as two numbers rather than a flag. Every case
            // the product needs falls out of them:
            //
            //   exactly one   min=1 max=1
            //   up to three   min=0 max=3
            //   two to four   min=2 max=4
            //
            // `is_required` is derived from min >= 1 and stored anyway, because
            // a query that filters on it is clearer than one that filters on
            // arithmetic, and the model keeps the two honest.
            $table->unsignedTinyInteger('min_select')->default(0);
            $table->unsignedTinyInteger('max_select')->default(1);
            $table->boolean('is_required')->default(false);

            $table->boolean('is_active')->default(true);
            $table->unsignedSmallInteger('display_order')->default(0);
            $table->timestamps();

            $table->index(['restaurant_id', 'is_active'], 'menu_modifier_groups_restaurant_index');

            // For the composite key options carry, so an option cannot belong to
            // a group of another restaurant.
            $table->unique(['id', 'restaurant_id'], 'menu_modifier_groups_id_restaurant_unique');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('menu_modifier_groups');
    }
};
