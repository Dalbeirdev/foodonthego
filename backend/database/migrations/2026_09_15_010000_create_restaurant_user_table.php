<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Who may work at which restaurant.
 *
 * **This table is the tenant boundary.** A restaurant is a tenant, and the only
 * way anybody reaches one is a row here. There is deliberately no
 * `restaurants.owner_id`: an owner is an assignment whose role is `owner`, so
 * there is one place to look and one place to revoke. Two sources of truth for
 * "who owns this" is how a removed owner keeps their access.
 *
 * The role lives here rather than on `users` because the same person can be an
 * owner at one restaurant and a cook at another, and a single column on `users`
 * cannot say that. `users.role` still decides which *surface* somebody signs in
 * to; this decides what they may do once inside a given tenant. Both are
 * checked — see App\Services\Tenancy\TenantAccessService.
 *
 * `status` exists so that access can be withdrawn without deleting the record
 * that it once existed. A dismissed manager is a revoked row, not a missing one,
 * and the difference matters the first time somebody asks who had access in
 * March.
 *
 * The unique pair is a database constraint rather than a validation rule. Two
 * assignments for one person at one restaurant would make "what may they do
 * here" ambiguous, and an ambiguous authorisation question gets answered
 * differently by different code paths.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('restaurant_user', function (Blueprint $table): void {
            $table->id();
            $table->uuid()->unique();

            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();

            // 'owner' | 'manager' | 'staff' — App\Enums\TenantRole. A string, so
            // a row read in a console is self-describing and re-ordering an enum
            // can never silently promote somebody.
            $table->string('tenant_role', 20);

            // 'active' | 'revoked'.
            $table->string('status', 20)->default('active');

            // Who granted it and when it stopped applying. Not an audit log —
            // that is Module 18 — but the minimum needed to answer "who let them
            // in" without one.
            $table->foreignId('granted_by_user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('granted_at')->nullable();
            $table->timestamp('revoked_at')->nullable();

            $table->timestamps();

            // One assignment per person per restaurant, enforced by the database.
            $table->unique(['restaurant_id', 'user_id'], 'restaurant_user_unique_membership');

            // The two directions authorisation actually reads: "which tenants may
            // this user reach" on every request, and "who works here" on a staff
            // screen. Both filter on status, so it is in the index.
            $table->index(['user_id', 'status'], 'restaurant_user_by_user');
            $table->index(['restaurant_id', 'status'], 'restaurant_user_by_restaurant');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('restaurant_user');
    }
};
