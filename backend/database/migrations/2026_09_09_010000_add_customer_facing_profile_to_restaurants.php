<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The two customer-facing profile fields Module 09 needs and Module 07 had no
 * use for.
 *
 * Both are deliberately separate from the private columns beside them.
 *
 * `description` is the operator's own words about their business, written for
 * customers. It is not marketing copy this platform generates, and it is not
 * derived from anything: a restaurant with nothing to say gets no description
 * section rather than a sentence somebody invented for it.
 *
 * `public_phone` is a **business** number the operator has chosen to publish.
 * It is not `owner_phone`, which is how the platform reaches the owner and is
 * on the private list. Two columns rather than one flag, because a single
 * "phone" with a visibility boolean is one forgotten `where` clause away from
 * publishing somebody's personal mobile.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('restaurants', function (Blueprint $table): void {
            $table->text('description')->nullable()->after('display_name');

            $table->string('public_phone', 32)->nullable()->after('owner_email');
        });
    }

    public function down(): void
    {
        Schema::table('restaurants', function (Blueprint $table): void {
            $table->dropColumn(['description', 'public_phone']);
        });
    }
};
