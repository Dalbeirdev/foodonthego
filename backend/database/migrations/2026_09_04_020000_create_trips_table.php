<?php

declare(strict_types=1);

use App\Enums\TripStatus;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * A planned journey: where a customer is setting off from, where they are going,
 * and when.
 *
 * The one design decision worth reading before the columns: **each endpoint is a
 * snapshot, not a foreign key.** A journey records the address as it was when the
 * journey was planned. If it held only `origin_address_id`, then editing a saved
 * address would silently rewrite journeys already planned against it, and Module
 * 04 deletes addresses for real, which would either orphan the journey or block
 * the delete. `origin_address_id` is kept alongside the snapshot as provenance
 * only — it goes NULL when the address goes, and nothing about the journey moves.
 *
 * Coordinates repeat Module 04's discipline exactly: nullable, and NULL until
 * something actually geocodes the place. Module 09 will resolve a corridor from
 * these two points, and a fabricated point produces a fabricated corridor.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('trips', function (Blueprint $table): void {
            $table->id();
            $table->uuid()->unique();

            // RESTRICT, matching customer_addresses: a customer with journeys is
            // history, and erasing them is Module 17's job with an audit entry,
            // not a side effect of a DELETE somewhere else.
            $table->foreignId('customer_id')->constrained('users')->restrictOnDelete();

            $table->enum('status', TripStatus::values())->default(TripStatus::Planned->value);

            foreach (['origin', 'destination'] as $endpoint) {
                // Provenance. Nullable and SET NULL: the snapshot below is what
                // the journey means, so losing the link loses nothing.
                $table->foreignId("{$endpoint}_address_id")
                    ->nullable()
                    ->constrained('customer_addresses')
                    ->nullOnDelete();

                $table->string("{$endpoint}_label", 60);
                $table->string("{$endpoint}_formatted_address", 400);
                $table->string("{$endpoint}_city", 90);
                $table->char("{$endpoint}_country_code", 2);

                $table->decimal("{$endpoint}_latitude", 10, 7)->nullable();
                $table->decimal("{$endpoint}_longitude", 10, 7)->nullable();
                $table->string("{$endpoint}_place_id", 255)->nullable();
            }

            // Stored UTC, like every other timestamp in this schema. The customer's
            // local time is a presentation concern; storing it would make "is this
            // journey in the past?" depend on where the server is.
            $table->dateTime('departure_at');

            // Nullable, and null is the normal case. A traveller who knows when
            // they will arrive may say so; nothing computes it yet. When Module 09
            // can derive it from a real route, it fills this in — until then an
            // invented arrival time would set an invented cooking time.
            $table->dateTime('expected_arrival_at')->nullable();

            $table->unsignedTinyInteger('traveller_count')->default(1);
            $table->string('note', 280)->nullable();

            $table->dateTime('cancelled_at')->nullable();
            $table->string('cancellation_reason', 120)->nullable();

            $table->timestamps();

            // The list query: this customer's journeys in a status, by departure.
            $table->index(['customer_id', 'status', 'departure_at']);
            // The "what is next" query, which does not filter on status because a
            // cancelled journey still has to be excluded by value, not by index.
            $table->index(['customer_id', 'departure_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('trips');
    }
};
