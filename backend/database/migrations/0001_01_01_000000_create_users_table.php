<?php

declare(strict_types=1);

use App\Enums\Role;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The users table, and with it the conventions every later migration follows.
 * See docs/06-database-conventions.md.
 *
 *  - Surrogate key is a BIGINT auto-increment, because InnoDB clusters on the
 *    primary key and a random UUID primary key fragments every insert.
 *  - A separate indexed UUID is what the API exposes. Sequential ids in URLs let
 *    anyone count our customers and walk to the next one.
 *  - Timestamps everywhere; soft deletes on anything a human can remove, so a
 *    deletion is recoverable and an audit trail keeps its foreign keys.
 *  - Money, when it arrives in later modules, is an integer of minor units. Never
 *    FLOAT, never DOUBLE.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('users', function (Blueprint $table): void {
            $table->id();
            $table->uuid('uuid')->unique();

            $table->string('name');
            $table->string('email')->unique();
            $table->timestamp('email_verified_at')->nullable();
            $table->string('phone', 32)->nullable()->unique();
            $table->timestamp('phone_verified_at')->nullable();
            $table->string('password');

            $table->enum('role', Role::values())->default(Role::Customer->value);
            $table->boolean('is_active')->default(true);
            $table->timestamp('last_seen_at')->nullable();

            $table->rememberToken();
            $table->timestamps();
            $table->softDeletes();

            // Supports the commonest admin query — active accounts of one role,
            // newest first — without a filesort.
            $table->index(['role', 'is_active']);
            $table->index('created_at');
        });

        Schema::create('password_reset_tokens', function (Blueprint $table): void {
            $table->string('email')->primary();
            $table->string('token');
            $table->timestamp('created_at')->nullable();
        });

        Schema::create('sessions', function (Blueprint $table): void {
            $table->string('id')->primary();
            $table->foreignId('user_id')->nullable()->index();
            $table->string('ip_address', 45)->nullable();
            $table->text('user_agent')->nullable();
            $table->longText('payload');
            $table->integer('last_activity')->index();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('sessions');
        Schema::dropIfExists('password_reset_tokens');
        Schema::dropIfExists('users');
    }
};
