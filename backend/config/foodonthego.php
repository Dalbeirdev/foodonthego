<?php

declare(strict_types=1);

/**
 * Product configuration. Reading env() only here (never in application code) is
 * what makes `php artisan config:cache` safe in production: a cached config file
 * means env() returns null everywhere else.
 */
return [
    'frontend_urls' => array_values(array_filter(
        array_map('trim', explode(',', (string) env('FRONTEND_URLS', ''))),
    )),

    'rate_limits' => [
        'public' => (int) env('RATE_LIMIT_PUBLIC', 60),
        'authenticated' => (int) env('RATE_LIMIT_AUTHENTICATED', 120),
    ],

    'idempotency_ttl' => (int) env('IDEMPOTENCY_TTL', 86400),

    'api' => [
        'current_version' => 'v1',
        'supported_versions' => ['v1'],
    ],
];
