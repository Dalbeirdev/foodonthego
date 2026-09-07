<?php

declare(strict_types=1);

namespace App\Models;

use App\Enums\CartStatus;
use App\Enums\PickupSelectionStatus;
use App\Services\Cart\CartTotals;
use App\Services\Cart\CartTotalsService;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Support\Carbon;
use Illuminate\Support\Str;

/**
 * What a customer has chosen so far, on one journey, from one restaurant.
 *
 * Empty `$fillable` like every other model here: a cart's customer, trip and
 * restaurant are decided by the service that creates it from validated context,
 * never by a request body.
 */
final class Cart extends Model
{
    /** @var list<string> */
    protected $fillable = [];

    /** @return array<string, string> */
    protected function casts(): array
    {
        return [
            'status' => CartStatus::class,
            'last_activity_at' => 'datetime',
            'expires_at' => 'datetime',
            'version' => 'integer',
            'pickup_selection_status' => PickupSelectionStatus::class,
            'requested_pickup_start_at' => 'immutable_datetime',
            'requested_pickup_end_at' => 'immutable_datetime',
            'pickup_selected_at' => 'immutable_datetime',
        ];
    }

    protected static function booted(): void
    {
        self::creating(static function (self $cart): void {
            $cart->uuid ??= (string) Str::uuid();
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

    /** @return BelongsTo<Trip, $this> */
    public function trip(): BelongsTo
    {
        return $this->belongsTo(Trip::class);
    }

    /** @return BelongsTo<Restaurant, $this> */
    public function restaurant(): BelongsTo
    {
        return $this->belongsTo(Restaurant::class);
    }

    /** @return HasMany<CartItem, $this> */
    public function items(): HasMany
    {
        return $this->hasMany(CartItem::class)->orderBy('id');
    }

    public function isActive(): bool
    {
        return $this->status === CartStatus::Active;
    }

    /**
     * Whether this cart has been left long enough to be stale.
     *
     * Nothing acts on it yet. The column is written and the question is
     * answerable, which is the foundation Module 12 needs; a scheduled job that
     * silently emptied carts before the screen explaining it existed would be
     * shipping the consequence without the explanation.
     */
    public function hasExpired(?Carbon $now = null): bool
    {
        $expiry = $this->expires_at;

        if ($expiry === null) {
            return false;
        }

        return $expiry->isBefore($now ?? now());
    }

    /**
     * Finishes with this cart, without destroying what the customer chose.
     *
     * The first thing in the project to write `CLOSED`. Module 11 created the
     * status and deliberately never used it, so that the "one active cart per
     * journey" index would have an off state to move a cart into rather than a
     * row to delete.
     *
     * Deleting would lose the record of what was chosen, and Module 13's orders
     * will point at these rows. Closing frees the index slot and keeps the
     * history, which is the whole reason the status exists.
     */
    public function close(): void
    {
        if (! $this->isActive()) {
            return;
        }

        $this->forceFill([
            'status' => CartStatus::Closed,
            'last_activity_at' => now(),
        ])->save();
    }

    /**
     * Records that the cart's CONTENTS changed, and pushes the expiry out.
     *
     * The version bump is what Module 13's pickup planning hangs on. A window
     * chosen for a cart of one quick dish is not a window that survives a slow
     * one being added, so every content change invalidates the plan — and the
     * counter is how the plan finds out.
     *
     * Deliberately a content counter rather than an activity counter. Reading
     * the cart, or a price being corrected underneath it, changes nothing about
     * how long the kitchen needs; invalidating a perfectly good pickup window
     * over either would be caution the customer experiences as breakage.
     *
     * One atomic statement — `version = version + 1` in SQL, not read-then-write
     * in PHP. Two taps that arrive together must produce two increments, and a
     * counter that can lose one is a counter that can leave a stale plan
     * looking current.
     */
    public function recordContentChange(): void
    {
        $ttl = (int) config('foodonthego.cart.ttl_seconds');

        $this->increment('version', 1, [
            'last_activity_at' => now(),
            'expires_at' => now()->addSeconds($ttl),
        ]);
    }

    /** How many individual things are in the cart, counting quantities. */
    public function itemCount(): int
    {
        return (int) $this->items->sum('quantity');
    }

    /**
     * The sum of the lines.
     *
     * Deliberately named a subtotal and never a total: there are no taxes,
     * fees, discounts or charges in this module, and calling it a total would
     * be a promise about a figure nobody has calculated yet.
     */
    public function subtotalMinor(): int
    {
        return (int) $this->items->sum('line_total_minor');
    }

    /**
     * The whole cart, as the cart screen renders it.
     *
     * The totals are passed in rather than worked out here. A model that could
     * calculate a charge is a second place charges are calculated, and the
     * whole point of {@see CartTotalsService} is that
     * there is one.
     *
     * `subtotal` is repeated at the top level as well as inside the breakdown.
     * It is redundant, and it is the field Module 11's badge already reads —
     * removing it to tidy the shape would break every client that ships today
     * to save four lines.
     *
     * @return array<string, mixed>
     */
    public function toCustomerArray(CartTotals $totals): array
    {
        return [
            'id' => $this->uuid,
            'status' => $this->status?->value,
            'trip_id' => $this->trip?->uuid,
            'restaurant_id' => $this->restaurant?->uuid,
            'restaurant_name' => $this->restaurant?->name,
            'currency' => $this->currency,
            'subtotal' => [
                'amount_minor' => $this->subtotalMinor(),
                'currency' => $this->currency,
            ],
            'items' => $this->items
                ->map(static fn (CartItem $item): array => $item->toCustomerArray())
                ->all(),
            'totals' => $totals->toApiArray(),
            'expires_at' => $this->expires_at?->toIso8601String(),
        ];
    }
}
