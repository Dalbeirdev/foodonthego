<?php

declare(strict_types=1);

/**
 * An attempt to pay for an order, and what became of it.
 *
 * An order may have several of these. A card that is declined does not
 * invalidate the order; the customer tries again, and each attempt is its own
 * row. What cannot happen twice is an order becoming PAID — that is guarded on
 * `orders`, not here.
 *
 * `amount_minor` is stored on the attempt as well as on the order, and they are
 * compared before anything is marked paid. Duplication is the point: the value
 * the provider was asked for and the value the order says is owed are two
 * different facts, and a mismatch between them is exactly the thing worth
 * detecting.
 *
 * `provider_order_id` and `provider_payment_id` are unique. A provider payment
 * identifier that has already been recorded cannot be presented against a
 * second order — the replay is refused by the database, not merely by a check.
 *
 * **No card data of any kind is stored here.** Not a PAN, not a last-four, not
 * a network, not a cardholder name. This table holds identifiers, an amount, a
 * status and timestamps, and there is deliberately no column into which such a
 * thing could be written by a later change that was not thinking about it.
 */

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('payments', function (Blueprint $table): void {
            $table->id();
            $table->uuid()->unique();

            $table->foreignId('order_id')->constrained()->cascadeOnDelete();

            // 'razorpay' today. A column rather than an assumption, because the
            // identifiers below are only unique within a provider.
            $table->string('provider', 32)->default('razorpay');

            // The provider's own order object, created server-side. The client
            // is told this id so its SDK can open a checkout against it; it is
            // not something the client chooses.
            $table->string('provider_order_id', 80);

            // Arrives with the result. Null until then.
            $table->string('provider_payment_id', 80)->nullable();

            $table->unsignedBigInteger('amount_minor');
            $table->char('currency', 3)->default('INR');

            // CREATED, AUTHORIZED, CAPTURED, FAILED.
            $table->string('status', 20)->default('CREATED');

            // When the server satisfied itself that this really happened, and
            // what convinced it. A payment is never trusted because a client
            // said so; this column records which authority was believed.
            //
            // CLIENT_CALLBACK — a signature the app returned, verified here.
            // WEBHOOK — the provider told us directly, signature verified.
            // RECONCILIATION — we went and asked.
            $table->timestamp('verified_at')->nullable();
            $table->string('verification_source', 20)->nullable();

            // The provider's reason, if it gave one. Free text from an external
            // system, rendered as text and never interpreted as a code.
            $table->string('failure_reason', 200)->nullable();

            $table->timestamps();

            $table->unique(['provider', 'provider_order_id'], 'payments_provider_order_unique');
            $table->unique(['provider', 'provider_payment_id'], 'payments_provider_payment_unique');
            $table->index(['order_id', 'status'], 'payments_order_status_index');
            $table->index('status', 'payments_status_index');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('payments');
    }
};
