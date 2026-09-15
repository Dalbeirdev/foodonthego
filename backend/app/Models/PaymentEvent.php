<?php

declare(strict_types=1);

namespace App\Models;

use App\Enums\PaymentEventOutcome;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * One webhook delivery, recorded exactly once.
 *
 * `payload_digest` holds a SHA-256 of the raw body. The body itself is not
 * stored: a provider payload can carry a contact number, an email address, a
 * billing name and card metadata, and none of that is ours to keep.
 *
 * Every row here passed signature verification. Deliveries that did not are
 * logged and discarded — writing them would let anybody who can reach the public
 * endpoint claim an event id in advance and have the genuine delivery rejected
 * as a duplicate.
 */
final class PaymentEvent extends Model
{
    /** @var list<string> */
    protected $fillable = [];

    /** @return array<string, string> */
    protected function casts(): array
    {
        return [
            'outcome' => PaymentEventOutcome::class,
            'received_at' => 'immutable_datetime',
            'processed_at' => 'immutable_datetime',
        ];
    }

    /** @return BelongsTo<Order, $this> */
    public function order(): BelongsTo
    {
        return $this->belongsTo(Order::class);
    }

    /** @return BelongsTo<Payment, $this> */
    public function payment(): BelongsTo
    {
        return $this->belongsTo(Payment::class);
    }
}
