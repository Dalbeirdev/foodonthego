<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * One answer to a group's question: Mild, Extra Cheese, Butter Naan.
 *
 * The price is a **delta**, not an absolute — unlike a variant, and for the
 * opposite reason. "Extra cheese ₹40" can only mean forty rupees more; there is
 * no reading of it as the price of the dish. A variant's "₹329" has two
 * readings, which is why that one is absolute.
 *
 * The delta is unsigned. A negative modifier would be a discount, and discounts
 * are a pricing concern with their own audit trail, not something to smuggle in
 * through a menu option. If the business ever wants "no cheese, −₹20", it gets
 * a deliberate design rather than a sign change here.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('menu_modifier_options', function (Blueprint $table): void {
            $table->id();
            $table->uuid()->unique();

            $table->foreignId('menu_modifier_group_id')->constrained()->cascadeOnDelete();
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();

            $table->string('name', 120);
            $table->string('description', 255)->nullable();

            // Zero is the common case and a real one: Mild costs nothing.
            $table->unsignedInteger('price_delta_minor')->default(0);
            $table->char('currency', 3)->default('INR');

            // Withdrawn by the operator, versus out of stock today. As with
            // variants, the first hides it and the second shows it disabled.
            $table->boolean('is_active')->default(true);
            $table->boolean('is_available')->default(true);

            // Preselected when the screen opens. Only ever set on a free
            // option: silently starting a customer at a paid choice is a dark
            // pattern, and the model refuses to serve one.
            $table->boolean('is_default')->default(false);

            $table->unsignedSmallInteger('display_order')->default(0);
            $table->timestamps();

            $table->index(
                ['menu_modifier_group_id', 'is_active', 'display_order'],
                'menu_modifier_options_visible_index',
            );

            $table->unique(['id', 'menu_modifier_group_id'], 'menu_modifier_options_id_group_unique');
        });

        // An option belongs to a group **of its own restaurant**.
        Schema::table('menu_modifier_options', function (Blueprint $table): void {
            $table->foreign(
                ['menu_modifier_group_id', 'restaurant_id'],
                'menu_modifier_options_group_same_restaurant',
            )
                ->references(['id', 'restaurant_id'])
                ->on('menu_modifier_groups')
                ->cascadeOnDelete();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('menu_modifier_options');
    }
};
