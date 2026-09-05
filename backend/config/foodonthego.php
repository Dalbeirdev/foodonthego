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

        // Discovery. Generous enough that a customer switching between map and
        // list, or reopening the screen, never meets it; tight enough that a
        // loop cannot spend the routing budget. The client is also expected not
        // to ask twice for the same route — this is the backstop, not the plan.
        'discovery' => (int) env('RATE_LIMIT_DISCOVERY', 30),
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
     | Routing (Module 06)
     |--------------------------------------------------------------------------
     */
    /*
    |--------------------------------------------------------------------------
    | Restaurant route discovery (Module 07)
    |--------------------------------------------------------------------------
    |
    | Every threshold here is a business assumption for the Delhi-Jaipur pilot,
    | not a fact about the world, which is exactly why none of them is written
    | into a service. Changing what counts as a reasonable stop should be a
    | deployment, not a release.
    */
    'discovery' => [
        // How far either side of the route a restaurant may sit and still be
        // worth evaluating. This is the *cheap* filter: it is measured as a
        // straight line to the route geometry, so it over-selects — a restaurant
        // 3 km from a highway with no exit for 20 km passes this and is then
        // rejected on its detour.
        //
        // 5 km for the pilot. Wide enough to catch a service road or a town just
        // off the highway, narrow enough that the candidate set stays small.
        'corridor_metres' => (int) env('DISCOVERY_CORRIDOR_METRES', 5_000),

        // The most restaurants that will be geometrically evaluated for one
        // request. A bound on the work, not on the answer: exceeding it means
        // the corridor is too wide for the dataset, and that is a configuration
        // problem worth seeing in a log rather than absorbing silently.
        'max_candidates' => (int) env('DISCOVERY_MAX_CANDIDATES', 300),

        // The most restaurants for which a real road-network detour will be
        // requested. Each one is a billed provider call, so this is the cost
        // ceiling of the whole module. Candidates beyond it keep their exact
        // geometric figures and carry a null detour, which the client renders as
        // an absent badge rather than as a zero.
        'max_detour_evaluations' => (int) env('DISCOVERY_MAX_DETOUR_EVALUATIONS', 12),

        // What makes a stop unreasonable. A restaurant that adds more than this
        // is not shown: it is not a stop on this journey, it is a different
        // journey.
        'max_detour_distance_metres' => (int) env('DISCOVERY_MAX_DETOUR_DISTANCE_METRES', 15_000),
        'max_detour_duration_seconds' => (int) env('DISCOVERY_MAX_DETOUR_DURATION_SECONDS', 900),

        // How many results a customer is given. Not a page of a thousand: a
        // traveller choosing where to eat is not reading past the first screen,
        // and a map with 400 markers on it communicates nothing.
        'result_limit' => (int) env('DISCOVERY_RESULT_LIMIT', 25),

        // How long a computed discovery result is served again without redoing
        // the work. Short, because availability changes on the minute and a
        // restaurant suspended at noon must not still be visible at half past.
        // Suspension does not wait for this to expire — the cache is versioned,
        // and a material change bumps the version.
        'cache_ttl_seconds' => (int) env('DISCOVERY_CACHE_TTL_SECONDS', 300),

        // Route geometry is simplified before it is measured against, because a
        // 25 000-point polyline times 300 candidates is nine million distance
        // calculations for an answer that does not change. The tolerance is the
        // most a simplified line may depart from the real one, and it is an
        // order of magnitude below the corridor width so that simplification can
        // never move a restaurant across the threshold.
        'geometry_simplify_tolerance_metres' => (int) env('DISCOVERY_SIMPLIFY_TOLERANCE_METRES', 150),

        // Used only when a restaurant's own timezone is unusable, and logged
        // when it happens. Never a silent assumption about where a restaurant is.
        'default_timezone' => env('DISCOVERY_DEFAULT_TIMEZONE', 'Asia/Kolkata'),

        /*
        |----------------------------------------------------------------------
        | Ranking weights (Module 08)
        |----------------------------------------------------------------------
        |
        | The "Recommended" order, as five numbers rather than as magic constants
        | scattered through a scoring method. They are here so that the product
        | question — what makes a stop worth recommending — can be answered by
        | somebody who does not read PHP, and changed without a release.
        |
        | They are normalised at use, so they need not sum to anything: doubling
        | every weight changes nothing, and doubling one changes its share.
        |
        | Never exposed to a customer. "Why is this first" is answered in words
        | on the card — four minutes' detour, open now — not with a score.
        */
        'weights' => [
            // Deliberately the largest. It is the whole reason this is a route
            // product rather than a nearby-restaurants product: a stop that
            // costs four minutes beats one that costs eighteen, whatever else
            // is true of them.
            'detour' => (float) env('DISCOVERY_WEIGHT_DETOUR', 0.45),

            // Second, and heavily weighted: a closed restaurant is not a stop
            // today, however convenient it is.
            'availability' => (float) env('DISCOVERY_WEIGHT_AVAILABILITY', 0.30),

            'proximity' => (float) env('DISCOVERY_WEIGHT_PROXIMITY', 0.15),

            // Last and lightest. Sorting by rating is what a generic listings
            // app does, and it would put a five-star restaurant forty minutes
            // off the route above a good one on it. Inert today in any case:
            // no restaurant has a rating.
            'rating' => (float) env('DISCOVERY_WEIGHT_RATING', 0.10),

            // Applied **only** when the customer typed something, and then
            // large: somebody who searched "Highway Spice" is asking for one
            // restaurant, not for the most convenient stop that happens to
            // match. Zero when there is no search, so it changes nothing.
            'search_relevance' => (float) env('DISCOVERY_WEIGHT_SEARCH_RELEVANCE', 0.60),
        ],
    ],

    'routing' => [
        // 'google' in any real deployment. 'development' is a straight-line
        // stand-in that refuses to run in production and labels everything it
        // returns; 'unconfigured' is the default and fails loudly.
        'provider' => env('ROUTE_PROVIDER', 'unconfigured'),

        // A *server* key, separate from the Places key so the two can carry
        // different API restrictions and be rotated independently. It never
        // leaves the backend: the app has no routing key of any kind.
        'google_api_key' => env('GOOGLE_ROUTES_API_KEY'),

        // Road travel. Configurable because a later market might not be, but not
        // customer-facing: FoodOnTheGo is about people driving between cities.
        'travel_mode' => env('ROUTE_TRAVEL_MODE', 'DRIVE'),

        // Whether to ask the provider for alternatives at all. Each one costs the
        // same as the primary route, so this is a product decision with an
        // invoice attached rather than a default worth leaving on.
        'alternatives_enabled' => (bool) env('ROUTE_ALTERNATIVES_ENABLED', true),

        // Including the recommended route. Three is a choice; ten is a list
        // nobody reads and four times the bill.
        'max_alternatives' => (int) env('ROUTE_MAX_ALTERNATIVES', 3),

        // Traffic-aware routing costs more than traffic-unaware. On, because a
        // travel time that ignores traffic is not much use to somebody deciding
        // when to eat.
        'traffic_aware' => (bool) env('ROUTE_TRAFFIC_AWARE', true),

        'timeout_seconds' => (int) env('ROUTE_TIMEOUT_SECONDS', 12),

        'language_code' => env('ROUTE_LANGUAGE_CODE', 'en-IN'),

        // How long a calculated route is served without asking the provider
        // again. The geometry does not change; the traffic figure does, and this
        // is the window in which we are willing to call it current.
        //
        // The single most important cost control in this module: without it,
        // every open of the route screen is a billed request.
        'freshness_seconds' => (int) env('ROUTE_FRESHNESS_SECONDS', 900),

        // Refuses a geometry larger than this before it is stored. A polyline is
        // normally a few kilobytes; anything approaching this is a malformed or
        // hostile response rather than a long journey.
        'max_polyline_bytes' => (int) env('ROUTE_MAX_POLYLINE_BYTES', 512_000),

        // How far a route's own start may be from the origin we asked about
        // before we refuse it. Providers snap to the nearest road, which is
        // metres in a city and can be a kilometre or two in open country; a
        // route starting further away than this is answering a different
        // question.
        'endpoint_tolerance_metres' => (int) env('ROUTE_ENDPOINT_TOLERANCE_METRES', 5_000),
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

    /*
     |--------------------------------------------------------------------------
     | Item customization and the cart (Module 11)
     |--------------------------------------------------------------------------
     |
     | Every limit a customer can run into while configuring a dish. Nothing in
     | the codebase compares against a literal — a business decision to allow
     | twenty of something is a change to this file and nothing else.
     */
    'cart' => [
        // How many of one configured line a customer may add at once.
        //
        // Twenty rather than ninety-nine: this is a roadside pickup order for
        // the people in one car, not a catering order, and a stepper that runs
        // to ninety-nine invites a mis-tap nobody notices until the counter.
        'max_quantity_per_line' => (int) env('CART_MAX_QUANTITY_PER_LINE', 20),

        // A note to the kitchen, not an essay. Long enough for "no onion, pack
        // the sauce separately, less spicy please" with room to spare; short
        // enough that it fits on a ticket somebody has to read while cooking.
        'max_special_instructions' => (int) env('CART_MAX_SPECIAL_INSTRUCTIONS', 300),

        // How many distinct lines one cart may hold. An anti-abuse ceiling
        // rather than a product rule; a real order is a handful of dishes.
        'max_lines' => (int) env('CART_MAX_LINES', 50),

        // How long an untouched cart stays usable. The foundation for the
        // stale-cart handling Module 12 owns: the column is written from now,
        // and nothing yet deletes on it.
        'ttl_seconds' => (int) env('CART_TTL_SECONDS', 60 * 60 * 24 * 7),
    ],

    'api' => [
        'current_version' => 'v1',
        'supported_versions' => ['v1'],
    ],
];
