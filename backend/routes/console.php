<?php

declare(strict_types=1);

use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Schedule;

Artisan::command('inspire', function (): void {
    $this->comment(Inspiring::quote());
})->purpose('Display an inspiring quote');

/*
|--------------------------------------------------------------------------
| Schedule
|--------------------------------------------------------------------------
|
| Requires a single cron entry on the host:
|   * * * * * cd /path/to/backend && php artisan schedule:run >> /dev/null 2>&1
|
| withoutOverlapping() matters on multi-instance deployments: several app
| containers each run the scheduler, and only one should do the work.
*/

// Off-peak, and daily rather than hourly — dead OTP rows are a retention concern,
// not a capacity one.
Schedule::command('otp:prune')->dailyAt('03:15')->withoutOverlapping();

/*
|--------------------------------------------------------------------------
| Module 16 — the sweeps that stand between a charge and a missing order
|--------------------------------------------------------------------------
*/

/*
 | Every five minutes, because this one is about somebody's money.
 |
 | A capture that never became an order is a customer who has paid and has
 | nothing. The window in which that is true should be minutes, not the hour a
 | tidier schedule would give it. Idempotent, so overlapping with a webhook
 | doing the same work is harmless — withoutOverlapping is about not stacking
 | sweeps, not about correctness.
 */
Schedule::command('orders:recover-captured')
    ->everyFiveMinutes()
    ->withoutOverlapping();

/*
 | Hourly, and reporting only.
 |
 | An order without a captured payment behind it is the failure that costs the
 | business rather than the customer, and it needs a human to decide whether the
 | payment is genuinely missing or merely unreconciled. A command that guessed
 | would eventually cancel somebody's dinner over a slow webhook.
 */
Schedule::command('orders:check-integrity')->hourly()->withoutOverlapping();

/*
 | Every minute. The outbox has to be drained from the day it starts filling, or
 | the first module to add a consumer inherits a backlog of stale events about
 | orders that were collected weeks ago.
 */
Schedule::command('outbox:publish')->everyMinute()->withoutOverlapping();

/*
|--------------------------------------------------------------------------
| Module 15 — the third path to a confirmed payment (KI-025)
|--------------------------------------------------------------------------
|
| `payments:reconcile` asks the provider about orders this server still thinks
| are unpaid, and settles the ones that were in fact paid. It is the path that
| runs when BOTH the client callback and the webhook were lost.
|
| Module 15 left it unscheduled on the grounds that a cadence depends on how a
| deployment is operated, and a project with no deployment inventing one would
| be inventing a fact. Module 16 noticed the gap and deliberately did not fix it
| under cover of its own work. This is that decision taken on its own, which is
| how it was always meant to happen.
|
| FIFTEEN MINUTES, and the number is derived rather than picked. The command's
| own --minutes default is a fifteen-minute grace period, so an order is not
| examined until both other paths have had their chance; sweeping more often
| than the grace window just re-asks about the same orders, and sweeping less
| often lengthens the window in which somebody has paid and has no order.
|
| It is also the only scheduled sweep that talks to the payment provider —
| Module 16's three are database-only — so the cost of running it is not
| notional. Fifteen minutes is the longest interval that adds no delay beyond
| the grace period the command already insists on.
|
| Safe in a deployment with no gateway configured: UnconfiguredPaymentGateway
| throws PaymentGatewayException, ReconciliationService counts that as
| `unreachable` and logs a warning, and the command still exits SUCCESS. A
| missing integration stays loud in the log without turning the scheduler into
| a failing job every quarter hour.
*/
Schedule::command('payments:reconcile')
    ->everyFifteenMinutes()
    ->withoutOverlapping();
