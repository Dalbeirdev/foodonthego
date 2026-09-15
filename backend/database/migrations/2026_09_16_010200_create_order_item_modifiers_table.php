<?php

declare(strict_types=1);

/**
 * The extras, as they were, at the price they were.
 *
 * Same rule as the lines above: provenance may be nulled, the snapshot may not.
 * "Extra cheese, ₹40" has to still read that way after somebody renames the
 * option or changes what it costs.
 */

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('order_item_modifiers', function (Blueprint $table): void {
            $table->id();

            $table->foreignId('order_item_id')->constrained()->cascadeOnDelete();

            $table->foreignId('menu_modifier_group_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignId('menu_modifier_option_id')->nullable()->constrained()->nullOnDelete();

            $table->string('group_name_snapshot', 120);
            $table->string('option_name_snapshot', 120);

            $table->unsignedInteger('price_delta_minor')->default(0);
            $table->char('currency', 3)->default('INR');

            $table->unsignedSmallInteger('display_order')->default(0);
            $table->timestamps();

            $table->index('order_item_id', 'order_item_modifiers_line_index');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('order_item_modifiers');
    }
};
