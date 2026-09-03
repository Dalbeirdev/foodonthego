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
