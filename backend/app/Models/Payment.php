<?php

declare(strict_types=1);

namespace App\Models;

use App\Enums\PaymentStatus;
use App\Enums\PaymentVerificationSource;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Str;

/**
 * One attempt to pay for an order.
 *
 * Empty `$fillable`. Every column here is written by the payment service from
 * either a provider response or a server-side calculation; nothing arrives from
 * a request body. In particular `amount_minor` and `status` are never taken
 * from a client, which is the whole point of the class.
 */
final class Payment extends Model
{
    /** @var list<string> */
    protected $fillable = [];

    /** @return array<string, string> */
    protected function casts(): array
    {
        return [
            'status' => PaymentStatus::class,
            'verification_source' => PaymentVerificationSource::class,
            'amount_minor' => 'integer',
            'verified_at' => 'immutable_datetime',
        ];
    }

    protected static function booted(): void
    {
        self::creating(static function (self $payment): void {
            $payment->uuid ??= (string) Str::uuid();
        });
    }

    public function getRouteKeyName(): string
    {
        return 'uuid';
    }

    /** @return BelongsTo<Order, $this> */
    public function order(): BelongsTo
    {
        return $this->belongsTo(Order::class);
    }
}
