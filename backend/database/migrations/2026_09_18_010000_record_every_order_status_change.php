<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * An order's status stops being a value and becomes a history.
 *
 * Module 16 left `orders.status` as a single column with one writer. That was
 * enough while an order had exactly one thing that could happen to it. From
 * here a restaurant accepts, refuses, cooks and finishes orders, and the
 * customer is shown a timeline of when each of those happened — so "what is the
 * status" and "how did it get there" become two different questions, and only
 * the second one can be audited.
 *
 * THE HISTORY IS THE RECORD. `orders.status` and the milestone timestamps below
 * are a denormalised cache of the latest row in `order_status_history`, kept
 * because the Orders tab must not join a history table to sort a list. Where
 * they disagree, the history is right and something is broken — which is why
 * `orders:check-integrity` gains a test for exactly that.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('order_status_history', function (Blueprint $table): void {
            $table->id();
            $table->uuid('uuid')->unique();

            $table->foreignId('order_id')->constrained()->cascadeOnDelete();

            /*
             | Null only for the very first row.
             |
             | An order's first history entry records it arriving at PLACED from
             | nothing. Making that a nullable column rather than inventing a
             | synthetic "NONE" status keeps the enum honest: there is no state
             | an order is in before it exists.
             */
            $table->string('from_status', 20)->nullable();
            $table->string('to_status', 20);

            /*
             | WHO CAUSED THIS, recorded for audit rather than for display.
             |
             | source_type is the category — SYSTEM, RESTAURANT, ADMIN, PAYMENT,
             | CUSTOMER_ACTION. actor_type/actor_id name the principal when
             | there is one. None of it reaches the customer: a customer needs
             | to know their order was accepted, not which member of staff
             | pressed the button, and shipping that identity to a stranger's
             | phone is a privacy leak with no upside.
             */
            $table->string('source_type', 20);
            $table->string('actor_type', 40)->nullable();
            $table->unsignedBigInteger('actor_id')->nullable();

            /*
             | Two different reasons, deliberately.
             |
             | reason_code is internal and may name anything operations finds
             | useful. customer_safe_note is the only thing a customer may see,
             | and it is written by the caller that already knows what is safe
             | to say. Deriving customer copy from an internal code at render
             | time is how "Staff shortage: employee #47 failed shift" reaches a
             | phone.
             */
            $table->string('reason_code', 60)->nullable();
            $table->string('customer_safe_note', 200)->nullable();

            $table->uuid('correlation_id')->nullable();

            /*
             | When it happened, from the server's clock.
             |
             | Separate from created_at because a backfilled or reconciled row
             | may be written long after the event it records, and a timeline
             | built on row-creation time would then lie about the order.
             */
            $table->timestamp('occurred_at');
            $table->timestamps();

            /*
             | The timeline query, and the tie-break that makes it deterministic.
             |
             | Two transitions inside the same second are possible -- a test
             | harness does it routinely -- and ordering by occurred_at alone
             | would leave their order up to the storage engine. The id breaks
             | the tie, and every reader sorts by both.
             */
            $table->index(['order_id', 'occurred_at', 'id'], 'order_status_history_timeline_index');

            /*
             | ONE ROW PER ORDER PER STATE.
             |
             | The current lifecycle has no state an order legitimately enters
             | twice, so a second ACCEPTED row means a duplicate delivery got
             | through -- and this index refuses it rather than putting two
             | "Restaurant accepted your order" entries on somebody's timeline.
             |
             | The day a state does legitimately repeat, this constraint has to
             | be removed deliberately, which is the point: it forces that
             | decision to be made rather than discovered.
             */
            $table->unique(['order_id', 'to_status'], 'order_status_history_once_index');
        });

        Schema::table('orders', function (Blueprint $table): void {
            /*
             | The milestone timestamps, one per state that has one.
             |
             | placed_at, paid_at and cancelled_at already exist. These complete
             | the set so a timeline can be read off the order row without
             | touching the history table -- and so `status = READY` with a null
             | ready_at is a detectable inconsistency rather than an invisible
             | one.
             */
            $table->timestamp('accepted_at')->nullable()->after('paid_at');
            $table->timestamp('rejected_at')->nullable()->after('accepted_at');
            $table->timestamp('cooking_started_at')->nullable()->after('rejected_at');
            $table->timestamp('ready_at')->nullable()->after('cooking_started_at');
            $table->timestamp('picked_up_at')->nullable()->after('ready_at');

            /*
             | Incremented on every status transition.
             |
             | THIS EXISTS FOR THE CLIENT, not for the database. A phone polling
             | this order can receive two responses out of order -- a slow
             | COOKING answer arriving after a fast READY one -- and comparing
             | status strings cannot tell which is newer, because the client
             | must not be the thing that knows COOKING precedes READY. A
             | monotonically increasing integer can, and it stays correct when
             | the lifecycle gains states the client has never heard of.
             |
             | Starts at 1: an order that has never transitioned since creation
             | is still at its first version, and 0 would make "never
             | transitioned" and "unset" the same value.
             */
            $table->unsignedBigInteger('order_version')->default(1)->after('status');

            /*
             | The customer-safe half of why an order ended badly.
             |
             | orders.cancellation_reason already exists and is internal. This
             | is the sentence a customer may read, and it is nullable because
             | most exceptions have nothing safe to add beyond the status
             | itself.
             */
            $table->string('customer_safe_reason', 200)->nullable()->after('cancellation_reason');

            $table->index(['customer_id', 'status', 'placed_at'], 'orders_customer_active_index');
        });
    }

    public function down(): void
    {
        Schema::table('orders', function (Blueprint $table): void {
            $table->dropIndex('orders_customer_active_index');
            $table->dropColumn([
                'accepted_at',
                'rejected_at',
                'cooking_started_at',
                'ready_at',
                'picked_up_at',
                'order_version',
                'customer_safe_reason',
            ]);
        });

        Schema::dropIfExists('order_status_history');
    }
};
