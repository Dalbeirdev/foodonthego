<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Lets other tables carry a composite foreign key into `menu_items`.
 *
 * Redundant with the primary key on its own, and not redundant at all in
 * effect: MySQL will only accept a foreign key that references a unique index,
 * so `UNIQUE(id, restaurant_id)` is what makes
 * "this variant belongs to an item **of this restaurant**" expressible as a
 * constraint rather than as a check somebody has to remember to write.
 *
 * `menu_categories` gained the same index in Module 10 for the same reason.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('menu_items', function (Blueprint $table): void {
            $table->unique(['id', 'restaurant_id'], 'menu_items_id_restaurant_unique');
        });
    }

    public function down(): void
    {
        Schema::table('menu_items', function (Blueprint $table): void {
            $table->dropUnique('menu_items_id_restaurant_unique');
        });
    }
};
