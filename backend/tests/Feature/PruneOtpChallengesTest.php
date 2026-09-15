<?php

declare(strict_types=1);

namespace Tests\Feature;

use App\Models\OtpChallenge;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\TestCase;

final class PruneOtpChallengesTest extends TestCase
{
    use RefreshDatabase;

    private function challenge(array $attributes): OtpChallenge
    {
        return OtpChallenge::create(array_merge([
            'uuid' => (string) Str::uuid(),
            'phone_e164' => '+9198'.random_int(10000000, 99999999),
            'otp_hash' => str_repeat('a', 64),
            'expires_at' => now()->addMinutes(5),
            'attempts' => 0,
            'max_attempts' => 5,
            'resend_count' => 0,
            'last_sent_at' => now(),
        ], $attributes));
    }

    public function test_it_deletes_challenges_that_can_no_longer_be_used(): void
    {
        $consumed = $this->challenge(['consumed_at' => now()]);
        $invalidated = $this->challenge(['invalidated_at' => now(), 'invalidated_reason' => 'superseded']);
        $expired = $this->challenge(['expires_at' => now()->subHour()]);

        foreach ([$consumed, $invalidated, $expired] as $old) {
            $old->forceFill(['created_at' => now()->subDays(3)])->save();
        }

        $this->artisan('otp:prune', ['--hours' => 48])->assertSuccessful();

        $this->assertDatabaseCount('otp_challenges', 0);
    }

    public function test_it_never_deletes_a_challenge_a_customer_could_still_be_typing(): void
    {
        // Old row, still live. Deleting it would show "code expired" to somebody
        // looking at the SMS on their screen.
        $live = $this->challenge(['expires_at' => now()->addMinutes(4)]);
        $live->forceFill(['created_at' => now()->subDays(10)])->save();

        $this->artisan('otp:prune', ['--hours' => 1])->assertSuccessful();

        $this->assertModelExists($live);
    }

    public function test_it_respects_the_retention_window(): void
    {
        // Consumed an hour ago: still inside a same-day abuse investigation.
        $recent = $this->challenge(['consumed_at' => now()]);
        $recent->forceFill(['created_at' => now()->subHour()])->save();

        $this->artisan('otp:prune', ['--hours' => 48])->assertSuccessful();

        $this->assertModelExists($recent);
    }

    public function test_the_window_cannot_be_argued_down_to_nothing(): void
    {
        $consumed = $this->challenge(['consumed_at' => now()]);
        $consumed->forceFill(['created_at' => now()->subMinutes(30)])->save();

        // --hours=0 is clamped to 1, so a mistyped cron entry cannot wipe rows
        // that a live investigation is reading.
        $this->artisan('otp:prune', ['--hours' => 0])->assertSuccessful();

        $this->assertModelExists($consumed);
    }
}
