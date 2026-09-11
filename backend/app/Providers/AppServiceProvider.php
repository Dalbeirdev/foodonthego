<?php

declare(strict_types=1);

namespace App\Providers;

use App\Support\ProductionConfigGuard;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\ServiceProvider;

final class AppServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        //
    }

    public function boot(): void
    {
        // Refuses to serve a production deployment that is misconfigured, rather
        // than booting, reporting itself healthy and being quietly insecure.
        ProductionConfigGuard::assert($this->app);

        // Accessing a relation that was not eager-loaded, or a property that does
        // not exist, is a bug — surfaced loudly in development instead of becoming
        // an N+1 query or a silent null in production.
        Model::preventLazyLoading(! $this->app->isProduction());
        Model::preventAccessingMissingAttributes(! $this->app->isProduction());
        Model::preventSilentlyDiscardingAttributes(! $this->app->isProduction());

        // Immutable dates keep ->addDay() from mutating a shared instance, which is
        // the classic source of "the ETA moved on its own" bugs.
        Carbon::setTestNow(null);

        if (! $this->app->isProduction()) {
            DB::listen(static function ($query): void {
                if ($query->time > 500) {
                    Log::warning('db.slow_query', [
                        'sql' => $query->sql,
                        'time_ms' => $query->time,
                    ]);
                }
            });
        }
    }
}
