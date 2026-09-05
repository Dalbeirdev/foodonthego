<?php

declare(strict_types=1);

namespace App\Models;

use App\Enums\CartStatus;
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
}
