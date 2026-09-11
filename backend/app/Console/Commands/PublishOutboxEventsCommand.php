<?php

declare(strict_types=1);

namespace App\Console\Commands;

use App\Models\OutboxEvent;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Date;
use Illuminate\Support\Facades\Log;

/**
 * Ship the events that were written with the orders they describe.
 *
 * WHAT THIS DELIBERATELY DOES NOT DO YET. There are no consumers. Module 18's
 * restaurant queue, Module 20's notifications and whatever analytics arrive
 * later are the things that will subscribe, and none of them exist — so this
 * marks rows published and records that it did.
 *
 * That is not a placeholder for its own sake. The outbox has to be drained from
 * the day it starts filling, or the first module to add a consumer inherits a
 * backlog of stale events about orders that were collected weeks ago. Draining
 * it now, with nothing downstream, keeps the table honest and makes the
 * eventual consumer a subscription rather than a migration.
 */
final class PublishOutboxEventsCommand extends Command
{
    protected $signature = 'outbox:publish {--limit=200}';

    protected $description = 'Mark pending outbox events as published.';

    public function handle(): int
    {
        $now = Date::now()->toImmutable();

        $pending = OutboxEvent::query()
            ->where('status', 'PENDING')
            ->where('available_at', '<=', $now)
            ->orderBy('id')
            ->limit((int) $this->option('limit'))
            ->get();

        foreach ($pending as $event) {
            $event->status = 'PUBLISHED';
            $event->published_at = $now;
            $event->attempts = (int) $event->attempts + 1;
            $event->save();

            // The event id, so a future consumer's deduplication can be traced
            // back to a publish. Never the payload: it is identifiers today,
            // but a log line is the wrong place to promise that stays true.
            Log::info('outbox.published', [
                'event_id' => $event->event_id,
                'event_name' => $event->event_name,
            ]);
        }

        $this->info($pending->count().' event(s) published.');

        return self::SUCCESS;
    }
}
