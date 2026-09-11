<?php

declare(strict_types=1);

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Baseline response hardening for a JSON API.
 *
 * This API serves no HTML, so the CSP is the restrictive "this document may load
 * nothing at all" policy — correct for JSON, and it means a browser coaxed into
 * rendering a response as a document cannot be made to execute anything.
 */
final class SecureHeaders
{
    public function handle(Request $request, Closure $next): Response
    {
        $response = $next($request);

        $response->headers->set('X-Content-Type-Options', 'nosniff');
        $response->headers->set('X-Frame-Options', 'DENY');
        $response->headers->set('Referrer-Policy', 'no-referrer');
        $response->headers->set('Cross-Origin-Resource-Policy', 'same-site');
        $response->headers->set('Permissions-Policy', 'geolocation=(), camera=(), microphone=()');
        $response->headers->set(
            'Content-Security-Policy',
            "default-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'",
        );

        // HSTS is only meaningful over TLS, and asserting it in local development
        // would pin developers' browsers to https://localhost for a year.
        if ($request->isSecure()) {
            $response->headers->set('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');
        }

        // Never let a proxy or browser cache an authenticated API response.
        $response->headers->set('Cache-Control', 'no-store, private');

        return $response;
    }
}
