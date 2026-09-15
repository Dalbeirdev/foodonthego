<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * What a platform role may reach, said out loud.
 *
 * A super administrator may work across tenants. That breadth is **not** an
 * implicit consequence of the role string: it is a row, and with no row a super
 * administrator reaches no tenant at all.
 *
 * That default is the whole point. "Super admin can see everything" is the
 * sentence that turns one compromised platform account into every restaurant's
 * data, and it is usually true by omission rather than by decision. Here the
 * omission denies.
 *
 * Two shapes:
 *
 *  - `scope = 'all'`, `restaurant_id` NULL — every tenant, present and future.
 *    Genuinely needed by somebody, rarely by many.
 *  - `scope = 'restaurant'`, `restaurant_id` set — one named tenant, which is
 *    what a support agent looking into one complaint should have.
 *
 * Granting is an admin-module concern and there is no endpoint for it here. This
 * table exists now because the authorisation layer must consult *something*, and
 * a hard-coded `if super_admin then true` would be exactly the implicit rule the
 * requirement forbids.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('platform_tenant_grants', function (Blueprint $table): void {
            $table->id();
            $table->uuid()->unique();

            $table->foreignId('user_id')->constrained()->cascadeOnDelete();

            // 'all' | 'restaurant'.
            $table->string('scope', 20);

            // Null when the scope is 'all'. Set, and enforced, when it is not.
            $table->foreignId('restaurant_id')->nullable()->constrained()->cascadeOnDelete();

            // What the grant permits, as a TenantRole: a support agent reading a
            // complaint needs 'staff', not 'owner'. Breadth and depth are
            // separate decisions and this column is the depth.
            $table->string('tenant_role', 20);

            $table->string('status', 20)->default('active');

            $table->foreignId('granted_by_user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('granted_at')->nullable();
            $table->timestamp('revoked_at')->nullable();
            $table->timestamps();

            $table->index(['user_id', 'status'], 'platform_grants_by_user');
            $table->index(['restaurant_id', 'status'], 'platform_grants_by_restaurant');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('platform_tenant_grants');
    }
};
