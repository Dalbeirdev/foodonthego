<?php

declare(strict_types=1);

/**
 * What the customer has asked for, and what it was decided against.
 *
 * A pickup selection is only meaningful alongside the facts that produced it. A
 * window chosen when the cart held one quick dish is not a window that survives
 * a slow one being added, and a window chosen against a route calculated an hour
 * ago is not a window anybody should be held to. So the selection is stored with
 * a fingerprint of its inputs, and reads as STALE the moment they move.
 *
 * `version` is the cart's own counter, incremented whenever its CONTENTS change.
 * It is what lets a price-only change be told apart from a timing-relevant one:
 * a dish going up in price does not alter how long the kitchen needs, and
 * invalidating a perfectly good pickup window over it would be an insult
 * dressed as caution.
 *
 * No order is created here and none can be. These columns hold intent.
 */

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('carts', function (Blueprint $table): void {
            // Starts at 1 rather than 0: an existing cart has had one state,
            // not none, and "version 0" invites an off-by-one at every
            // comparison.
            $table->unsignedInteger('version')->default(1)->after('status');

            $table->string('pickup_selection_status', 12)
                ->default('NONE')
                ->after('expires_at');

            // Instants, in UTC, as every timestamp in this schema is. The
            // restaurant's zone travels beside them because a pickup happens at
            // the counter, on the counter's clock.
            $table->timestamp('requested_pickup_start_at')->nullable()->after('pickup_selection_status');
            $table->timestamp('requested_pickup_end_at')->nullable()->after('requested_pickup_start_at');
            $table->string('pickup_timezone', 64)->nullable()->after('requested_pickup_end_at');
            $table->timestamp('pickup_selected_at')->nullable()->after('pickup_timezone');

            // The fingerprint of the inputs the selection was made against:
            // cart version, route and its calculation time, restaurant state,
            // hours, and the planning configuration version. Compared rather
            // than parsed — it is opaque on purpose.
            $table->char('pickup_planning_fingerprint', 64)->nullable()->after('pickup_selected_at');
        });
    }

    public function down(): void
    {
        Schema::table('carts', function (Blueprint $table): void {
            $table->dropColumn([
                'version',
                'pickup_selection_status',
                'requested_pickup_start_at',
                'requested_pickup_end_at',
                'pickup_timezone',
                'pickup_selected_at',
                'pickup_planning_fingerprint',
            ]);
        });
    }
};
