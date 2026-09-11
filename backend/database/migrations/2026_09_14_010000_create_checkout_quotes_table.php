<?php

declare(strict_types=1);

/**
 * What was offered, at what price, for how long.
 *
 * A checkout quote is NOT an order, NOT a Razorpay order and NOT a payment.
 * Nothing in Module 14 creates any of those, and the statuses here are chosen
 * so that nothing can mistake this for one: borrowing PENDING or CONFIRMED
 * from an order lifecycle would make a quote look like something it is not.
 *
 * Every amount is an integer of minor units. No float has authority over money
 * anywhere in this schema, and a quote is the last place one could sneak in.
 *
 * The `*_configured` flags exist because "not configured" and "configured as
 * zero" are different facts. A restaurant with a null tax rate has no tax rule;
 * one with a rate of nought has a rule that says nought. A screen showing
 * "Tax 0.00" for the first case tells a customer a decision was made when none
 * was.
 */

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('checkout_quotes', function (Blueprint $table): void {
            $table->id();
            $table->uuid()->unique();

            $table->foreignId('customer_id')->constrained('users')->cascadeOnDelete();
            $table->foreignId('cart_id')->constrained()->cascadeOnDelete();
            $table->foreignId('trip_id')->constrained()->cascadeOnDelete();
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();

            // The cart's own counter at the moment of quoting. Part of the
            // fingerprint, and stored separately so a stale quote can say what
            // it was quoted against rather than only that it disagrees.
            $table->unsignedInteger('cart_version');

            // The pickup window this price was quoted for. A quote is for a
            // basket AND a time; the same basket an hour later is a different
            // promise.
            $table->timestamp('pickup_start_at')->nullable();
            $table->timestamp('pickup_end_at')->nullable();
            $table->string('pickup_timezone', 64)->nullable();

            $table->char('currency', 3)->default('INR');

            $table->unsignedBigInteger('items_subtotal_minor');

            // Each component, and whether anybody has actually configured it.
            $table->unsignedBigInteger('tax_minor')->default(0);
            $table->boolean('tax_configured')->default(false);

            $table->unsignedBigInteger('packaging_fee_minor')->default(0);
            $table->boolean('packaging_fee_configured')->default(false);

            $table->unsignedBigInteger('platform_fee_minor')->default(0);
            $table->boolean('platform_fee_configured')->default(false);

            // Discounts have no mechanism in this project yet. The columns exist
            // so that adding one later is a service change rather than a
            // migration on a table holding live quotes, and they are asserted to
            // be nought for as long as nothing can set them.
            $table->unsignedBigInteger('discount_minor')->default(0);
            $table->boolean('discount_configured')->default(false);

            $table->bigInteger('other_adjustment_minor')->default(0);
            $table->boolean('other_adjustment_configured')->default(false);

            // What the customer would pay. Stored rather than derived on read,
            // because a quote is a record of what was offered — recomputing it
            // later would answer a different question.
            $table->unsignedBigInteger('payable_total_minor');

            // ACTIVE and CONSUMED are stored. STALE and EXPIRED are DERIVED on
            // every read: a column reading ACTIVE after the cart changed is not
            // wrong because a job failed to run, it is wrong because a column
            // cannot know. Same reasoning as Module 13's pickup selection.
            $table->string('status', 12)->default('ACTIVE');

            // Opaque, compared and never parsed. Covers customer, cart and its
            // version, restaurant, trip, route and its calculation time, the
            // pickup selection, the commercial rule version, and the currency.
            $table->char('fingerprint', 64);

            // Which commercial rules produced these figures. Changing a tax
            // rate or a fee moves this, which invalidates every outstanding
            // quote — without it a customer could hold a quote across a pricing
            // change and pay yesterday's number.
            $table->unsignedInteger('commercial_rule_version');

            $table->timestamp('expires_at');
            $table->timestamps();

            $table->index(['customer_id', 'cart_id', 'status'], 'checkout_quotes_lookup_index');

            // A quote's cart is its customer's cart. Composite, like every other
            // cross-entity guarantee in this schema, so a quote naming another
            // customer's cart is unwritable rather than merely unlikely.
            $table->unique(['id', 'customer_id'], 'checkout_quotes_id_customer_unique');
        });

        Schema::table('checkout_quotes', function (Blueprint $table): void {
            $table->foreign(['cart_id', 'customer_id'], 'checkout_quotes_cart_same_customer')
                ->references(['id', 'customer_id'])
                ->on('carts')
                ->cascadeOnDelete();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('checkout_quotes');
    }
};
