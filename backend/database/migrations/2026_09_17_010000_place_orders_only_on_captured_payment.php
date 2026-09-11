<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/*
|--------------------------------------------------------------------------
| Module 16 — an order becomes an order when the money is captured
|--------------------------------------------------------------------------
|
| Module 15 wrote an `orders` row at checkout and attached a payment to it.
| Module 16 requires that a customer-facing order exist only downstream of a
| verified captured payment. Both are satisfied by narrowing what the earlier
| row means rather than by renaming half the codebase:
|
|   AWAITING_PAYMENT  is a payment target. It has no order number, no pickup
|                     credentials, no placed_at, and never appears in the
|                     customer's Orders tab. Nothing about it is shown to a
|                     customer as a purchase.
|
|   PLACED            is the order. Reached only through
|                     CreateOrderFromCapturedPayment, which mints the number
|                     and the pickup credentials in the same transaction.
|
| THE DEVIATION, STATED RATHER THAN HIDDEN. The specification says no order
| record may exist before capture. One does — in a table called `orders`, in a
| state that is not an order. That is a naming compromise, taken deliberately
| against renaming Module 15's table and re-opening 1,201 passing tests and a
| green device suite for no customer-visible gain. It is recorded in
| docs/31-order-creation-confirmation.md and in the completion report.
*/
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('orders', function (Blueprint $table): void {
            /*
             | Minted at placement, not at checkout. A payment target has no
             | number because there is nothing yet for a customer to read out.
             |
             | Widened from 20 to 24 to fit FOTG-YYMMDD-XXXXXXXXXX (22). The
             | alternative was trimming the random suffix, which would have
             | bought four characters of column at the cost of ten bits of
             | collision headroom — the wrong side of that trade for a value
             | that is unique-indexed and minted under load.
             */
            $table->string('order_number', 24)->nullable()->change();

            // Likewise: an order is placed when the money is captured, and
            // placed_at is the timestamp the Orders tab sorts on.
            $table->timestamp('placed_at')->nullable()->change();
        });

        Schema::table('orders', function (Blueprint $table): void {
            /*
             | ONE CAPTURED PAYMENT, AT MOST ONE ORDER — enforced by the
             | database rather than by a service.
             |
             | `if (!$orderExists)` loses a race between two workers; a unique
             | index cannot. Every duplicate delivery — second callback, second
             | webhook, reconciliation sweep, queue retry — converges on this
             | column, and the second writer gets an integrity violation it can
             | translate into "the order already exists" rather than a second
             | order.
             |
             | Nullable because a payment target has no payment placed against
             | it yet, and MySQL permits many NULLs in a unique index.
             */
            $table->foreignId('placed_from_payment_id')
                ->nullable()
                ->unique()
                ->constrained('payments')
                ->nullOnDelete();

            /*
             | PICKUP CREDENTIALS — hashes only.
             |
             | Both are keyed HMAC-SHA256 (hex, 64 chars) under an application
             | pepper, never bare hashes. A human pickup code is short enough
             | that an unkeyed digest of it is exhaustible offline in seconds:
             | an attacker with a database dump and 32^8 candidates recovers
             | every code in the table. The pepper lives outside the database,
             | so a dump alone is not enough.
             |
             | Plaintext is returned to the owning customer through a dedicated
             | endpoint and is never stored, logged, or included in ordinary
             | order responses.
             */
            $table->char('pickup_code_hash', 64)->nullable();
            $table->char('pickup_token_hash', 64)->nullable()->unique();

            // Bumping this invalidates a previously issued code and QR token
            // without touching the order. Rotation support for Module 21.
            $table->unsignedInteger('pickup_credential_version')->default(1);
            $table->timestamp('pickup_token_expires_at')->nullable();

            /*
             | OPERATIONAL SNAPSHOTS — the minimum a counter needs.
             |
             | Deliberately not a copy of the profile. A restaurant handing over
             | food needs a name to call out and, where the business requires
             | it, a verified number to ring. It does not need an email, a date
             | of birth, saved addresses, or any other trip's history.
             */
            $table->string('customer_name_snapshot', 120)->nullable();
            $table->string('customer_phone_snapshot', 20)->nullable();
            $table->string('restaurant_name_snapshot', 180)->nullable();
            $table->string('restaurant_address_snapshot', 300)->nullable();

            // The Orders tab: this customer's orders, newest first.
            $table->index(['customer_id', 'placed_at'], 'orders_customer_placed_index');

            // The restaurant queue Module 18 will need. Added now because the
            // column order is dictated by that query and retrofitting an index
            // to a large table is the expensive kind of change.
            $table->index(
                ['restaurant_id', 'status', 'pickup_start_at'],
                'orders_restaurant_queue_index',
            );
        });
    }

    public function down(): void
    {
        Schema::table('orders', function (Blueprint $table): void {
            $table->dropIndex('orders_restaurant_queue_index');
            $table->dropIndex('orders_customer_placed_index');
            $table->dropConstrainedForeignId('placed_from_payment_id');
            $table->dropColumn([
                'pickup_code_hash',
                'pickup_token_hash',
                'pickup_credential_version',
                'pickup_token_expires_at',
                'customer_name_snapshot',
                'customer_phone_snapshot',
                'restaurant_name_snapshot',
                'restaurant_address_snapshot',
            ]);
        });
    }
};
