<?php

declare(strict_types=1);

namespace App\Models;

use App\Enums\TripStatus;
use App\Services\Trip\TripService;
use Carbon\CarbonImmutable;
use Database\Factories\TripFactory;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Str;

/**
 * A journey a customer has planned.
 *
 * Nothing here is fillable. Every column is written by {@see TripService} by
 * name, because the endpoint columns are derived from a request rather than
 * copied from one, and the status columns are a lifecycle rather than a value
 * somebody sets. An empty `$fillable` is the strongest statement of that: a
 * request body containing `status`, `customer_id` or `cancelled_at` has nowhere
 * to land even if a future caller passes the whole array in.
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
            'departure_at' => 'immutable_datetime',
            'expected_arrival_at' => 'immutable_datetime',
            'cancelled_at' => 'immutable_datetime',
            'traveller_count' => 'integer',
            // Strings, for the same reason as a saved address: a coordinate that
            // round-trips through a float loses its last place, and this pair is
            // what Module 09 will build a corridor from.
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

    /** @param  Builder<self>  $query */
    public function scopeOwnedBy(Builder $query, User $customer): Builder
    {
        return $query->where('customer_id', $customer->getKey());
    }

    /**
     * Journeys still ahead of the traveller: planned, and not yet departed.
     *
     * @param  Builder<self>  $query
     */
    public function scopeUpcoming(Builder $query, CarbonImmutable $now): Builder
    {
        return $query
            ->where('status', TripStatus::Planned)
            ->where('departure_at', '>=', $now)
            ->orderBy('departure_at');
    }

    /**
     * Journeys behind the traveller: departure has passed, cancelled or not.
     *
     * A cancelled journey whose departure is still ahead is in neither list. It
     * is not upcoming — nobody is going — and calling it past would be a lie
     * about a date. It is reachable by its own scope and by its id.
     *
     * @param  Builder<self>  $query
     */
    public function scopePast(Builder $query, CarbonImmutable $now): Builder
    {
        return $query
            ->where('departure_at', '<', $now)
            ->orderByDesc('departure_at');
    }

    /** @param  Builder<self>  $query */
    public function scopeCancelled(Builder $query): Builder
    {
        return $query->where('status', TripStatus::Cancelled)->orderByDesc('departure_at');
    }

    public function isCancelled(): bool
    {
        return $this->status === TripStatus::Cancelled;
    }

    public function hasDeparted(CarbonImmutable $now): bool
    {
        return $this->departure_at !== null && $this->departure_at->lessThan($now);
    }

    /**
     * Whether the owner can still change this journey.
     *
     * Two conditions, and both are about meaning rather than permission: a
     * cancelled journey is a record of a decision, and a journey whose departure
     * has passed is a record of a plan. Editing either would rewrite history that
     * a later module's orders will point at.
     */
    public function isEditable(CarbonImmutable $now): bool
    {
        return $this->status->isOpen() && ! $this->hasDeparted($now);
    }

    /**
     * The API shape — an explicit allow-list, not `toArray()`.
     *
     * `customer_id`, the two `*_address_id` columns and the auto-increment key
     * never appear: they are internal, and the address ids in particular would
     * leak the existence and identity of saved-address rows into a journey
     * payload that has no need of them.
     *
     * @return array<string, mixed>
     */
    public function toApiArray(CarbonImmutable $now): array
    {
        return [
            'id' => $this->uuid,
            'status' => $this->status->value,
            'origin' => $this->endpointArray('origin'),
            'destination' => $this->endpointArray('destination'),
            'departure_at' => $this->departure_at?->toIso8601String(),
            'expected_arrival_at' => $this->expected_arrival_at?->toIso8601String(),
            'traveller_count' => $this->traveller_count,
            'note' => $this->note,
            'cancelled_at' => $this->cancelled_at?->toIso8601String(),
            'cancellation_reason' => $this->cancellation_reason,
            // Derived, and sent rather than left to the client: "can I still edit
            // this?" is a server rule, and a client that recomputed it from the
            // clock would disagree with the server across a timezone or a slow
            // phone clock and offer an edit that is then refused.
            'is_editable' => $this->isEditable($now),
            'has_departed' => $this->hasDeparted($now),
            'created_at' => $this->created_at?->toIso8601String(),
            'updated_at' => $this->updated_at?->toIso8601String(),
        ];
    }

    /** @return array<string, mixed> */
    private function endpointArray(string $prefix): array
    {
        return [
            'label' => $this->{"{$prefix}_label"},
            'formatted_address' => $this->{"{$prefix}_formatted_address"},
            'city' => $this->{"{$prefix}_city"},
            'country_code' => $this->{"{$prefix}_country_code"},
            'latitude' => $this->{"{$prefix}_latitude"},
            'longitude' => $this->{"{$prefix}_longitude"},
            'place_id' => $this->{"{$prefix}_place_id"},
        ];
    }
}
