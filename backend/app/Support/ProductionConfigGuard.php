<?php

declare(strict_types=1);

namespace App\Support;

use Illuminate\Contracts\Foundation\Application;
use RuntimeException;

/**
 * Startup checks that only apply once the environment claims to be staging or
 * production.
 *
 * Each one is a configuration that would otherwise produce a service that looks
 * healthy and is not: debug mode leaking stack traces, an unsigned app key, a CORS
 * list that lets any origin read credentialed responses. Failing to boot is the
 * loud, safe outcome — a container that will not start gets noticed immediately,
 * while one that starts insecure does not.
 */
final class ProductionConfigGuard
{
    /** Environments where these rules are enforced. */
    private const GUARDED = ['staging', 'production'];

    public static function assert(Application $app): void
    {
        if (! in_array($app->environment(), self::GUARDED, true)) {
            return;
        }

        $failures = [];

        if (config('app.debug') === true) {
            $failures[] = 'APP_DEBUG must be false — debug mode returns stack traces and configuration to clients.';
        }

        $key = (string) config('app.key');
        if ($key === '' || $key === 'base64:') {
            $failures[] = 'APP_KEY is not set — sessions and encrypted values cannot be trusted without it.';
        }

        $origins = (array) config('foodonthego.frontend_urls');
        if ($origins === []) {
            $failures[] = 'FRONTEND_URLS must list at least one origin — an empty CORS allow-list leaves the decision to the browser.';
        }
        if (in_array('*', $origins, true)) {
            $failures[] = 'FRONTEND_URLS may not contain "*" — this API is credentialed, and a wildcard origin with credentials leaks them.';
        }

        foreach ($origins as $origin) {
            if (! str_starts_with((string) $origin, 'https://')) {
                $failures[] = "FRONTEND_URLS entry \"{$origin}\" must use https in this environment.";
            }
        }

        if (config('database.default') !== 'mysql') {
            $failures[] = 'DB_CONNECTION must be mysql — MySQL is the source of truth for orders, payments and payouts.';
        }

        if ((string) config('database.connections.mysql.password') === '') {
            $failures[] = 'DB_PASSWORD must not be empty.';
        }

        if ($failures !== []) {
            throw new RuntimeException(
                "FoodOnTheGo refused to start in the \"{$app->environment()}\" environment.\n\n  - "
                .implode("\n  - ", $failures)
                ."\n\nFix the configuration and restart. See docs/07-security.md.\n",
            );
        }
    }
}
