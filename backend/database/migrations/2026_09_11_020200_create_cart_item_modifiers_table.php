<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Which options a customer chose on one cart line, and what each cost.
 *
 * Snapshots for the same reason the line has them: "Extra Cheese" may be
 * renamed or repriced, and a cart that redrew itself from the live rows would
 * quietly rewrite what the customer chose.
 *
 * `price_delta_minor` here is the figure that went into the line's unit price.
 * It is stored per row rather than summed into the line alone so a later screen
 * can show the customer the breakdown they were quoted, line by line, rather
 * than a total they have to take on trust.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('cart_item_modifiers', function (Blueprint $table): void {
            $table->id();

            $table->foreignId('cart_item_id')->constrained()->cascadeOnDelete();
            $table->foreignId('menu_modifier_group_id')->constrained()->cascadeOnDelete();
            $table->foreignId('menu_modifier_option_id')->constrained()->cascadeOnDelete();

            $table->string('group_name_snapshot', 120);
            $table->string('option_name_snapshot', 120);

            $table->unsignedInteger('price_delta_minor')->default(0);
            $table->char('currency', 3)->default('INR');

            $table->unsignedSmallInteger('display_order')->default(0);
            $table->timestamps();

            // One option can be chosen once on a line. Choosing "Extra Cheese"
            // twice is a client bug, and a unique index is a cheaper place to
            // discover it than a doubled bill.
            $table->unique(
                ['cart_item_id', 'menu_modifier_option_id'],
                'cart_item_modifiers_option_unique',
            );

            $table->index('cart_item_id', 'cart_item_modifiers_line_index');
        });

        // The option belongs to the group it is recorded under. Without this a
        // line could claim "Spice level: Extra Cheese", and the breakdown shown
        // to the customer would be nonsense that validated cleanly.
        Schema::table('cart_item_modifiers', function (Blueprint $table): void {
            $table->foreign(
                ['menu_modifier_option_id', 'menu_modifier_group_id'],
                'cart_item_modifiers_option_same_group',
            )
                ->references(['id', 'menu_modifier_group_id'])
                ->on('menu_modifier_options')
                ->cascadeOnDelete();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('cart_item_modifiers');
    }
};
