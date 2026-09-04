<?php

declare(strict_types=1);

namespace App\Models;

use App\Enums\LocationSourceType;
use App\Enums\RouteStatus;
use App\Enums\TripStatus;
use App\Services\Trip\TripService;
use Carbon\CarbonImmutable;
use Database\Factories\TripFactory;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\HasOne;
use Illuminate\Support\Str;

/**
 * A trip a customer has created.
 *
 * Nothing here is fillable. Every column is written by {@see TripService} by
 * name, because the endpoint columns are *derived* from a request rather than
 * copied from one, and the two status columns are a lifecycle rather than values
 * somebody sets. An empty `$fillable` is the strongest statement of that: a
 * request body containing `status`, `route_status`, `customer_id` or
 * `distance_metres` has nowhere to land even if a future caller passes the whole
 * array through.
 */
final class Trip extends Model
{
    /** @use HasFactory<TripFactory> */
    use HasFactory;

    /** @var list<string> */
    protected $fillable = [];

    protected function casts(): array
    {
        return [
            'status' => TripStatus::class,
            'route_status' => RouteStatus::class,
            'origin_source_type' => LocationSourceType::class,
            'destination_source_type' => LocationSourceType::class,
            'cancelled_at' => 'immutable_datetime',
            // Strings, not floats. A coordinate that round-trips through a float
            // loses its last place, and the last place of a coordinate is metres
            // — which is the unit the same-location rule works in.
            'origin_latitude' => 'string',
            'origin_longitude' => 'string',
            'destination_latitude' => 'string',
            'destination_longitude' => 'string',
        ];
    }

    protected static function booted(): void
    {
        self::creating(static function (self $trip): void {
            $trip->uuid ??= (string) Str::uuid();
        });
    }

    public function getRouteKeyName(): string
    {
        return 'uuid';
    }

    /** @return BelongsTo<User, $this> */
    public function customer(): BelongsTo
    {
        return $this->belongsTo(User::class, 'customer_id');
    }

    /** @return HasMany<TripRoute, $this> */
    public function routes(): HasMany
    {
        return $this->hasMany(TripRoute::class);
    }

    /**
     * The chosen route, if there is one.
     *
     * A `HasOne` over a flag the database itself keeps unique — see the
     * `trip_routes_one_selected_per_trip` index — so "the selected route" is
     * genuinely singular rather than "the first of however many got selected".
     *
     * @return HasOne<TripRoute, $this>
     */
    public function selectedRoute(): HasOne
    {
        return $this->hasOne(TripRoute::class)->where('is_selected', true);
    }

    /** @param  Builder<self>  $query */
    public function scopeOwnedBy(Builder $query, User $customer): Builder
    {
        return $query->where('customer_id', $customer->getKey());
    }

    /**
     * Newest first. Deliberately deterministic: a list that reorders between two
     * loads makes people tap the wrong row.
     *
     * @param  Builder<self>  $query
     */
    public function scopeNewestFirst(Builder $query): Builder
    {
        return $query->orderByDesc('id');
    }

    /** @param  Builder<self>  $query */
    public function scopeActive(Builder $query): Builder
    {
        return $query->where('status', TripStatus::RoutePending);
    }

    public function isCancelled(): bool
    {
        return $this->status === TripStatus::Cancelled;
    }

    /** Whether the owner can still discard this trip. */
    public function isDiscardable(): bool
    {
        return $this->status->isOpen();
    }

    /**
     * The API shape — an explicit allow-list, not `toArray()`.
     *
     * `customer_id`, the two `*_saved_address_id` columns and the auto-increment
     * key never appear. The address ids in particular would leak the existence
     * and identity of saved-address rows into a payload that has no use for them.
     *
     * There are no distance, duration, polyline or ETA keys **on the trip
     * itself**, because there are no such columns. What a client may find here
     * from Module 06 onwards is `selected_route`: a summary of the route the
     * customer chose, present only when one has genuinely been calculated for
     * *these* endpoints. A client that finds null cannot render an estimate.
     *
     * @return array<string, mixed>
     */
    public function toApiArray(): array
    {
        return [
            'id' => $this->uuid,
            'status' => $this->status->value,
            'route_status' => $this->route_status->value,
            'origin' => $this->endpointArray('origin'),
            'destination' => $this->endpointArray('destination'),
            'cancelled_at' => $this->cancelled_at?->toIso8601String(),
            'created_at' => $this->created_at?->toIso8601String(),
            'updated_at' => $this->updated_at?->toIso8601String(),
            'selected_route' => $this->selectedRouteSummary(),
        ];
    }

    /**
     * The chosen route's headline figures, or null.
     *
     * Two guards, and both are necessary. `route_status` must say Ready, and the
     * route's fingerprint must still match these endpoints — a route calculated
     * before an endpoint moved has real geometry for the wrong journey, and
     * putting its distance on the home screen would be the most convincing wrong
     * number this product could show.
     *
     * @return array<string, mixed>|null
     */
    private function selectedRouteSummary(): ?array
    {
        if (! $this->route_status->hasUsableRoute() || ! $this->relationLoaded('selectedRoute')) {
            return null;
        }

        $route = $this->selectedRoute;

        return $route !== null && $route->matchesEndpointsOf($this)
            ? $route->toApiSummaryArray()
            : null;
    }

    /** @return array<string, mixed> */
    private function endpointArray(string $prefix): array
    {
        return [
            'source_type' => $this->{"{$prefix}_source_type"}->value,
            'display_name' => $this->{"{$prefix}_name"},
            'formatted_address' => $this->{"{$prefix}_formatted_address"},
            'latitude' => $this->{"{$prefix}_latitude"},
            'longitude' => $this->{"{$prefix}_longitude"},
            'place_id' => $this->{"{$prefix}_place_id"},
            'city' => $this->{"{$prefix}_city"},
            'region' => $this->{"{$prefix}_region"},
            'country_code' => $this->{"{$prefix}_country_code"},
            'postal_code' => $this->{"{$prefix}_postal_code"},
        ];
    }

    public function cancelledAtOrNull(): ?CarbonImmutable
    {
        return $this->cancelled_at;
    }
}
