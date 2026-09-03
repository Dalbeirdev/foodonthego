<?php

declare(strict_types=1);

use App\Exceptions\ApiExceptionRenderer;
use App\Http\Middleware\AssignRequestId;
use App\Http\Middleware\EnforceIdempotency;
use App\Http\Middleware\LogApiRequests;
use App\Http\Middleware\SecureHeaders;
use Illuminate\Cache\RateLimiting\Limit;
use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\RateLimiter;

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
    })
    ->create();
