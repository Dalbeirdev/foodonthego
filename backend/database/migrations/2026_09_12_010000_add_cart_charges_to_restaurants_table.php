<?php

declare(strict_types=1);

/**
 * What a restaurant adds to a cart's subtotal.
 *
 * Both columns are the restaurant's to set and both default to **nothing**. A
 * platform that invents a packaging fee is charging a customer money that no
 * restaurant asked for, and a tax rate guessed in a migration is a wrong number
 * that looks exactly like a right one — it reads as correct, it survives review
 * because it is the figure everyone expects, and it ships.
 *
 * `tax_rate_bps` is nullable rather than zero-defaulted, because null and zero
 * mean different things here: null is "this restaurant has not been configured,
 * use the platform default", and zero is "this restaurant is deliberately not
 * taxed". Collapsing them would make an unconfigured restaurant indistinguishable
 * from a tax-exempt one.
 *
 * Basis points, so a rate is an integer and no float touches money.
 */

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('restaurants', function (Blueprint $table): void {
            $table->unsignedSmallInteger('tax_rate_bps')
                ->nullable()
                ->after('is_accepting_orders');

            $table->unsignedInteger('packaging_fee_minor')
                ->default(0)
                ->after('tax_rate_bps');
        });
    }

    public function down(): void
    {
        Schema::table('restaurants', function (Blueprint $table): void {
            $table->dropColumn(['tax_rate_bps', 'packaging_fee_minor']);
        });
    }
};
