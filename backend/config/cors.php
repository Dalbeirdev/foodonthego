<?php

declare(strict_types=1);

/**
 * An exact allow-list, never a reflection of the inbound Origin.
 *
 * NOTE: the origins are parsed from env() directly rather than read with
 * config('foodonthego.frontend_urls'). Laravel loads every config file in a single
 * pass, so calling config() from inside one is not guaranteed to see another — it
 * silently yields the default, which here produced an empty allow-list and blocked
 * every browser request. Keep this in step with config/foodonthego.php.
 *
 * supports_credentials is on because the dashboards are credentialed; a wildcard
 * origin combined with credentials is exactly the configuration that leaks them,
 * which is why ProductionConfigGuard refuses to boot on one.
 */
$origins = array_values(array_filter(
    array_map('trim', explode(',', (string) env('FRONTEND_URLS', ''))),
));

return [
    'paths' => ['api/*'],
    'allowed_methods' => ['GET', 'POST', 'PATCH', 'PUT', 'DELETE', 'OPTIONS'],
    'allowed_origins' => $origins,
    'allowed_origins_patterns' => [],
    'allowed_headers' => ['Accept', 'Authorization', 'Content-Type', 'X-Request-Id', 'Idempotency-Key'],
    'exposed_headers' => ['X-Request-Id', 'Idempotency-Replayed'],
    'max_age' => 3600,
    'supports_credentials' => true,
];
