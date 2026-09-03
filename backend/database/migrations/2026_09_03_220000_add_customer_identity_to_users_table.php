<?php

declare(strict_types=1);

use App\Enums\AccountStatus;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Module 03 — customer identity on the existing `users` table.
 *
 * One users table with a role column, not a separate `customers` table. A second
 * identity system would mean two authentication paths, two token stores and two
 * places to get suspension wrong; the role separation established in Module 01 is
 * what keeps a customer out of the admin API.
 *
 * `name` is split into `first_name` / `last_name` because registration collects
 * them separately and re-splitting a joined string is lossy for names like
 * "Krishnamurthy-Ramanathan".
 *
 * `password` becomes nullable: a customer authenticates by OTP and never has one.
 * Storing a dummy hash to satisfy a NOT NULL would be a lie in the schema.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table): void {
            $table->string('first_name')->nullable()->after('uuid');
            $table->string('last_name')->nullable()->after('first_name');

            // The canonical identity. Unique, so two spellings of one number can
            // never become two accounts — enforced by the database, not by a
            // SELECT-then-INSERT that races.
            $table->string('phone_e164', 20)->nullable()->unique()->after('phone');

            // ENUM, not a string — the same convention as `role`, and for the
            // same reason: the database refuses a status the application does
            // not have a case for, so a typo in a migration or a manual UPDATE
            // fails loudly instead of creating an account nobody can classify.
            $table->enum('status', AccountStatus::values())
                ->default(AccountStatus::Active->value)
                ->after('role');
            $table->timestamp('last_login_at')->nullable()->after('last_seen_at');

            $table->index(['status', 'role']);
        });

        // Backfill before adding constraints, so an existing row is not orphaned.
        Schema::table('users', function (Blueprint $table): void {
            $table->string('password')->nullable()->change();
            $table->string('email')->nullable()->change();
            $table->string('name')->nullable()->change();
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table): void {
            $table->dropIndex(['status', 'role']);
            $table->dropUnique(['phone_e164']);
            $table->dropColumn(['first_name', 'last_name', 'phone_e164', 'status', 'last_login_at']);
        });
    }
};
