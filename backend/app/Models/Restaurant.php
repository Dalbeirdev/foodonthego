<?php

declare(strict_types=1);

namespace App\Models;

use App\Enums\RestaurantStatus;
use App\Enums\RestaurantVerificationStatus;
use App\Services\Discovery\RestaurantDiscoveryEligibilityService;
use Database\Factories\RestaurantFactory;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;
use Illuminate\Support\Collection;
use Illuminate\Support\Str;

/**
 * A restaurant, as much of one as route discovery needs.
 *
 * Nothing is fillable. Every column here is either operator-owned (and will be
 * written by the restaurant module through explicit assignment) or
 * platform-owned; none of it comes from a customer request, and a customer
 * endpoint that could mass-assign `status` would be a way to make a suspended
 * restaurant visible again.
 *
 * The API shape is deliberately built by hand in {@see toDiscoveryArray()}
 * rather than by hiding columns. `$hidden` is a deny-list, and a deny-list means
 * the column somebody adds next month is exposed until they remember to hide
 * it. An allow-list means it is invisible until somebody decides otherwise.
 */
final class Restaurant extends Model
{
    /** @use HasFactory<RestaurantFactory> */
    use HasFactory, SoftDeletes;

    /** @var list<string> */
    protected $fillable = [];

    protected function casts(): array
    {
        return [
            'status' => RestaurantStatus::class,
            'verification_status' => RestaurantVerificationStatus::class,
            'is_discoverable' => 'boolean',
            'is_accepting_orders' => 'boolean',
            'price_level' => 'integer',
            'rating_count' => 'integer',
            'default_preparation_minutes' => 'integer',
            // Strings, like every other coordinate in this schema: a decimal
            // that round-trips through a float loses its last place, and the
            // last place is a metre.
            'latitude' => 'string',
            'longitude' => 'string',
            'rating_average' => 'string',
        ];
    }

    protected static function booted(): void
    {
        self::creating(static function (self $restaurant): void {
            $restaurant->uuid ??= (string) Str::uuid();
        });
    }

    public function getRouteKeyName(): string
    {
        return 'uuid';
    }

    /** @return HasMany<RestaurantCuisine, $this> */
    public function cuisines(): HasMany
    {
        return $this->hasMany(RestaurantCuisine::class)->orderBy('position');
    }

    /** @return HasMany<RestaurantFacility, $this> */
    public function facilities(): HasMany
    {
        return $this->hasMany(RestaurantFacility::class)->orderBy('position');
    }

    /**
     * Customer-visible photographs, in the operator's order.
     *
     * Scoped to active rows at the relation, so nothing downstream has to
     * remember: a query that forgets `->visible()` still cannot reach an
     * unmoderated image.
     *
     * @return HasMany<RestaurantMedia, $this>
     */
    public function media(): HasMany
    {
        return $this->hasMany(RestaurantMedia::class)
            ->where('is_active', true)
            ->orderBy('position')
            ->orderBy('id');
    }

    /**
     * The menu sections a customer may see, in the operator's order.
     *
     * @return HasMany<MenuCategory, $this>
     */
    public function menuCategories(): HasMany
    {
        return $this->hasMany(MenuCategory::class)
            ->where('is_active', true)
            ->orderBy('display_order')
            ->orderBy('id');
    }

    /** @return HasMany<RestaurantOpeningHour, $this> */
    public function openingHours(): HasMany
    {
        return $this->hasMany(RestaurantOpeningHour::class)->orderBy('opens_at');
    }

    /**
     * Restaurants a customer is permitted to see, by the three columns alone.
     *
     * The full rule lives in {@see RestaurantDiscoveryEligibilityService},
     * which is the only thing that should decide eligibility. This scope exists
     * so the decision can also be pushed into SQL — a corridor query that pulls
     * suspended restaurants back and filters them in PHP has still read them,
     * and on a national dataset that is the difference between an index range
     * scan and most of the table.
     *
     * @param  Builder<Restaurant>  $query
     */
    public function scopeDiscoverable(Builder $query): void
    {
        $query->where('status', RestaurantStatus::Approved)
            ->where('verification_status', RestaurantVerificationStatus::Verified)
            ->where('is_discoverable', true)
            ->whereNotNull('latitude')
            ->whereNotNull('longitude');
    }

    /**
     * Inside a latitude/longitude box.
     *
     * The cheap half of the two-stage corridor search. A box is not a corridor —
     * it over-selects at the corners — but it is the shape an index can answer,
     * and the exact point-to-polyline distance then rejects what the box let
     * through.
     *
     * @param  Builder<Restaurant>  $query
     */
    public function scopeWithinBox(
        Builder $query,
        float $south,
        float $west,
        float $north,
        float $east,
    ): void {
        $query->whereBetween('latitude', [$south, $north])
            ->whereBetween('longitude', [$west, $east]);
    }

    public function hasPosition(): bool
    {
        return $this->latitude !== null && $this->longitude !== null;
    }

    /** The name a marker or a narrow card should use. */
    public function shortName(): string
    {
        return $this->display_name ?: $this->name;
    }

    /** @return list<string> */
    public function cuisineNames(): array
    {
        return $this->cuisines->pluck('cuisine')->values()->all();
    }

    /** @return list<string> */
    public function facilityNames(): array
    {
        return $this->facilities->pluck('facility')->values()->all();
    }

    /**
     * The customer-safe shape.
     *
     * Written out by hand, one key at a time. Everything absent from this list
     * is absent from the API — owner contact details, tax and bank references,
     * the commission rate, internal notes — and it stays absent when somebody
     * adds a column, because adding a column does not add a line here.
     *
     * `rating` is null until there is a reviews module. It is not a zero and it
     * is not a hopeful 4.5: the card renders nothing where a rating would go.
     *
     * @return array<string, mixed>
     */
    public function toDiscoveryArray(): array
    {
        return [
            'id' => $this->uuid,
            'name' => $this->name,
            'short_name' => $this->shortName(),
            'location' => [
                'latitude' => $this->latitude,
                'longitude' => $this->longitude,
            ],
            'city' => $this->city,
            'formatted_address' => $this->formatted_address,
            'cuisines' => $this->cuisineNames(),
            'facilities' => $this->facilityNames(),
            'price_level' => $this->price_level,
            'rating' => $this->rating_average,
            'review_count' => $this->rating_count > 0 ? $this->rating_count : null,
            'logo_url' => $this->logo_url,
            'cover_image_url' => $this->cover_image_url,
        ];
    }

    /**
     * The columns a customer must never receive.
     *
     * Named here, next to the shape that excludes them, so the privacy test can
     * assert against one list rather than against a tester's memory.
     *
     * @return Collection<int, string>
     */
    public static function privateColumns(): Collection
    {
        return collect([
            'owner_name',
            'owner_phone',
            'owner_email',
            'tax_identifier',
            'bank_account_reference',
            'commission_rate',
            'internal_notes',
        ]);
    }
}
