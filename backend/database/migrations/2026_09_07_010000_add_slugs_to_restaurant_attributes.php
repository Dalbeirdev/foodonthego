<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * A stable identifier for every cuisine and facility.
 *
 * Module 07 stored these as the operator wrote them — "North Indian",
 * "Parking" — which is right for display and wrong for filtering. A filter that
 * travels as a display label breaks the first time the label is corrected, and
 * cannot survive translation at all: `?cuisines=North%20Indian` is a query in
 * English about a value somebody may later render in Hindi.
 *
 * The slug is a **stored generated column**, not a second field somebody has to
 * remember to set. It is derived from the label by the database itself, so the
 * two cannot drift — the same reasoning as Module 06's one-selected-route
 * invariant, applied to a much smaller problem.
 *
 * `[^a-zA-Z0-9]+` collapses to a single underscore, so "Vegetarian & Vegan
 * Options" is `vegetarian_vegan_options` rather than something with an ampersand
 * in a query string.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('restaurant_cuisines', function (Blueprint $table): void {
            $table->string('slug', 60)
                ->storedAs("LOWER(REGEXP_REPLACE(TRIM(cuisine), '[^a-zA-Z0-9]+', '_'))")
                ->after('cuisine');
        });

        Schema::table('restaurant_facilities', function (Blueprint $table): void {
            $table->string('slug', 60)
                ->storedAs("LOWER(REGEXP_REPLACE(TRIM(facility), '[^a-zA-Z0-9]+', '_'))")
                ->after('facility');
        });

        // Indexed because every cuisine and facility filter is a lookup by slug
        // across the whole table, and the corridor query has already narrowed
        // the restaurants — this narrows their attributes.
        Schema::table('restaurant_cuisines', function (Blueprint $table): void {
            $table->index(['slug', 'restaurant_id'], 'restaurant_cuisines_slug_index');
        });

        Schema::table('restaurant_facilities', function (Blueprint $table): void {
            $table->index(['slug', 'restaurant_id'], 'restaurant_facilities_slug_index');
        });

        // A name index for search. Not full-text: at pilot scale a prefix and
        // substring match over a few thousand rows is answered in single-digit
        // milliseconds, and MySQL full-text brings stemming, stopwords and a
        // minimum word length that would quietly change what "Cafe" matches.
        // The decision and its reversal condition are documented in
        // docs/23-restaurant-search-filters-ranking.md.
        Schema::table('restaurants', function (Blueprint $table): void {
            $table->index('name', 'restaurants_name_index');
        });

        // Backfill is unnecessary — a stored generated column is computed for
        // every existing row when it is added — but the count is worth asserting
        // once here rather than discovering a silent empty column later.
        $missing = DB::table('restaurant_cuisines')->where('slug', '')->count();

        if ($missing > 0) {
            throw new RuntimeException("{$missing} cuisine rows produced an empty slug.");
        }
    }

    public function down(): void
    {
        Schema::table('restaurants', function (Blueprint $table): void {
            $table->dropIndex('restaurants_name_index');
        });

        Schema::table('restaurant_facilities', function (Blueprint $table): void {
            $table->dropIndex('restaurant_facilities_slug_index');
            $table->dropColumn('slug');
        });

        Schema::table('restaurant_cuisines', function (Blueprint $table): void {
            $table->dropIndex('restaurant_cuisines_slug_index');
            $table->dropColumn('slug');
        });
    }
};
