<?php

declare(strict_types=1);

use App\Enums\RestaurantStatus;
use App\Enums\RestaurantVerificationStatus;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The restaurants a customer can be shown along a route.
 *
 * This is deliberately the *discovery* foundation and not the restaurant
 * product. It carries what deciding "may this restaurant appear, and where is
 * it" needs, plus the small amount of preview metadata a card shows. Menus,
 * pricing, staff, settlements and the operator dashboard belong to the modules
 * that own them; creating their columns now would fix decisions before the
 * features that depend on them are understood.
 *
 * Three columns that look redundant and are not. `status` is the commercial
 * standing, `verification_status` is the compliance outcome, and
 * `is_discoverable` is the switch. They disagree in practice — a verified
 * restaurant can be suspended, an approved one can be switched off while it
 * rebuilds its menu — and collapsing them into one "active" flag would mean the
 * reason a restaurant is invisible is guessed rather than recorded.
 *
 * The private columns at the bottom are here on purpose. A privacy test that
 * asserts a response contains no owner phone number proves nothing if no owner
 * phone number exists to leak.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('restaurants', function (Blueprint $table): void {
            $table->id();
            $table->uuid()->unique();

            $table->string('name', 160);

            // A shorter name for a marker label or a narrow card. Null means
            // "use the real name" rather than "this restaurant has no name".
            $table->string('display_name', 60)->nullable();

            // --- where it is -------------------------------------------------
            //
            // Nullable, and that nullability is a rule rather than an oversight:
            // a restaurant whose coordinates have not been established is not
            // route-discoverable. Deriving a point from the address text would
            // put a marker on a map, and a customer in a field.
            //
            // DECIMAL(10,7) is ~11mm at the equator and matches `trips` and
            // `customer_addresses`, so a coordinate means the same thing
            // wherever it is stored. These two columns are the single source of
            // truth for position: there is no parallel POINT column to drift.
            $table->decimal('latitude', 10, 7)->nullable();
            $table->decimal('longitude', 10, 7)->nullable();

            $table->string('formatted_address', 400);
            $table->string('city', 120);
            $table->string('region', 120)->nullable();
            $table->char('country_code', 2)->default('IN');
            $table->string('postal_code', 16)->nullable();

            // The restaurant's own clock. Stored rather than assumed, because
            // "open" is a statement about local time and a pilot that is
            // entirely Asia/Kolkata today is not one for ever. Never the
            // device's timezone: a traveller crossing a boundary would watch
            // restaurants open and close as their phone caught up.
            $table->string('timezone', 64)->default('Asia/Kolkata');

            // --- may a customer see it ---------------------------------------
            $table->enum('status', RestaurantStatus::values())
                ->default(RestaurantStatus::Draft->value);

            $table->enum('verification_status', RestaurantVerificationStatus::values())
                ->default(RestaurantVerificationStatus::Pending->value);

            // The customer-facing switch, owned by the operator.
            $table->boolean('is_discoverable')->default(false);

            // Temporary pause. Distinct from opening hours: the doors are open
            // and the kitchen is not taking work.
            $table->boolean('is_accepting_orders')->default(true);

            // --- preview metadata --------------------------------------------
            //
            // All nullable, because Module 07 must be able to say "we do not
            // know" rather than print a plausible number. There is no reviews
            // module yet, so `rating_average` is null on every real row and the
            // card shows nothing where a rating would go.
            $table->unsignedTinyInteger('price_level')->nullable();
            $table->decimal('rating_average', 2, 1)->nullable();
            $table->unsignedInteger('rating_count')->default(0);

            $table->string('logo_url', 500)->nullable();
            $table->string('cover_image_url', 500)->nullable();

            // Metadata only. Module 07 must not add this to a travel time and
            // call the result a pickup time — that combination is the ETA
            // engine's, and inventing it here would be a promise nobody checked.
            $table->unsignedSmallInteger('default_preparation_minutes')->nullable();

            // --- not for customers -------------------------------------------
            //
            // Present so the privacy tests have something to fail on, and
            // because discovery has to be safe against the shape the real
            // restaurant module will have rather than against a table that
            // happens to hold nothing sensitive yet.
            $table->string('owner_name', 160)->nullable();
            $table->string('owner_phone', 20)->nullable();
            $table->string('owner_email', 255)->nullable();
            $table->string('tax_identifier', 32)->nullable();
            $table->string('bank_account_reference', 64)->nullable();
            $table->decimal('commission_rate', 5, 2)->nullable();
            $table->text('internal_notes')->nullable();

            $table->timestamps();
            $table->softDeletes();

            // --- indexes ------------------------------------------------------
            //
            // Two, for the two halves of the candidate query, and no more.
            //
            // The corridor search is a latitude/longitude range over the route's
            // bounding boxes, and latitude is the selective half of it: a
            // Delhi-Jaipur corridor is about three degrees of latitude out of
            // the thirty India spans. Leading with it lets MySQL range-scan
            // rather than read the table.
            $table->index(['latitude', 'longitude'], 'restaurants_position_index');

            // And the eligibility filter, which every discovery query applies
            // and which is the same three columns every time.
            $table->index(
                ['status', 'verification_status', 'is_discoverable'],
                'restaurants_discoverable_index',
            );
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('restaurants');
    }
};
