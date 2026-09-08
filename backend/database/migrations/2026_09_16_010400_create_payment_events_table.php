<?php

declare(strict_types=1);

/**
 * Every webhook the provider sent, recorded exactly once.
 *
 * `provider_event_id` is UNIQUE, and that single constraint is the entire
 * idempotency mechanism. Providers retry: a delivery that times out, or that
 * this server answers slowly, arrives again. Without this, a retried
 * `payment.captured` runs the capture path twice.
 *
 * Doing it with a unique index rather than a "have I seen this?" query is
 * deliberate. Two deliveries can be in flight at the same moment, and a check
 * followed by a write has a gap between them; a unique index does not.
 *
 * **The payload is not stored.** Only a SHA-256 digest of the raw body, plus
 * the handful of identifiers the handler actually needs. A provider payload can
 * carry a contact number, an email address, a billing name and card metadata,
 * and none of that is ours to keep. The digest is enough for the one question
 * worth asking later — "was this the same delivery?" — without keeping the
 * thing itself.
 *
 * **Only deliveries that passed signature verification are stored here, and that
 * is a security property rather than tidiness.** The endpoint is public: anybody
 * can post to it. If a rejected delivery were written with the event id it
 * claimed, an attacker could send a forged body carrying the event id of a real
 * payment they knew was coming, and the genuine delivery would then collide with
 * the unique index and be discarded as a duplicate — a paid order left unpaid,
 * by an attacker who never needed the secret. Rejected deliveries are logged
 * instead, where they are visible without being load-bearing.
 */

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('payment_events', function (Blueprint $table): void {
            $table->id();

            $table->string('provider', 32)->default('razorpay');

            // The provider's identifier for this delivery. The whole of the
            // idempotency guarantee rests on the unique index below.
            $table->string('provider_event_id', 120);

            $table->string('event_type', 80);

            // Resolved where possible. Null when a delivery names something this
            // server does not know about, which is itself worth recording rather
            // than discarding.
            $table->foreignId('payment_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignId('order_id')->nullable()->constrained()->nullOnDelete();

            // SHA-256 of the raw request body. Not the body.
            $table->char('payload_digest', 64);

            $table->timestamp('received_at');
            $table->timestamp('processed_at')->nullable();

            // What the handler did: APPLIED, DUPLICATE or IGNORED. Never
            // REJECTED — a rejected delivery does not reach this table.
            $table->string('outcome', 20)->nullable();

            $table->timestamps();

            $table->unique(['provider', 'provider_event_id'], 'payment_events_provider_event_unique');
            $table->index(['order_id', 'id'], 'payment_events_order_index');
            $table->index('event_type', 'payment_events_type_index');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('payment_events');
    }
};
