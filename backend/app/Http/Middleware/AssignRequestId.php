<?php

declare(strict_types=1);

namespace App\Http\Middleware;

use App\Support\RequestContext;
use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Str;
use Symfony\Component\HttpFoundation\Response;

/**
 * Gives every request a correlation ID and echoes it back on the response.
 *
 * An inbound `X-Request-Id` is honoured so a trace started at the edge (or by the
 * mobile app) survives into our logs — but it is validated first. Accepting an
 * arbitrary client string would let a caller forge or poison log lines, so anything
 * that is not a plain UUID is replaced with one we generate.
 */
final class AssignRequestId
{
    public const HEADER = 'X-Request-Id';

    public function handle(Request $request, Closure $next): Response
    {
        $incoming = $request->headers->get(self::HEADER);
        $requestId = is_string($incoming) && Str::isUuid($incoming)
            ? $incoming
            : (string) Str::uuid();

        RequestContext::set($requestId);
        $request->headers->set(self::HEADER, $requestId);

        $response = $next($request);
        $response->headers->set(self::HEADER, $requestId);

        return $response;
    }
}
