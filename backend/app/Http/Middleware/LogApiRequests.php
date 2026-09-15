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

        $response = $next($request);

        /*
         | THE ACTOR IS READ AFTER THE REQUEST, NOT BEFORE IT, AND THAT IS THE
         | WHOLE POINT.
         |
         | This block used to sit above `$next()`. It could never work there.
         | These middleware are prepended to the `api` GROUP, while
         | `auth:sanctum` is applied per route group in routes/api.php -- so at
         | that moment nothing had authenticated anybody, and `$request->user()`
         | fell through to the DEFAULT guard, which is `web` (session). A
         | stateless API request carries no session, so the guard returned null,
         | the `if` never ran, and `setActor()` was never called even once.
         |
         | Every api.request line ever written has therefore carried no actor at
         | all: no id, no role. Not a formatting problem -- the fields were
         | simply never set.
         |
         | After `$next()`, the route's own auth middleware has run and Sanctum
         | has installed a user resolver on the request, so this reads the
         | principal the request was actually served as. Late enough to be true,
         | and still before the line below is written, which is the only
         | ordering that matters.
         |
         | Found by static analysis (KI-003): it flagged `is_string()` on a
         | backed enum, and the dead branch turned out to be inside a block that
         | was itself dead.
         */
        if (($user = $request->user()) !== null) {
            RequestContext::setActor(
                (string) $user->getAuthIdentifier(),
                // The enum's VALUE. The previous `is_string($user->role)` test
                // was written while `users.role` was a string column and has
                // answered false ever since it became a backed enum.
                $user->role?->value,
            );
        }

        $durationMs = round((microtime(true) - $startedAt) * 1000, 2);
        $status = $response->getStatusCode();

        $context = [
            'method' => $request->method(),
            // The matched route pattern, not the concrete URL: /api/v1/orders/{order}
            // aggregates, whereas one line per order id does not.
            'route' => $request->route()?->uri() ?? $request->path(),
            'path' => self::loggablePath($request),
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

    /**
     * Route parameters whose *values* must never be written to a log.
     *
     * Everything else in a path is an internal uuid, which says which record
     * without saying anything about it. A provider place id is different: it
     * names a real place, and a line that pairs one with `actor_id` is a record
     * of where a specific customer was going. Restart Module 05's log
     * inspection found exactly that — `api/v1/customer/places/dev%3Ataj-mahal`
     * beside the customer who asked for it.
     *
     * The search *query* was never logged and still is not: the query string is
     * not part of `path()`, and the request body is never logged at all.
     *
     * @var list<string>
     */
    private const PRIVATE_ROUTE_PARAMETERS = ['place'];

    /**
     * The concrete path, with private parameter values replaced by their name.
     *
     * Kept rather than dropped, because the path is what makes a log line
     * useful for everything else; only the sensitive segment is removed, and it
     * is removed by *value* so a place id cannot survive by being url-encoded.
     */
    private static function loggablePath(Request $request): string
    {
        $path = $request->path();
        $route = $request->route();

        if ($route === null) {
            return $path;
        }

        foreach (self::PRIVATE_ROUTE_PARAMETERS as $name) {
            $value = $route->parameter($name);

            if (! is_string($value) || $value === '') {
                continue;
            }

            $path = str_replace([$value, rawurlencode($value)], '{'.$name.'}', $path);
        }

        return $path;
    }
}
