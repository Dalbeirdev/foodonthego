<?php

declare(strict_types=1);

namespace App\Models;

use App\Enums\OrderStatus;
use App\Enums\PaymentStatus;
use App\Models\Concerns\BelongsToTenant;
use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Support\Str;

/**
 * What a customer committed to buy, at a price that no longer moves.
 *
 * Empty `$fillable`, like every other model here. An order's customer,
 * restaurant, amounts and status are decided by the service that writes it from
 * a quote the server itself produced. There is no path by which a number from a
 * request body reaches a column on this table, and that is the single most
 * important property of this class.
 *
 * Tenanted through `BelongsToTenant`: an order belongs to a restaurant, and a
 * restaurant is a tenant. Operators reach orders only for restaurants they are
 * assigned to, filtered in the query.
 */
final class Order extends Model
{
    use BelongsToTenant;

    /** @var list<string> */
    protected $fillable = [];

    /** @return array<string, string> */
    protected function casts(): array
    {
        return [
            'status' => OrderStatus::class,
            'pickup_start_at' => 'immutable_datetime',
            'pickup_end_at' => 'immutable_datetime',
            'placed_at' => 'immutable_datetime',
            'paid_at' => 'immutable_datetime',
            'cancelled_at' => 'immutable_datetime',
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
        self::creating(static function (self $order): void {
            $order->uuid ??= (string) Str::uuid();
            $order->order_number ??= self::mintOrderNumber();
        });
    }

    /**
     * A number a customer can read out loud.
     *
     * Date prefix plus ten random base-32 characters, uppercase, with the
     * letters that get misheard or mistyped removed — no I, L, O or U. Not
     * sequential: a sequential order number tells anybody who has one roughly
     * how many orders the platform has taken, and lets them guess their
     * neighbours.
     *
     * Uniqueness is the column's unique index; this only has to make a
     * collision unlikely enough that the retry never happens in practice.
     */
    public static function mintOrderNumber(?CarbonImmutable $now = null): string
    {
        $alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
        $suffix = '';

        for ($i = 0; $i < 10; $i++) {
            $suffix .= $alphabet[random_int(0, 31)];
        }

        return ($now ?? CarbonImmutable::now())->format('ymd').'-'.$suffix;
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

    /** @return BelongsTo<Restaurant, $this> */
    public function restaurant(): BelongsTo
    {
        return $this->belongsTo(Restaurant::class);
    }

    /** @return BelongsTo<Trip, $this> */
    public function trip(): BelongsTo
    {
        return $this->belongsTo(Trip::class);
    }

    /** @return BelongsTo<CheckoutQuote, $this> */
    public function checkoutQuote(): BelongsTo
    {
        return $this->belongsTo(CheckoutQuote::class);
    }

    /** @return HasMany<OrderItem, $this> */
    public function items(): HasMany
    {
        return $this->hasMany(OrderItem::class)->orderBy('display_order')->orderBy('id');
    }

    /** @return HasMany<Payment, $this> */
    public function payments(): HasMany
    {
        return $this->hasMany(Payment::class);
    }

    /**
     * The attempt that settled this order, if one did.
     *
     * Deliberately looked up by status rather than by "the most recent one". The
     * latest attempt on a paid order is not necessarily the one that paid it —
     * a duplicate delivery or a retried callback can write a newer row — and
     * "which attempt settled this" has exactly one right answer.
     */
    public function settledPayment(): ?Payment
    {
        return $this->payments()
            ->where('status', PaymentStatus::Captured->value)
            ->orderBy('id')
            ->first();
    }

    public function isPaid(): bool
    {
        return $this->status === OrderStatus::Paid;
    }
}
