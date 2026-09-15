<?php

declare(strict_types=1);

namespace App\Models;

use App\Services\Routing\RouteCalculationService;
use App\Services\Routing\RouteOption;
use App\Support\Trip\EndpointFingerprint;
use Carbon\CarbonImmutable;
use Database\Factories\TripRouteFactory;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Str;

/**
 * One route option calculated for a trip.
 *
 * Nothing is fillable. Every value here comes from a routing provider by way of
 * {@see RouteCalculationService}, and there is no request in which a customer
 * supplies a distance, a duration, a polyline or a selection flag. An empty
 * `$fillable` is the strongest statement of that: a body containing
 * `distance_meters` has nowhere to land even if a future caller passes the whole
 * array through.
 */
final class TripRoute extends Model
{
    /** @use HasFactory<TripRouteFactory> */
    use HasFactory;

    /** @var list<string> */
    protected $fillable = [];

    protected function casts(): array
    {
        return [
            'distance_meters' => 'integer',
            'duration_seconds' => 'integer',
            'traffic_duration_seconds' => 'integer',
            'provider_route_index' => 'integer',
            'is_recommended' => 'boolean',
            'is_selected' => 'boolean',
            'calculated_at' => 'immutable_datetime',
            // Strings, like the trip's own coordinates: a bound that round-trips
            // through a float loses its last place, and the camera that frames a
            // route is the poorer for it.
            'bounds_north' => 'string',
            'bounds_south' => 'string',
            'bounds_east' => 'string',
            'bounds_west' => 'string',
        ];
    }

    protected static function booted(): void
    {
        self::creating(static function (self $route): void {
            $route->uuid ??= (string) Str::uuid();
        });
    }

    public function getRouteKeyName(): string
    {
        return 'uuid';
    }

    /** @return BelongsTo<Trip, $this> */
    public function trip(): BelongsTo
    {
        return $this->belongsTo(Trip::class);
    }

    /** @param  Builder<self>  $query */
    public function scopeForTrip(Builder $query, Trip $trip): Builder
    {
        return $query->where('trip_id', $trip->getKey());
    }

    /** Provider order: the recommended route first. */
    public function scopeInProviderOrder(Builder $query): Builder
    {
        return $query->orderBy('provider_route_index');
    }

    /**
     * How much longer traffic is making this route.
     *
     * Null when there is no traffic-aware figure, and never negative — see
     * {@see RouteOption::trafficDelaySeconds()} for why a
     * negative delay is a comparison of two different assumptions rather than a
     * time saving.
     */
    public function trafficDelaySeconds(): ?int
    {
        if ($this->traffic_duration_seconds === null) {
            return null;
        }

        $delay = $this->traffic_duration_seconds - $this->duration_seconds;

        return $delay > 0 ? $delay : null;
    }

    /**
     * Whether this route still describes the journey the trip currently
     * describes.
     */
    public function matchesEndpointsOf(Trip $trip): bool
    {
        return hash_equals(
            $this->endpoints_fingerprint,
            EndpointFingerprint::of($trip),
        );
    }

    public function calculatedAt(): ?CarbonImmutable
    {
        return $this->calculated_at;
    }

    /**
     * The compact shape, for a list.
     *
     * No geometry. A trips list showing ten journeys does not need ten
     * polylines, and sending them would make the cheapest screen in the app the
     * heaviest response it fetches.
     *
     * @return array<string, mixed>
     */
    public function toApiSummaryArray(): array
    {
        return [
            'route_id' => $this->uuid,
            'summary' => $this->summary,
            'distance_meters' => $this->distance_meters,
            'duration_seconds' => $this->duration_seconds,
            'traffic_duration_seconds' => $this->traffic_duration_seconds,
            'traffic_delay_seconds' => $this->trafficDelaySeconds(),
            'calculated_at' => $this->calculated_at?->toIso8601String(),
        ];
    }

    /**
     * The API shape — an explicit allow-list, not `toArray()`.
     *
     * `trip_id`, the auto-increment key and the generated `selected_trip_id`
     * column never appear.
     *
     * Units are what this method is careful about. `distance_meters` and
     * `duration_seconds` go out as the integers they are stored as; nothing is
     * pre-formatted into "278 km" here, because a client that is handed a string
     * cannot show miles, cannot sum two legs, and cannot re-render in another
     * language.
     *
     * @return array<string, mixed>
     */
    public function toApiArray(): array
    {
        return [
            'route_id' => $this->uuid,
            'provider' => $this->provider,
            'provider_route_index' => $this->provider_route_index,
            'summary' => $this->summary,
            'distance_meters' => $this->distance_meters,
            'duration_seconds' => $this->duration_seconds,
            'traffic_duration_seconds' => $this->traffic_duration_seconds,
            'traffic_delay_seconds' => $this->trafficDelaySeconds(),
            'encoded_polyline' => $this->encoded_polyline,
            'bounds' => [
                'north' => $this->bounds_north,
                'south' => $this->bounds_south,
                'east' => $this->bounds_east,
                'west' => $this->bounds_west,
            ],
            'is_recommended' => $this->is_recommended,
            'is_selected' => $this->is_selected,
            'calculated_at' => $this->calculated_at?->toIso8601String(),
        ];
    }
}
