<?php

declare(strict_types=1);

namespace App\Models;

use App\Enums\CartStatus;
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

    /** Records that the customer did something, and pushes the expiry out. */
    public function touchActivity(): void
    {
        $ttl = (int) config('foodonthego.cart.ttl_seconds');

        $this->forceFill([
            'last_activity_at' => now(),
            'expires_at' => now()->addSeconds($ttl),
        ])->save();
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
