<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The routes calculated for a trip, and the fingerprint that says which
 * endpoints they belong to.
 *
 * A separate table rather than columns on `trips`, because a provider returns
 * several alternatives and the customer picks one. Flattening the chosen route
 * onto the trip would make "show me the alternatives again" a second provider
 * call — which is a bill, not a query.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('trip_routes', function (Blueprint $table): void {
            $table->id();
            $table->uuid()->unique();

            // Cascade: a route is worthless without its trip, and Module 05
            // discards trips rather than deleting them, so this only fires on a
            // real erasure.
            $table->foreignId('trip_id')->constrained()->cascadeOnDelete();

            // Which provider produced this. Stored rather than assumed, so a row
            // can always be traced to the service that returned it — and so a
            // row from a non-production provider is identifiable for ever.
            $table->string('provider', 32);

            // The provider's own ordering. Kept because "the first route" is a
            // provider concept with meaning (it is the one it recommends), and
            // because it makes a calculation idempotent per trip.
            $table->unsignedTinyInteger('provider_route_index');

            // "via NH 48" — the provider's own words, shown as-is or not at all.
            $table->string('summary', 180)->nullable();

            // Metres and seconds. Never a formatted string: "278 km" cannot be
            // summed, compared, or converted for a customer who wants miles.
            $table->unsignedInteger('distance_meters');
            $table->unsignedInteger('duration_seconds');

            // Null when the provider was not asked for, or could not give, a
            // traffic-aware figure. Null is the honest answer; copying the base
            // duration here would invent a traffic reading of exactly zero.
            $table->unsignedInteger('traffic_duration_seconds')->nullable();

            // The provider's encoded polyline. Storing the decoded coordinates
            // would be tens of thousands of rows per route for something every
            // consumer re-encodes anyway; Module 07 decodes this at the service
            // layer when it needs a corridor.
            $table->mediumText('encoded_polyline');

            // The route's own bounding box, so a corridor search can be narrowed
            // before any geometry is decoded at all.
            $table->decimal('bounds_north', 10, 7);
            $table->decimal('bounds_south', 10, 7);
            $table->decimal('bounds_east', 10, 7);
            $table->decimal('bounds_west', 10, 7);

            $table->boolean('is_recommended')->default(false);
            $table->boolean('is_selected')->default(false);

            // Which endpoints this was calculated for.
            //
            // Deliberately stored here and *derived* on the trip, rather than
            // stored on both. A second copy on `trips` would be a second thing to
            // keep in step with the eight endpoint columns, and the failure mode
            // of getting that wrong is a route that looks current and is not.
            // Computing the trip's side from its own columns cannot drift from
            // them.
            $table->char('endpoints_fingerprint', 64);

            // When the provider answered. Traffic-aware figures decay; this is
            // what a later module will use to decide a recalculation is due.
            $table->timestamp('calculated_at');

            $table->timestamps();

            // One row per provider alternative per trip. A retried calculation
            // upserts onto this rather than appending, which is what stops ten
            // taps producing thirty rows.
            $table->unique(['trip_id', 'provider_route_index']);

            $table->index(['trip_id', 'is_selected']);
        });

        // The one-selected-route invariant, in the database rather than in a
        // service somebody can forget to call.
        //
        // A virtual column that is the trip id when the row is selected and NULL
        // otherwise, with a unique index over it: MySQL does not compare NULLs,
        // so any number of unselected rows coexist and a second selected row for
        // the same trip is refused by the engine.
        Schema::table('trip_routes', function (Blueprint $table): void {
            $table->unsignedBigInteger('selected_trip_id')
                ->nullable()
                ->virtualAs('CASE WHEN is_selected = 1 THEN trip_id ELSE NULL END');

            $table->unique('selected_trip_id', 'trip_routes_one_selected_per_trip');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('trip_routes');
    }
};
