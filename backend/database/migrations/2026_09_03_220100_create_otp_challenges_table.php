<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * An OTP challenge: one issued code, and everything needed to verify it safely.
 *
 * The code itself is **never stored**. `otp_hash` is a peppered hash, so a dump of
 * this table does not hand an attacker a working code for every phone number in
 * flight — the same reason password columns hold hashes.
 *
 * `attempts` and `expires_at` live here rather than in Redis because they are the
 * security state of the challenge: MySQL is the source of truth (Module 01), and
 * a Redis flush must not silently reset somebody's brute-force counter to zero.
 * Redis still does the request-rate limiting, where losing a counter is merely
 * generous rather than dangerous.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('otp_challenges', function (Blueprint $table): void {
            $table->id();
            $table->uuid('uuid')->unique();

            $table->string('phone_e164', 20);
            $table->string('otp_hash');

            $table->timestamp('expires_at');
            $table->unsignedTinyInteger('attempts')->default(0);
            $table->unsignedTinyInteger('max_attempts');

            // Set the moment a code is accepted, so the same code can never be
            // presented twice.
            $table->timestamp('consumed_at')->nullable();

            // Set when a newer challenge supersedes this one, or when attempts run
            // out. Distinct from `consumed_at`: one means "used", the other means
            // "must never be used".
            $table->timestamp('invalidated_at')->nullable();
            $table->string('invalidated_reason', 40)->nullable();

            $table->unsignedTinyInteger('resend_count')->default(0);
            $table->timestamp('last_sent_at')->nullable();

            // Operational metadata for abuse investigation. Deliberately minimal —
            // no device fingerprint, no advertising id. See docs/07-security.md.
            $table->string('request_ip', 45)->nullable();

            $table->timestamps();

            // The lookup every verify performs: newest live challenge for a number.
            $table->index(['phone_e164', 'consumed_at', 'invalidated_at']);
            // Supports the cleanup job.
            $table->index('expires_at');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('otp_challenges');
    }
};
