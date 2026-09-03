<?php

declare(strict_types=1);

namespace App\Http\Middleware;

use App\Support\RequestContext;
use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Symfony\Component\HttpFoundation\Response;

/**
 * One structured line per API request: what was called, by whom, what came back and
 * how long it took.
 *
 * The request *body* is deliberately never logged. Sanitising it is possible (the
 * formatter does redact known keys) but the safer default for an API that will
 * carry addresses, payment intents and OTPs is not to write it at all.
 */
final class LogApiRequests
{
    public function handle(Request $request, Closure $next): Response
    {
        $startedAt = microtime(true);

        $user = $request->user();
        if ($user !== null) {
            RequestContext::setActor(
                (string) $user->getAuthIdentifier(),
                is_string($user->role ?? null) ? $user->role : null,
            );
        }

        $response = $next($request);

        $durationMs = round((microtime(true) - $startedAt) * 1000, 2);
        $status = $response->getStatusCode();

        $context = [
            'method' => $request->method(),
            // The matched route pattern, not the concrete URL: /api/v1/orders/{order}
            // aggregates, whereas one line per order id does not.
            'route' => $request->route()?->uri() ?? $request->path(),
            'path' => $request->path(),
            'status' => $status,
            'duration_ms' => $durationMs,
            'ip' => $request->ip(),
        ];

        match (true) {
            $status >= 500 => Log::error('api.request.failed', $context),
            $status >= 400 => Log::warning('api.request.rejected', $context),
            default => Log::info('api.request', $context),
        };

        return $response;
    }
}
