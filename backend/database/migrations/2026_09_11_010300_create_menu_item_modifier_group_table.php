<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Which questions get asked about which dish.
 *
 * A pivot rather than a column on the group, because "Spice level" is written
 * once and attached to every curry on the menu. Writing it eleven times would
 * mean eleven rows to keep in step the day the kitchen renames it.
 *
 * `display_order` lives here rather than on the group: the same question may
 * sensibly come first on one dish and last on another.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('menu_item_modifier_group', function (Blueprint $table): void {
            $table->id();

            $table->foreignId('menu_item_id')->constrained()->cascadeOnDelete();
            $table->foreignId('menu_modifier_group_id')->constrained()->cascadeOnDelete();
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();

            $table->unsignedSmallInteger('display_order')->default(0);
            $table->timestamps();

            // One attachment per pair. Asking the same question twice on one
            // dish is a data error, not a feature.
            $table->unique(
                ['menu_item_id', 'menu_modifier_group_id'],
                'menu_item_modifier_group_unique',
            );

            $table->index(['menu_item_id', 'display_order'], 'menu_item_modifier_group_order_index');
        });

        // Both ends must belong to the same restaurant as the pivot row. Two
        // composite keys, and between them a dish of restaurant A cannot be
        // asked a question belonging to restaurant B.
        Schema::table('menu_item_modifier_group', function (Blueprint $table): void {
            $table->foreign(['menu_item_id', 'restaurant_id'], 'menu_item_modifier_group_item_same_restaurant')
                ->references(['id', 'restaurant_id'])
                ->on('menu_items')
                ->cascadeOnDelete();

            $table->foreign(
                ['menu_modifier_group_id', 'restaurant_id'],
                'menu_item_modifier_group_group_same_restaurant',
            )
                ->references(['id', 'restaurant_id'])
                ->on('menu_modifier_groups')
                ->cascadeOnDelete();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('menu_item_modifier_group');
    }
};
