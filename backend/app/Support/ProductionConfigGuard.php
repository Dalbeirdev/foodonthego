<?php

declare(strict_types=1);

namespace App\Support;

use App\Services\Otp\OtpDeliveryProvider;
use App\Services\Places\PlaceProvider;
use App\Services\Places\UnconfiguredPlaceProvider;
use Illuminate\Contracts\Foundation\Application;
use RuntimeException;
use Throwable;

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

        $failures = array_merge($failures, self::otpFailures($app));
        $failures = array_merge($failures, self::placeFailures($app));

        if ($failures !== []) {
            throw new RuntimeException(
                "FoodOnTheGo refused to start in the \"{$app->environment()}\" environment.\n\n  - "
                .implode("\n  - ", $failures)
                ."\n\nFix the configuration and restart. See docs/07-security.md.\n",
            );
        }
    }

    /**
     * Place provider configuration.
     *
     * The failure this prevents: a deployment ships with no Places credentials,
     * every search returns an error, and the trip planner is unusable for
     * everybody — discovered by a customer who cannot type a destination rather
     * than by a deploy that refused to finish. The development gazetteer refuses
     * to be constructed in production on its own account; this catches the
     * quieter case of a provider that resolves to "unconfigured".
     *
     * @return array<int, string>
     */
    private static function placeFailures(Application $app): array
    {
        try {
            $provider = $app->make(PlaceProvider::class);
        } catch (Throwable $e) {
            // Includes the development gazetteer's refusal to exist in production.
            return ['PLACES_PROVIDER could not be resolved: '.$e->getMessage()];
        }

        if ($provider instanceof UnconfiguredPlaceProvider) {
            return [
                'PLACES_PROVIDER is not configured. Set it and its credentials, or the trip planner cannot resolve a destination.',
            ];
        }

        return [];
    }

    /**
     * One-time passcode configuration.
     *
     * The failure this prevents is specific and has happened to other people: a
     * deployment goes out with OTP_PROVIDER still on the development log writer,
     * every sign-in silently "succeeds" at the API while no SMS is ever sent, and
     * the codes sit in a log file on a production host where anybody with read
     * access can sign in as any customer who has ever requested one. The provider
     * itself refuses to be constructed in production; this catches the same
     * mistake at boot, before a single request, and for any future provider that
     * reports it cannot reach a real handset.
     *
     * @return array<int, string>
     */
    private static function otpFailures(Application $app): array
    {
        $failures = [];

        if (config('foodonthego.otp.simulate_provider_failure') === true) {
            $failures[] = 'OTP_SIMULATE_PROVIDER_FAILURE must be false — it is a development switch that makes every sign-in fail.';
        }

        try {
            $provider = $app->make(OtpDeliveryProvider::class);
        } catch (Throwable $e) {
            // Includes LogOtpProvider's own refusal to exist in production.
            return [...$failures, 'OTP_PROVIDER could not be resolved: '.$e->getMessage()];
        }

        if (! $provider->deliversToRealDevices()) {
            $failures[] = sprintf(
                'OTP_PROVIDER is "%s", which does not deliver to real devices. Configure a real SMS provider before serving customers.',
                $provider->name(),
            );
        }

        return $failures;
    }
}
