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

        // Per IP, per minute, on the unauthenticated auth endpoints. Deliberately
        // far below the public allowance — a genuine sign-in needs a handful of
        // requests, so anything above this is not a customer signing in.
        'auth_otp' => (int) env('RATE_LIMIT_AUTH_OTP', 10),
        'auth_verify' => (int) env('RATE_LIMIT_AUTH_VERIFY', 15),
    ],

    'idempotency_ttl' => (int) env('IDEMPOTENCY_TTL', 86400),

    /*
     |--------------------------------------------------------------------------
     | One-time passcodes (Module 03)
     |--------------------------------------------------------------------------
     |
     | Every OTP rule lives here. Nothing in the codebase compares against a
     | literal 6 or 300 — a business decision to lengthen the code or shorten its
     | life is a change to this file and nothing else.
     */
    'otp' => [
        'length' => (int) env('OTP_LENGTH', 6),

        // Long enough to read an SMS and type it, short enough that an
        // intercepted code is stale before it is useful.
        'ttl_seconds' => (int) env('OTP_TTL_SECONDS', 300),

        // Wrong guesses allowed against one challenge before it dies. With a
        // six-digit code that leaves a 5-in-a-million chance per challenge.
        'max_attempts' => (int) env('OTP_MAX_ATTEMPTS', 5),

        // Enforced server-side. The client countdown is a courtesy.
        'resend_cooldown_seconds' => (int) env('OTP_RESEND_COOLDOWN_SECONDS', 30),

        // Requests per phone number and per IP, and the window they apply over.
        'max_requests_per_phone' => (int) env('OTP_MAX_REQUESTS_PER_PHONE', 5),
        'max_requests_per_ip' => (int) env('OTP_MAX_REQUESTS_PER_IP', 20),
        'request_window_seconds' => (int) env('OTP_REQUEST_WINDOW_SECONDS', 3600),

        // How long a verified phone can be exchanged for an account.
        'registration_token_ttl_seconds' => (int) env('OTP_REGISTRATION_TOKEN_TTL_SECONDS', 900),

        // 'log' writes codes to a development log file; anything else must be a
        // real provider. The production guard refuses to boot on a provider that
        // reports it cannot deliver to a real handset.
        'provider' => env('OTP_PROVIDER', 'log'),

        // Development-only switch for exercising the delivery-failure path.
        'simulate_provider_failure' => (bool) env('OTP_SIMULATE_PROVIDER_FAILURE', false),
    ],

    /*
     |--------------------------------------------------------------------------
     | Saved addresses (Module 04)
     |--------------------------------------------------------------------------
     */
    'addresses' => [
        // An anti-abuse ceiling, not a product limit. Generous enough that no
        // real customer meets it — a traveller with home, work, two sets of
        // parents and a few regular stops is nowhere near — and low enough that
        // an account cannot be used as free storage.
        'max_per_customer' => (int) env('ADDRESS_MAX_PER_CUSTOMER', 25),

        // The launch market. Used as the form default only; the schema and the
        // validator both accept any ISO 3166-1 alpha-2 code.
        'default_country_code' => env('ADDRESS_DEFAULT_COUNTRY', 'IN'),
    ],

    /*
     |--------------------------------------------------------------------------
     | Places (Module 05)
     |--------------------------------------------------------------------------
     |
     | Place search is server-mediated. The key lives here and never ships to a
     | device: a key in a mobile binary is a published key, and the platform
     | restrictions Google offers bound the damage rather than preventing it.
     | Held here it is IP-restricted to our servers and rotatable without an app
     | release. See docs/20-trip-planner.md.
     */
    'places' => [
        // 'google' in any real deployment. 'development' is a small fixed
        // gazetteer of real places for local work and refuses to run in
        // production; 'unconfigured' is the default and fails loudly.
        'provider' => env('PLACES_PROVIDER', 'unconfigured'),

        'google_api_key' => env('GOOGLE_PLACES_API_KEY'),

        // A search *bias*, not a filter, and a list rather than a constant: the
        // launch market is India, and a permanently hard-coded country would
        // have to be hunted down in the first month of the second market.
        'regions' => array_values(array_filter(
            array_map('trim', explode(',', (string) env('PLACES_REGIONS', 'in'))),
        )),

        'timeout_seconds' => (int) env('PLACES_TIMEOUT_SECONDS', 5),
        'max_results' => (int) env('PLACES_MAX_RESULTS', 8),

        // A search query is personal, so this cache is short and keyed by the
        // query alone — never by customer. It exists to stop a retyped search
        // costing twice, not to build a history.
        'cache_seconds' => (int) env('PLACES_CACHE_SECONDS', 120),
    ],

    /*
     |--------------------------------------------------------------------------
     | Journeys (Module 05)
     |--------------------------------------------------------------------------
     */
    'trips' => [
        // An anti-abuse ceiling on trips still waiting for a route. Cancelled
        // trips and trips that have been routed do not count, so a customer who
        // uses the app is never told they have too many.
        'max_pending_per_customer' => (int) env('TRIP_MAX_PENDING_PER_CUSTOMER', 20),

        // How close two endpoints may be before they are the same place.
        //
        // 75 metres is a building, not a neighbourhood. It catches the case this
        // rule exists for — the same airport chosen once from a saved address and
        // once from a search — without refusing a genuinely short journey between
        // two nearby addresses, which a generous radius would.
        'same_location_threshold_metres' => (int) env('TRIP_SAME_LOCATION_METRES', 75),
    ],

    'auth' => [
        // Sanctum access-token lifetime. 30 days: long enough that a traveller is
        // not signed out mid-journey, short enough that a lost handset stops
        // working. Revocation on logout is immediate regardless.
        'token_ttl_seconds' => (int) env('AUTH_TOKEN_TTL_SECONDS', 60 * 60 * 24 * 30),
    ],

    'api' => [
        'current_version' => 'v1',
        'supported_versions' => ['v1'],
    ],
];
