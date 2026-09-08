<?php

declare(strict_types=1);

/**
 * Let a restaurant say "nobody has set a packaging fee here".
 *
 * Module 12 added `tax_rate_bps` as nullable and argued the case in its own
 * migration: null is "not configured, use the platform default" and zero is
 * "deliberately not charged", and collapsing them makes an unconfigured
 * restaurant indistinguishable from an exempt one.
 *
 * `packaging_fee_minor` was added in the same migration with `default(0)` and
 * NOT NULL, so it cannot express the distinction its neighbour was given. The
 * reasoning applies identically, and the omission surfaced the moment Module 14
 * asked "is this component configured?": every restaurant answered yes, and
 * every checkout grew a "Packaging  0.00" row telling the customer a decision
 * had been made when none had.
 *
 * Existing zeroes become NULL. Nobody in this project has deliberately set a
 * packaging fee of nought -- the value is the column default on every row, which
 * is the definition of unset. A restaurant that genuinely wants to advertise
 * "no packaging charge" can be set to 0 explicitly, and it will show.
 */

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('restaurants', function (Blueprint $table): void {
            $table->unsignedInteger('packaging_fee_minor')->nullable()->default(null)->change();
        });

        DB::table('restaurants')->where('packaging_fee_minor', 0)->update([
            'packaging_fee_minor' => null,
        ]);
    }

    public function down(): void
    {
        DB::table('restaurants')->whereNull('packaging_fee_minor')->update([
            'packaging_fee_minor' => 0,
        ]);

        Schema::table('restaurants', function (Blueprint $table): void {
            $table->unsignedInteger('packaging_fee_minor')->default(0)->nullable(false)->change();
        });
    }
};
