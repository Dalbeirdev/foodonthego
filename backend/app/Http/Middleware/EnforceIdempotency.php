<?php

declare(strict_types=1);

namespace App\Http\Middleware;

use App\Enums\ApiErrorCode;
use App\Http\Responses\ApiResponse;
use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Symfony\Component\HttpFoundation\Response;

/**
 * Makes an unsafe request replay-safe when the client supplies `Idempotency-Key`.
 *
 * The problem this exists for: a traveller on a patchy motorway connection taps
 * "place order", the response is lost, the app retries — and without this they are
 * charged twice. With it, the retry returns the first response.
 *
 * Two properties matter and are easy to get wrong:
 *
 *  - The key is namespaced per authenticated actor. A key is chosen by the client,
 *    so a global namespace would let one user guess another's key and read back
 *    their response body.
 *  - The same key with a *different* request body is rejected rather than served
 *    the old response, because that is a client bug (or an attack), not a retry.
 *
 * Module 01 wires the mechanism. Endpoints that need it opt in from their own module.
 */
final class EnforceIdempotency
{
    public const HEADER = 'Idempotency-Key';

    private const UNSAFE_METHODS = ['POST', 'PATCH', 'PUT', 'DELETE'];

    public function handle(Request $request, Closure $next): Response
    {
        $key = $request->headers->get(self::HEADER);

        if (! is_string($key) || $key === '' || ! in_array($request->method(), self::UNSAFE_METHODS, true)) {
            return $next($request);
        }

        if (strlen($key) > 255) {
            return ApiResponse::error(
                ApiErrorCode::ValidationFailed,
                'Idempotency-Key must be 255 characters or fewer.',
            );
        }

        $actor = self::actorFingerprint($request);
        $cacheKey = 'idempotency:'.hash('sha256', $actor.'|'.$key);
        $fingerprint = hash('sha256', $request->getContent());

        /** @var array{fingerprint: string, status: int, body: string}|null $stored */
        $stored = Cache::get($cacheKey);

        if ($stored !== null) {
            if (! hash_equals($stored['fingerprint'], $fingerprint)) {
                return ApiResponse::error(
                    ApiErrorCode::IdempotencyKeyReused,
                    'This Idempotency-Key was already used for a different request body.',
                );
            }

            return response($stored['body'], $stored['status'])
                ->header('Content-Type', 'application/json')
                ->header('Idempotency-Replayed', 'true');
        }

        $response = $next($request);

        // Only a settled outcome is worth replaying. Caching a 5xx would make a
        // transient failure permanent for the lifetime of the key.
        if ($response->getStatusCode() < 500) {
            Cache::put($cacheKey, [
                'fingerprint' => $fingerprint,
                'status' => $response->getStatusCode(),
                'body' => $response->getContent(),
            ], (int) config('foodonthego.idempotency_ttl'));
        }

        return $response;
    }

    /**
     * A stable identity for the caller, for scoping the key.
     *
     * Taken from the credential the request *carries*, not from
     * `$request->user()`. This middleware runs before authentication, so the
     * resolved user is normally null here — but "normally" is doing dangerous
     * work in that sentence: anything that resolves a user earlier (a change of
     * middleware order, a framework that caches a guard across requests) would
     * silently give two retries of one request two different cache keys, and
     * idempotency would stop working precisely when it was needed.
     *
     * The credential is hashed. A raw token must not become a cache key, where
     * it would sit in Redis in plaintext for a day.
     */
    private static function actorFingerprint(Request $request): string
    {
        $authorization = (string) $request->headers->get('Authorization', '');

        if ($authorization !== '') {
            return 'token:'.hash('sha256', $authorization);
        }

        return 'anonymous:'.$request->ip();
    }
}
