<?php

declare(strict_types=1);

use App\Exceptions\ApiExceptionRenderer;
use App\Http\Middleware\AssignRequestId;
use App\Http\Middleware\EnforceIdempotency;
use App\Http\Middleware\EnsureRole;
use App\Http\Middleware\LogApiRequests;
use App\Http\Middleware\SecureHeaders;
use Illuminate\Cache\RateLimiting\Limit;
use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\RateLimiter;
use Laravel\Sanctum\Http\Middleware\CheckAbilities;
use Laravel\Sanctum\Http\Middleware\CheckForAnyAbility;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        api: __DIR__.'/../routes/api.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        // Order is deliberate. The request id is assigned first so that everything
        // after it — including a failure inside another middleware — is logged and
        // reported against the same correlation id. Logging wraps the rest so its
        // recorded duration and status reflect what the client actually received.
        $middleware->api(prepend: [
            AssignRequestId::class,
            SecureHeaders::class,
            LogApiRequests::class,
            EnforceIdempotency::class,
        ]);

        // Deliberately NOT applied globally: /health/* must stay unthrottled so an
        // orchestrator polling liveness cannot rate-limit itself into a false
        // "unhealthy" verdict. Routes opt in with `throttle:api-public`.

        // Authorisation is two independent gates and both are named here so that a
        // route reads as a sentence: `role:` asks what kind of account this is,
        // `abilities:` asks what this particular token was issued to do. A route
        // that only checks authentication has checked neither.
        $middleware->alias([
            'role' => EnsureRole::class,
            'abilities' => CheckAbilities::class,
            'ability' => CheckForAnyAbility::class,
        ]);

        // There is no HTML login page to send a guest to. Laravel's default
        // redirect target is `route('login')`, which for any request that does
        // not announce `Accept: application/json` — a browser opening an API URL,
        // a probe, a misconfigured client — throws RouteNotFoundException before
        // the AuthenticationException is ever raised, and the caller is told 500
        // when the truth is 401. Returning null keeps the exception intact so the
        // renderer answers with the same 401 every other caller gets.
        $middleware->redirectGuestsTo(static fn (): ?string => null);
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        $exceptions->render(fn (Throwable $e, Request $request) => app(ApiExceptionRenderer::class)->render($e, $request));
    })
    ->booted(function (): void {
        // Keyed by authenticated user where there is one, and by IP otherwise, so a
        // shared corporate NAT does not throttle every traveller behind it as one.
        RateLimiter::for('api-public', static fn (Request $request): Limit => $request->user()
            ? Limit::perMinute((int) config('foodonthego.rate_limits.authenticated'))->by('user:'.$request->user()->getAuthIdentifier())
            : Limit::perMinute((int) config('foodonthego.rate_limits.public'))->by('ip:'.$request->ip()));

        // Unauthenticated auth endpoints are the ones worth attacking, so they get
        // their own much tighter budget rather than the general public allowance.
        //
        // This is the coarse per-IP net and is not the real OTP control: the precise
        // per-phone and per-IP limits live in OtpRateLimiter, which counts issued
        // challenges rather than HTTP requests and survives a client that retries
        // through a proxy pool. This one exists so a flood never reaches the
        // database at all.
        RateLimiter::for('auth-otp', static fn (Request $request): Limit => Limit::perMinute(
            (int) config('foodonthego.rate_limits.auth_otp'),
        )->by('ip:'.$request->ip()));

        // Verification and registration are guessing surfaces. The per-challenge
        // attempt counter in MySQL is authoritative — an attacker who cycles
        // challenges to dodge it still meets this.
        RateLimiter::for('auth-verify', static fn (Request $request): Limit => Limit::perMinute(
            (int) config('foodonthego.rate_limits.auth_verify'),
        )->by('ip:'.$request->ip()));

        // Restaurant discovery is the most expensive endpoint in the
        // application: a corridor query over the restaurant table plus up to a
        // dozen billed routing calls. Keyed by customer rather than by IP,
        // because the abuse this guards against is one client looping — a
        // rebuilt widget, a map pan, a retry storm — and a shared corporate NAT
        // must not throttle every traveller behind it as one.
        RateLimiter::for('discovery', static fn (Request $request): Limit => $request->user()
            ? Limit::perMinute((int) config('foodonthego.rate_limits.discovery'))
                ->by('user:'.$request->user()->getAuthIdentifier())
            : Limit::perMinute((int) config('foodonthego.rate_limits.public'))
                ->by('ip:'.$request->ip()));
    })
    ->create();
