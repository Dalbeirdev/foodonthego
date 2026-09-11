<?php

declare(strict_types=1);

use App\Enums\LocationSourceType;
use App\Enums\RouteStatus;
use App\Enums\TripStatus;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * A trip: where a customer is setting off from, where they are going, and where
 * those two places came from.
 *
 * Three decisions worth reading before the columns.
 *
 * **Each endpoint is a snapshot, not a foreign key.** A trip records the place as
 * it was when the trip was created. Holding only `origin_saved_address_id` would
 * mean that editing a saved address silently rewrote trips already created from
 * it, and Module 04 deletes addresses for real, so the key would either orphan
 * the trip or block the delete. The id is kept alongside as provenance, with
 * `ON DELETE SET NULL`: losing the link loses nothing.
 *
 * **Coordinates are NOT NULL.** This is the opposite of `customer_addresses`,
 * deliberately. A saved address is a note to oneself and may never be geocoded;
 * a trip endpoint is an input to route calculation, and one without a position is
 * a trip Module 06 cannot do anything with. Requiring them here is what forces
 * the app to resolve a saved address properly instead of quietly filling in
 * something plausible.
 *
 * **Status and route status are separate columns.** `status` is what the customer
 * means; `route_status` is how far a technical job has got. Conflating them would
 * make "the customer's current plan" and "waiting for a route" mutually
 * exclusive, which is the state every trip is in the moment Module 05 finishes.
 * Module 05 only ever writes NOT_CALCULATED, and there are no distance, duration,
 * polyline or ETA columns at all — a nullable one would be an invitation to fill
 * it in with an estimate.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('trips', function (Blueprint $table): void {
            $table->id();
            $table->uuid()->unique();

            // RESTRICT, matching customer_addresses: a customer with trips is
            // history, and erasing them is Module 17's job with an audit entry
            // rather than a side effect of a DELETE somewhere else.
            $table->foreignId('customer_id')->constrained('users')->restrictOnDelete();

            $table->enum('status', TripStatus::values())->default(TripStatus::RoutePending->value);
            $table->enum('route_status', RouteStatus::values())->default(RouteStatus::NotCalculated->value);

            foreach (['origin', 'destination'] as $end) {
                $table->enum("{$end}_source_type", LocationSourceType::values());

                // Provenance only. The snapshot below is what the trip means.
                $table->foreignId("{$end}_saved_address_id")
                    ->nullable()
                    ->constrained('customer_addresses')
                    ->nullOnDelete();

                // The provider's identifier, when the place came from a search.
                $table->string("{$end}_place_id", 255)->nullable();

                $table->string("{$end}_name", 180);
                $table->string("{$end}_formatted_address", 400);

                // Required, and the reason is in the class comment above.
                $table->decimal("{$end}_latitude", 10, 7);
                $table->decimal("{$end}_longitude", 10, 7);

                $table->string("{$end}_city", 120)->nullable();
                $table->string("{$end}_region", 120)->nullable();
                $table->char("{$end}_country_code", 2)->nullable();
                $table->string("{$end}_postal_code", 16)->nullable();
            }

            $table->dateTime('cancelled_at')->nullable();

            $table->timestamps();

            // The list query: this customer's trips, newest first.
            $table->index(['customer_id', 'created_at']);
            // "What is this customer waiting on a route for" — the query Module
            // 06's worker will want, indexed before it is slow rather than after.
            $table->index(['customer_id', 'status', 'route_status']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('trips');
    }
};
