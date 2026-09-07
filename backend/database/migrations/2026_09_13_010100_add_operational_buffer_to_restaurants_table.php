<?php

declare(strict_types=1);

/**
 * A restaurant's own packing and handover time.
 *
 * Nullable, and null is not zero. Null means "nobody has set this, use the
 * platform default"; zero means "this kitchen hands over the instant the food
 * is done", which is a claim an operator can make but the platform should not
 * make on their behalf. The same distinction the cart's tax rate draws, for the
 * same reason.
 *
 * This is a duration and never a charge. It moves a pickup window later; it
 * touches no total.
 */

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('restaurants', function (Blueprint $table): void {
            $table->unsignedSmallInteger('operational_buffer_minutes')
                ->nullable()
                ->after('default_preparation_minutes');
        });
    }

    public function down(): void
    {
        Schema::table('restaurants', function (Blueprint $table): void {
            $table->dropColumn('operational_buffer_minutes');
        });
    }
};
