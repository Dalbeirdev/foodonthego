<?php

declare(strict_types=1);

namespace App\Models;

use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\Date;
use Illuminate\Support\Str;

/**
 * An event that will be published, written in the transaction that made it true.
 *
 * @property string $event_id
 * @property string $event_name
 * @property string $dedupe_key
 * @property array<string, mixed> $payload
 * @property string $status
 */
final class OutboxEvent extends Model
{
    /**
     * Empty on purpose, like every model in this project. Rows here are written
     * by named code paths that know what they are writing, never by handing an
     * array from a request to create().
     */
    protected $fillable = [];

    protected function casts(): array
    {
        return [
            'payload' => 'array',
            'available_at' => 'datetime',
            'published_at' => 'datetime',
        ];
    }

    /**
     * Enqueue an event, unless the same logical event is already queued.
     *
     * Relies on the unique index over (event_name, dedupe_key) rather than a
     * read-then-write: the whole point of this table is to be correct when two
     * workers reach it at once. A duplicate insert throws, and the caller — who
     * is inside the order-creation transaction — treats that as the invariant
     * doing its job.
     *
     * PAYLOADS ARE IDENTIFIERS. A consumer that needs the basket reads the
     * order. Copying business data into this table would create a second source
     * of truth that goes stale, in a row whose entire purpose is to be shipped
     * somewhere else.
     *
     * @param  array<string, scalar>  $payload
     */
    public static function queue(
        string $eventName,
        string $dedupeKey,
        array $payload,
        ?CarbonImmutable $now = null,
    ): self {
        $now ??= Date::now()->toImmutable();

        $event = new self;
        $event->event_id = (string) Str::uuid();
        $event->event_name = $eventName;
        $event->dedupe_key = $dedupeKey;
        $event->payload = $payload;
        $event->status = 'PENDING';
        $event->available_at = $now;
        $event->save();

        return $event;
    }
}
