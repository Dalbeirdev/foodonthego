<?php

declare(strict_types=1);

namespace App\Models;

use App\Enums\OrderStatus;
use App\Enums\OrderTransitionSource;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Str;

/**
 * One thing that happened to an order, written once and never again.
 *
 * APPEND ONLY. There is no update path in this class and no service that edits
 * a row after writing it. A timeline whose past can be rewritten is not an
 * audit trail — it is a display cache with extra steps — and the whole reason
 * this table exists is to answer "when was this order accepted, and who says
 * so" months later, against a dispute.
 *
 * Correcting a wrong row is therefore not an UPDATE. It would be a privileged,
 * separately authorised workflow that appends a correction, and no such
 * workflow exists.
 */
final class OrderStatusHistory extends Model
{
    protected $table = 'order_status_history';

    /**
     * Empty, like every model here.
     *
     * Nothing about a status change comes from a request body: the statuses
     * come from the state machine, the actor from the authenticated principal,
     * and the time from the server's clock.
     *
     * @var list<string>
     */
    protected $fillable = [];

    protected static function booted(): void
    {
        self::creating(static function (self $entry): void {
            $entry->uuid ??= (string) Str::uuid();
        });
    }

    /** @return array<string, string> */
    protected function casts(): array
    {
        return [
            'from_status' => OrderStatus::class,
            'to_status' => OrderStatus::class,
            'source_type' => OrderTransitionSource::class,
            'occurred_at' => 'immutable_datetime',
        ];
    }

    /** @return BelongsTo<Order, $this> */
    public function order(): BelongsTo
    {
        return $this->belongsTo(Order::class);
    }
}
