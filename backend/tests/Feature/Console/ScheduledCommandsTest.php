<?php

declare(strict_types=1);

namespace Tests\Feature\Console;

use Illuminate\Console\Scheduling\Event;
use Illuminate\Console\Scheduling\Schedule;
use Tests\TestCase;

/**
 * The sweeps a deployment must actually run, and how often.
 *
 * KI-025 was one command missing from `routes/console.php` — `payments:reconcile`
 * existed, was tested, and would never have run. It was found by a person
 * reading the file, which is not a control: nothing failed, and nothing would
 * have failed if the other three had been dropped too.
 *
 * That is what this fixes. Scheduling is the one part of this backend with no
 * caller — no route reaches it, no service depends on it, and every test that
 * exercises these commands invokes them directly. A `Schedule::command` line
 * deleted by accident is invisible to everything else in the suite, and its
 * consequence is silent: a sweep that stands between a charge and a missing
 * order simply stops happening.
 *
 * The cadences are asserted, not just the presence. "It is scheduled" is
 * satisfied by `->yearly()`, and a yearly sweep over somebody's money is the
 * same defect wearing a different hat.
 */
final class ScheduledCommandsTest extends TestCase
{
    /**
     * The artisan name of a scheduled event.
     *
     * The stored command is a full invocation — `'/usr/bin/php' 'artisan'
     * orders:recover-captured` — so only the last segment is the name.
     */
    private function nameOf(Event $event): ?string
    {
        if (! is_string($event->command)) {
            return null;
        }

        $parts = preg_split('/\s+/', trim($event->command)) ?: [];

        return trim((string) end($parts), "'\"");
    }

    /**
     * @return array<string, string> command => cron expression
     */
    private function scheduled(): array
    {
        $found = [];

        foreach ($this->app->make(Schedule::class)->events() as $event) {
            if ($name = $this->nameOf($event)) {
                $found[$name] = $event->expression;
            }
        }

        return $found;
    }

    public function test_every_sweep_that_stands_between_a_charge_and_a_missing_order_is_scheduled(): void
    {
        $scheduled = $this->scheduled();

        // Each of these has a failure mode that is somebody's money, and none of
        // them has any other caller in a running deployment.
        $required = [
            // A capture that never became an order: the customer has paid and
            // has nothing. Minutes, not hours.
            'orders:recover-captured' => '*/5 * * * *',

            // An order with no captured payment behind it. Reporting only,
            // because a command that guessed would cancel somebody's dinner
            // over a slow webhook.
            'orders:check-integrity' => '0 * * * *',

            // Drained from the day it starts filling, or the first consumer
            // inherits a backlog of events about orders collected weeks ago.
            'outbox:publish' => '* * * * *',

            // KI-025. The third path to a confirmed payment, for when both the
            // callback and the webhook were lost. Fifteen minutes, matching the
            // grace period the command itself insists on.
            'payments:reconcile' => '*/15 * * * *',
        ];

        foreach ($required as $command => $expression) {
            $this->assertArrayHasKey(
                $command,
                $scheduled,
                sprintf(
                    '%s is not scheduled. It has no other caller in a deployment, '
                    .'so nothing would run it and nothing else in this suite would notice.',
                    $command,
                ),
            );

            $this->assertSame(
                $expression,
                $scheduled[$command],
                sprintf('%s is scheduled, but not at the cadence it needs', $command),
            );
        }
    }

    public function test_otp_pruning_stays_on_its_off_peak_daily_slot(): void
    {
        // Not a money sweep — a retention concern, and deliberately daily rather
        // than hourly. Asserted so that "make everything five-minutely" is a
        // change somebody has to argue for.
        $this->assertSame('15 3 * * *', $this->scheduled()['otp:prune'] ?? null);
    }

    public function test_the_sweeps_do_not_stack_on_a_slow_run(): void
    {
        // Several app containers each run the scheduler, and a sweep that takes
        // longer than its interval must not have a second copy start on top of
        // it. withoutOverlapping is what stops that, and it is easy to leave off
        // a line copied from one that had it.
        $guarded = [];

        foreach ($this->app->make(Schedule::class)->events() as $event) {
            if ($name = $this->nameOf($event)) {
                $guarded[$name] = $event->withoutOverlapping;
            }
        }

        foreach ([
            'orders:recover-captured',
            'orders:check-integrity',
            'outbox:publish',
            'payments:reconcile',
            'otp:prune',
        ] as $command) {
            $this->assertTrue(
                $guarded[$command] ?? false,
                sprintf('%s may stack on a slow run: it has no withoutOverlapping()', $command),
            );
        }
    }
}
