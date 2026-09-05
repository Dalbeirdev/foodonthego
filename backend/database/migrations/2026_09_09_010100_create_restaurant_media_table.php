<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Photographs of a restaurant, as customers see them.
 *
 * Module 07 stored a single `logo_url` and `cover_image_url` on the restaurant
 * row, which is enough for a list card and not enough for a detail screen. A
 * gallery is a relation, not more columns: `image_1_url` through
 * `image_5_url` is a schema that runs out.
 *
 * Two things here exist because a photograph is not just a URL.
 *
 * `alt_text` is the operator's own caption. A screen reader announcing
 * "Image 2 of 5" tells a blind customer nothing about whether they want to eat
 * here; "the terrace seating at dusk" does. It is nullable because most rows
 * will not have one, and an invented caption is worse than an honest generic.
 *
 * `is_active` is the moderation gate. Media arrives from an operator dashboard
 * a later module will build, and a photograph nobody has looked at yet must not
 * reach a customer's screen simply because it was uploaded. Defaulting to false
 * puts the mistake on the safe side.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('restaurant_media', function (Blueprint $table): void {
            $table->id();
            $table->uuid()->unique();

            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();

            // The delivery URL, not a storage path. Whatever CDN or signing
            // layer sits in front of the bucket produces this; nothing in the
            // customer API ever composes a bucket path itself.
            $table->string('url', 2048);

            // A smaller derivative for the list card and the gallery strip.
            // Null means "use the full one", which is correct rather than
            // broken on a restaurant whose images predate the resizer.
            $table->string('thumbnail_url', 2048)->nullable();

            $table->string('alt_text', 255)->nullable();

            // Intrinsic size, so the client can reserve the right box before
            // the bytes arrive and the page does not jump when they do.
            $table->unsignedSmallInteger('width')->nullable();
            $table->unsignedSmallInteger('height')->nullable();

            $table->unsignedSmallInteger('position')->default(0);

            $table->boolean('is_active')->default(false);

            $table->timestamps();

            // The customer query: this restaurant's active images, in order.
            $table->index(['restaurant_id', 'is_active', 'position'], 'restaurant_media_gallery_index');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('restaurant_media');
    }
};
