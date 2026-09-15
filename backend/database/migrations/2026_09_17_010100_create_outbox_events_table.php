<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/*
|--------------------------------------------------------------------------
| The transactional outbox
|--------------------------------------------------------------------------
|
| An order that exists but whose OrderPlaced event was lost is a restaurant
| that never hears about food it has been paid for. Dispatching to a queue
| inside the transaction does not fix that — the queue write can succeed and
| the transaction still roll back, which produces the opposite and worse
| failure: an event for an order that does not exist.
|
| So the event is a row, written in the same transaction as the order. Either
| both are there or neither is. A worker publishes rows afterwards, and may
| publish the same row twice if it dies mid-flight — which is why consumers
| must be idempotent and why every row carries a stable event id to
| deduplicate on.
|
| PAYLOADS CARRY IDENTIFIERS, NOT BUSINESS DATA. A consumer that needs the
| basket reads it from the order. An event carrying a copy of the cart is a
| second source of truth that goes stale the moment anything changes, and it
| puts customer data in a table that exists to be shipped elsewhere.
*/
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('outbox_events', function (Blueprint $table): void {
            $table->id();

            // What a consumer deduplicates on. Stable across republishing:
            // the same logical event keeps this id however many times the
            // worker delivers it.
            $table->uuid('event_id')->unique();

            $table->string('event_name', 64);

            /*
             | EXACTLY ONE LOGICAL EVENT PER SUBJECT, enforced by the database.
             |
             | dedupe_key is the subject the event is about — for OrderPlaced,
             | the order's uuid. Order creation retried after a partial failure
             | re-enters this insert and is rejected, so a customer's order
             | cannot produce two OrderPlaced events no matter how many times
             | the creation path runs.
             */
            $table->string('dedupe_key', 64);

            // Identifiers only. See the note above.
            $table->json('payload');

            $table->string('status', 12)->default('PENDING');
            $table->unsignedSmallInteger('attempts')->default(0);
            $table->timestamp('available_at')->nullable();
            $table->timestamp('published_at')->nullable();

            // Truncated deliberately: a provider error can be long and this
            // column is read by operators, not machines.
            $table->string('last_error', 300)->nullable();

            $table->timestamps();

            $table->unique(['event_name', 'dedupe_key'], 'outbox_events_subject_unique');

            // The publisher's query: oldest pending first.
            $table->index(['status', 'available_at'], 'outbox_events_pending_index');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('outbox_events');
    }
};
