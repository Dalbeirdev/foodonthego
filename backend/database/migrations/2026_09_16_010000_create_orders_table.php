<?php

declare(strict_types=1);

/**
 * What a customer actually committed to buy, at a price that no longer moves.
 *
 * The difference between this table and `checkout_quotes` is the difference
 * between an offer and an agreement. A quote expires and is recomputed; an
 * order is a financial record and its numbers are frozen the moment it is
 * written. Nothing recalculates an order's total, ever — not on read, not when
 * the menu changes, not when the commercial rules change.
 *
 * Every amount is an integer of minor units. No float has authority over money
 * anywhere in this schema.
 *
 * `checkout_quote_id` is UNIQUE. One quote becomes at most one order, enforced
 * by the database rather than by a service remembering to check, because the
 * failure it prevents is a customer charged twice for one basket after a
 * double-tap or a retried request.
 *
 * The `*_configured` flags come across from the quote unchanged, for the same
 * reason they exist there: "no tax rule" and "a tax rule of nought" are
 * different facts, and an order that flattens them tells a later reader a
 * decision was made when none was.
 */

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('orders', function (Blueprint $table): void {
            $table->id();
            $table->uuid()->unique();

            // What a human says out loud. Distinct from the uuid, which is what
            // a URL carries: a customer reading a number to somebody at a
            // counter should not be reading 36 hex characters.
            $table->string('order_number', 20)->unique();

            $table->foreignId('customer_id')->constrained('users')->cascadeOnDelete();
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();

            // The journey and basket this came from. Nullable and nulled rather
            // than cascaded: an order outlives the cart it was assembled in, and
            // deleting a trip must not delete the money.
            $table->foreignId('trip_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignId('cart_id')->nullable()->constrained()->nullOnDelete();

            // One quote, at most one order. The whole double-charge class of bug
            // is closed here rather than in a service.
            $table->foreignId('checkout_quote_id')->nullable()->unique()->constrained()->nullOnDelete();

            // The pickup window that was agreed. Stored, not looked up: what the
            // restaurant promised is a fact about this order.
            $table->timestamp('pickup_start_at')->nullable();
            $table->timestamp('pickup_end_at')->nullable();
            $table->string('pickup_timezone', 64)->nullable();

            $table->char('currency', 3)->default('INR');

            $table->unsignedBigInteger('items_subtotal_minor');

            $table->unsignedBigInteger('tax_minor')->default(0);
            $table->boolean('tax_configured')->default(false);

            $table->unsignedBigInteger('packaging_fee_minor')->default(0);
            $table->boolean('packaging_fee_configured')->default(false);

            $table->unsignedBigInteger('platform_fee_minor')->default(0);
            $table->boolean('platform_fee_configured')->default(false);

            $table->unsignedBigInteger('discount_minor')->default(0);
            $table->boolean('discount_configured')->default(false);

            $table->bigInteger('other_adjustment_minor')->default(0);
            $table->boolean('other_adjustment_configured')->default(false);

            // The authority on what is owed. Every payment is checked against
            // this column and nothing else; a provider saying a different number
            // is a mismatch to refuse, not a total to adopt.
            $table->unsignedBigInteger('payable_total_minor');

            $table->unsignedInteger('commercial_rule_version')->default(1);

            /*
             * Payment states only, and deliberately no further.
             *
             * AWAITING_PAYMENT, PAID, PAYMENT_FAILED, CANCELLED. There is no
             * PREPARING, READY or COLLECTED, because no fulfilment workflow has
             * been specified and inventing one here would create a vocabulary
             * that screens and reports start depending on before anybody has
             * decided it is right.
             *
             * PAID is written once. The transition is guarded in the service and
             * `paid_at` records when it happened; a second verification of the
             * same payment is a no-op rather than a second write.
             */
            $table->string('status', 20)->default('AWAITING_PAYMENT');

            $table->timestamp('placed_at');
            $table->timestamp('paid_at')->nullable();
            $table->timestamp('cancelled_at')->nullable();
            $table->string('cancellation_reason', 200)->nullable();

            $table->timestamps();

            $table->index(['customer_id', 'id'], 'orders_customer_index');
            $table->index(['restaurant_id', 'status'], 'orders_restaurant_status_index');
            $table->index('status', 'orders_status_index');

            // Lets the line tables carry a composite key back to this order and
            // its restaurant, so a line holding another restaurant's dish is not
            // a row that can be written.
            $table->unique(['id', 'restaurant_id'], 'orders_id_restaurant_unique');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('orders');
    }
};
