<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Cuisines, facilities and opening hours.
 *
 * Three tables rather than three JSON columns on `restaurants`, because Module
 * 08 filters on all three and a JSON column that has to be filtered is a table
 * that has not been written yet. They are loaded eagerly in one query each, so
 * the cost of normalising them is two extra round trips per discovery request,
 * not one per restaurant.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('restaurant_cuisines', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();

            // The operator's own declared cuisine, stored as written. Never
            // inferred from the restaurant's name: "Punjab Sweet House" is a
            // guess, and a vegetarian traveller acting on a guess is a
            // complaint.
            $table->string('cuisine', 60);

            // Display order, so "North Indian, Chinese" is not silently
            // reordered into "Chinese, North Indian" by a query planner.
            $table->unsignedTinyInteger('position')->default(0);

            $table->unique(['restaurant_id', 'cuisine']);
            $table->index('cuisine');
        });

        Schema::create('restaurant_facilities', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();

            // Parking, Restroom, Seating, Takeaway. A claim the operator makes
            // and the platform can be held to, so it is stored and never
            // assumed from anything else.
            $table->string('facility', 60);
            $table->unsignedTinyInteger('position')->default(0);

            $table->unique(['restaurant_id', 'facility']);
            $table->index('facility');
        });

        Schema::create('restaurant_opening_hours', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();

            // 0 = Monday .. 6 = Sunday, matching Carbon's ISO day-of-week minus
            // one. Written down here because "day 0" is a coin flip otherwise.
            $table->unsignedTinyInteger('day_of_week');

            // Local wall-clock times in the restaurant's own timezone. A row
            // whose `closes_at` is not after `opens_at` is an overnight window
            // — 18:00 to 02:00 — and is handled as one, rather than treated as
            // a data error and silently dropped.
            $table->time('opens_at');
            $table->time('closes_at');

            // Several rows per day are allowed, for a kitchen that shuts
            // between lunch and dinner. Hence no unique key on the day alone.
            $table->index(['restaurant_id', 'day_of_week']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('restaurant_opening_hours');
        Schema::dropIfExists('restaurant_facilities');
        Schema::dropIfExists('restaurant_cuisines');
    }
};
