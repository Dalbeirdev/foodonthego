<?php

declare(strict_types=1);

namespace App\Console\Commands;

use App\Models\OtpChallenge;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Log;

/**
 * Deletes OTP challenges that can no longer be used.
 *
 * Two reasons, and the second is the important one:
 *
 * 1. The table grows by one row per sign-in attempt forever and nothing in the
 *    product ever reads an old row.
 * 2. A dead challenge is still a record that a particular phone number tried to
 *    sign in at a particular time, which is personal data we have no reason to
 *    keep. Retaining it only widens what a database compromise discloses.
 *
 * A short grace period after expiry is kept deliberately, so that an abuse
 * investigation on the same day still has something to look at.
 *
 * Note what is *not* deleted: nothing here touches the rate-limit counters, which
 * live in Redis with their own window. Pruning must never hand an attacker a
 * fresh budget.
 */
final class PruneOtpChallenges extends Command
{
    protected $signature = 'otp:prune {--hours=48 : Delete unusable challenges older than this many hours}';

    protected $description = 'Delete expired, consumed and invalidated OTP challenges past their retention window.';

    public function handle(): int
    {
        $hours = max(1, (int) $this->option('hours'));
        $cutoff = now()->subHours($hours);

        // Only rows that are already unusable. A live challenge is never pruned,
        // however old the row is — deleting one mid-verification would present a
        // customer with "code expired" while their SMS is on screen.
        $deleted = OtpChallenge::query()
            ->where('created_at', '<', $cutoff)
            ->where(function ($query): void {
                $query->whereNotNull('consumed_at')
                    ->orWhereNotNull('invalidated_at')
                    ->orWhere('expires_at', '<', now());
            })
            ->delete();

        Log::info('otp.challenges.pruned', [
            'deleted' => $deleted,
            'older_than_hours' => $hours,
        ]);

        $this->info("Pruned {$deleted} OTP challenge(s) older than {$hours}h.");

        return self::SUCCESS;
    }
}
