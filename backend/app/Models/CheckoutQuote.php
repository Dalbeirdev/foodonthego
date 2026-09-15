<?php

declare(strict_types=1);

namespace App\Models;

use App\Enums\CheckoutQuoteStatus;
use App\Support\Checkout\CheckoutFingerprint;
use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Str;

/**
 * What the server offered, at what price, for how long.
 *
 * Empty `$fillable`, like every other model here: a quote's customer, cart,
 * amounts and fingerprint are decided by the service that writes it from
 * validated state, never by a request body. There is no path by which a number
 * from a client reaches a column on this table.
 *
 * **A quote is not an order.** Module 14 creates no order, no Razorpay object
 * and no payment, and this row is not a step towards one existing — it is a
 * record of an offer that expires.
 */
final class CheckoutQuote extends Model
{
    /** @var list<string> */
    protected $fillable = [];

    /** @return array<string, string> */
    protected function casts(): array
    {
        return [
            'status' => CheckoutQuoteStatus::class,
            'cart_version' => 'integer',
            'pickup_start_at' => 'immutable_datetime',
            'pickup_end_at' => 'immutable_datetime',
            'expires_at' => 'immutable_datetime',
            'items_subtotal_minor' => 'integer',
            'tax_minor' => 'integer',
            'packaging_fee_minor' => 'integer',
            'platform_fee_minor' => 'integer',
            'discount_minor' => 'integer',
            'other_adjustment_minor' => 'integer',
            'payable_total_minor' => 'integer',
            'commercial_rule_version' => 'integer',
            'tax_configured' => 'boolean',
            'packaging_fee_configured' => 'boolean',
            'platform_fee_configured' => 'boolean',
            'discount_configured' => 'boolean',
            'other_adjustment_configured' => 'boolean',
        ];
    }

    protected static function booted(): void
    {
        self::creating(static function (self $quote): void {
            $quote->uuid ??= (string) Str::uuid();
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

    /** @return BelongsTo<Cart, $this> */
    public function cart(): BelongsTo
    {
        return $this->belongsTo(Cart::class);
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

    public function hasExpired(?CarbonImmutable $now = null): bool
    {
        return $this->expires_at !== null
            && $this->expires_at->isBefore($now ?? CarbonImmutable::now());
    }

    /**
     * What has actually become of this quote.
     *
     * Two of the four statuses are stored and two are worked out. `ACTIVE` and
     * `CONSUMED` are facts about what the server did; `EXPIRED` and `STALE` are
     * conclusions about this quote held against the world right now.
     *
     * Derived rather than written back for the reason Module 13 established for
     * pickup selections: a column reading ACTIVE after the cart changed is not
     * wrong because a job failed to run — a column cannot know. Recomputing is
     * cheap and cannot go out of date.
     *
     * Expiry is checked before staleness. "Your checkout timed out, here is a
     * fresh one" is a smaller thing to tell a customer than "your order
     * changed", and when both are true the clock is the one that ran out first.
     */
    public function effectiveStatus(Cart $cart, ?CarbonImmutable $now = null): CheckoutQuoteStatus
    {
        $stored = $this->status ?? CheckoutQuoteStatus::Active;

        if ($stored === CheckoutQuoteStatus::Consumed) {
            return CheckoutQuoteStatus::Consumed;
        }

        if ($this->hasExpired($now)) {
            return CheckoutQuoteStatus::Expired;
        }

        return hash_equals($this->fingerprint, CheckoutFingerprint::of($cart))
            ? CheckoutQuoteStatus::Active
            : CheckoutQuoteStatus::Stale;
    }
}
