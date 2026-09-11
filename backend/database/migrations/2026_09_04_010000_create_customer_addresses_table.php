<?php

declare(strict_types=1);

use App\Enums\AddressType;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * A place a customer has saved: Home, Work, or somewhere they named themselves.
 *
 * Two design points worth reading before changing anything here.
 *
 * **The one-default rule is enforced by the database, not by application code.**
 * See `default_for_customer` below. Application-level locking is still used — it
 * produces a clean error instead of a constraint violation — but it is the second
 * line of defence, not the only one.
 *
 * **Coordinates are nullable and stay NULL until something actually geocodes.**
 * The schema is ready for Google Places — `place_id`, `latitude`, `longitude`,
 * `formatted_address` — because the trip planner will need to route between saved
 * addresses. Inventing coordinates from a typed address would produce a route to
 * a place the customer never chose, which is worse than having none.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('customer_addresses', function (Blueprint $table): void {
            $table->id();
            $table->uuid('uuid')->unique();

            // RESTRICT, not CASCADE, and the reason is a MySQL rule rather than a
            // preference: a column referenced by a stored generated column cannot
            // carry ON DELETE CASCADE (error 1215), and `default_for_customer`
            // below references this one.
            //
            // Given the choice, the generated column wins. It makes "at most one
            // default per customer" impossible to violate, including by a future
            // code path that forgets to take the lock — while cascade only saves
            // a step on a path that barely exists, since customers are soft
            // deleted and a hard erase is an explicit operation in its own right.
            //
            // The consequence, stated so it is not a surprise: erasing a customer
            // must delete their addresses first. A hard delete with addresses
            // still attached fails loudly instead of silently destroying them,
            // which is the better failure for an erasure path that will need an
            // audit trail anyway.
            $table->foreignId('customer_id')
                ->constrained('users')
                ->restrictOnDelete();

            $table->enum('type', AddressType::values());

            // What the customer calls it. Seeded from the type for HOME/WORK and
            // required for OTHER.
            $table->string('label', 60);

            // Structured, because the trip planner needs the parts and because a
            // single free-text blob cannot be corrected field by field.
            $table->string('address_line_1', 180);
            $table->string('address_line_2', 180)->nullable();
            $table->string('landmark', 120)->nullable();
            $table->string('city', 90);
            $table->string('state', 90);

            // Nullable: not every country has postal codes, and several that do
            // treat them as optional.
            $table->string('postal_code', 16)->nullable();

            // ISO 3166-1 alpha-2. India-first, never India-only.
            $table->char('country_code', 2);

            // The single-line form for display and for handing to a maps SDK. It
            // is composed from the parts above until Places supplies a real one.
            $table->string('formatted_address', 400);

            // Reserved for the mapping module. NULL until something geocodes; see
            // docs/19-customer-profile-and-addresses.md.
            $table->decimal('latitude', 10, 7)->nullable();
            $table->decimal('longitude', 10, 7)->nullable();
            $table->string('place_id', 255)->nullable();

            $table->boolean('is_default')->default(false);

            // The database-level one-default guarantee.
            //
            // MySQL has no partial indexes, so this generated column holds the
            // customer id only while the row is the default and NULL otherwise —
            // and MySQL does not collide NULLs in a unique index. Two concurrent
            // "make this my default" requests therefore cannot both win, whatever
            // the application does.
            //
            // It is declared here, inside CREATE TABLE, rather than added by a
            // later ALTER: adding a STORED generated column rebuilds the table
            // with the copy algorithm, and MySQL cannot re-create the foreign key
            // while doing so (error 1215).
            //
            // ->nullable() is load-bearing, not decoration: without it Laravel
            // appends NOT NULL, the column can never be NULL, and every row would
            // then collide on the unique index below.
            $table->rawColumn(
                'default_for_customer',
                'bigint unsigned generated always as (if(is_default = 1, customer_id, null)) stored',
            )->nullable();
            $table->unique('default_for_customer', 'customer_addresses_one_default_unique');

            $table->timestamps();

            // The list query: one customer's addresses, default first.
            $table->index(['customer_id', 'is_default']);
            // Supports "did this customer already save this type" without a scan.
            $table->index(['customer_id', 'type']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('customer_addresses');
    }
};
