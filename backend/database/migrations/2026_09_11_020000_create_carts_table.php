<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * What a customer has chosen so far, on one journey, from one restaurant.
 *
 * Three scoping decisions, all of them enforced rather than documented:
 *
 * **One active cart per customer per trip.** A cart belongs to the journey the
 * restaurant was discovered on, because a stop makes no sense away from the
 * road it is on. A partial-unique index below makes a second active cart for
 * the same trip impossible.
 *
 * **One restaurant per cart.** A pickup order is collected at a counter; two
 * counters is two orders. Adding a second restaurant's dish is refused with a
 * conflict rather than silently merged or silently emptied — Module 12 owns
 * whatever "start a new cart" looks like, and destroying a customer's
 * selections to make an API call succeed is not a decision this module gets to
 * take on their behalf.
 *
 * **One currency per cart.** Stored here rather than derived, so a mixed-currency
 * cart is a constraint violation rather than an arithmetic surprise.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('carts', function (Blueprint $table): void {
            $table->id();
            $table->uuid()->unique();

            $table->foreignId('customer_id')->constrained('users')->cascadeOnDelete();
            $table->foreignId('trip_id')->constrained()->cascadeOnDelete();
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();

            $table->string('status', 20)->default('ACTIVE');
            $table->char('currency', 3)->default('INR');

            // The foundation for stale-cart handling, which is Module 12's.
            // Written on every change; nothing deletes on it yet, deliberately —
            // a scheduled job that silently empties carts is not something to
            // ship before the screen that would explain it exists.
            $table->timestamp('last_activity_at')->nullable();
            $table->timestamp('expires_at')->nullable();

            $table->timestamps();

            // At most one ACTIVE cart per (customer, trip).
            //
            // MySQL has no partial index, so this generated column stands in
            // for one: it is 1 while the cart is active and NULL otherwise, and
            // NULLs do not collide in a unique index. A second active cart for
            // one journey therefore cannot be written — not by a race between
            // two taps, not by a bug in the service.
            //
            // The flag is derived from `status` alone and the trip id goes in
            // the index instead. Deriving it from `trip_id` would read more
            // directly and MySQL refuses it: a column used in a generated
            // expression cannot carry a cascading foreign key, and a trip that
            // is deleted must take its carts with it.
            $table->unsignedTinyInteger('active_flag')
                ->nullable()
                ->storedAs("CASE WHEN status = 'ACTIVE' THEN 1 ELSE NULL END");

            $table->index(['customer_id', 'status'], 'carts_customer_status_index');
            $table->index('expires_at', 'carts_expiry_index');

            $table->unique(
                ['customer_id', 'trip_id', 'active_flag'],
                'carts_one_active_per_trip_unique',
            );

            // For the composite keys cart items carry.
            $table->unique(['id', 'customer_id'], 'carts_id_customer_unique');
            $table->unique(['id', 'restaurant_id'], 'carts_id_restaurant_unique');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('carts');
    }
};
