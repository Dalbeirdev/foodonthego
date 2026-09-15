<?php

declare(strict_types=1);

namespace App\Models;

use App\Enums\OrderStatus;
use App\Enums\PaymentStatus;
use App\Models\Concerns\BelongsToTenant;
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

            // Module 17. One per fulfilment state, so a timeline can be read
            // off this row without joining the history table -- and so a
            // status with no matching timestamp is a detectable fault.
            'accepted_at' => 'immutable_datetime',
            'rejected_at' => 'immutable_datetime',
            'cooking_started_at' => 'immutable_datetime',
            'ready_at' => 'immutable_datetime',
            'picked_up_at' => 'immutable_datetime',
            'order_version' => 'integer',

            // Module 16. The expiry was missing a cast and reached the
            // presenter as a raw string, where ->toIso8601String() is a fatal
            // error rather than a wrong value — which is the good kind of bug,
            // and the reason the credential endpoint failed loudly on its first
            // run instead of quietly serving an unparseable date.
            'pickup_token_expires_at' => 'immutable_datetime',
            'pickup_credential_version' => 'integer',
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

            // The order number is NOT minted here any more.
            //
            // A row created at checkout is a payment target, and a payment
            // target has no number because there is nothing yet for a customer
            // to read out. CreateOrderFromCapturedPayment mints it at the
            // moment the money is captured, which is the moment the row becomes
            // an order. Minting it here would put a customer-facing number on
            // every abandoned checkout.
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

    /** @return BelongsTo<Cart, $this> */
    public function cart(): BelongsTo
    {
        return $this->belongsTo(Cart::class);
    }

    /**
     * The captured payment this order was placed from.
     *
     * Unique at the database level: this column is the one-payment-one-order
     * invariant, not a convenience.
     *
     * @return BelongsTo<Payment, $this>
     */
    public function placedFromPayment(): BelongsTo
    {
        return $this->belongsTo(Payment::class, 'placed_from_payment_id');
    }

    /**
     * Everything that has happened to this order, oldest first.
     *
     * Ordered by occurred_at and then id, never by occurred_at alone: two
     * transitions can land inside the same second, and which of them a
     * customer sees first must not be up to the storage engine.
     *
     * @return HasMany<OrderStatusHistory, $this>
     */
    public function statusHistory(): HasMany
    {
        return $this->hasMany(OrderStatusHistory::class)
            ->orderBy('occurred_at')
            ->orderBy('id');
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

    /**
     * Whether this is a placed order rather than a payment target.
     *
     * Renamed from isPaid() in Module 16, because the old name asked a question
     * about money of a record that no longer answers it. "Has the customer
     * paid" is now read from the payment; this asks whether an order exists.
     */
    public function isPlaced(): bool
    {
        return $this->status === OrderStatus::Placed;
    }
}
