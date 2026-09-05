<?php

declare(strict_types=1);

use App\Enums\ApiErrorCode;
use App\Http\Controllers\Api\V1\Auth\CustomerOtpController;
use App\Http\Controllers\Api\V1\Auth\CustomerRegistrationController;
use App\Http\Controllers\Api\V1\Auth\SessionController;
use App\Http\Controllers\Api\V1\Customer\AddressController;
use App\Http\Controllers\Api\V1\Customer\CartItemController;
use App\Http\Controllers\Api\V1\Customer\PlaceController;
use App\Http\Controllers\Api\V1\Customer\ProfileController;
use App\Http\Controllers\Api\V1\Customer\RestaurantMenuController;
use App\Http\Controllers\Api\V1\Customer\TripController;
use App\Http\Controllers\Api\V1\Customer\TripRestaurantController;
use App\Http\Controllers\Api\V1\Customer\TripRestaurantDetailController;
use App\Http\Controllers\Api\V1\Customer\TripRouteController;
use App\Http\Controllers\Api\V1\HealthController;
use App\Http\Controllers\Api\V1\MetaController;
use App\Http\Responses\ApiResponse;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| FoodOnTheGo API — v1
|--------------------------------------------------------------------------
|
| Every route lives under /api/v1. Versioning is in the path rather than in a
| header because it survives a browser address bar, a curl in a bug report and a
| CDN cache key — see docs/05-api-standards.md.
|
| Feature routes arrive with the modules that implement them, each behind the
| middleware it needs. Module 01 shipped health and meta; Module 03 adds customer
| authentication.
*/

Route::prefix('v1')->group(function (): void {
    // Unauthenticated and unthrottled: an orchestrator polling liveness must not be
    // able to rate-limit itself out of a healthy verdict.
    Route::get('/health/live', [HealthController::class, 'live'])->name('api.v1.health.live');
    Route::get('/health/ready', [HealthController::class, 'ready'])->name('api.v1.health.ready');

    Route::middleware('throttle:api-public')->group(function (): void {
        Route::get('/meta', MetaController::class)->name('api.v1.meta');
    });

    /*
     |----------------------------------------------------------------------
     | Customer authentication (Module 03)
     |----------------------------------------------------------------------
     |
     | Phone + OTP only. A customer never has a password, so there is no password
     | reset, no credential stuffing surface and nothing to breach — the trade is
     | that the OTP endpoints themselves are the attack surface, which is why they
     | carry their own throttles rather than the general public allowance.
     */
    Route::prefix('auth/customer')->group(function (): void {
        Route::post('/otp/request', [CustomerOtpController::class, 'request'])
            ->middleware('throttle:auth-otp')
            ->name('api.v1.auth.customer.otp.request');

        Route::post('/otp/verify', [CustomerOtpController::class, 'verify'])
            ->middleware('throttle:auth-verify')
            ->name('api.v1.auth.customer.otp.verify');

        // Not under 'auth:sanctum': there is no account yet. The registration
        // token issued by otp/verify is the credential, and it carries the
        // verified phone number with it.
        Route::post('/register', CustomerRegistrationController::class)
            ->middleware('throttle:auth-verify')
            ->name('api.v1.auth.customer.register');
    });

    /*
     |----------------------------------------------------------------------
     | Authenticated customer
     |----------------------------------------------------------------------
     |
     | Both gates, always. 'auth:sanctum' proves the token is real and unexpired;
     | 'role:customer' proves the account behind it is a customer; 'abilities'
     | proves the token was minted for the customer app rather than, say, a future
     | restaurant tablet token belonging to the same person. A restaurant or admin
     | token presented here fails on the role gate, not on a controller check
     | somebody might forget to write.
     */
    Route::middleware(['auth:sanctum', 'role:customer', 'abilities:customer', 'throttle:api-public'])
        ->group(function (): void {
            Route::get('/customer/me', [SessionController::class, 'me'])->name('api.v1.customer.me');
            Route::post('/auth/logout', [SessionController::class, 'logout'])->name('api.v1.auth.logout');

            /*
             |------------------------------------------------------------------
             | Profile and saved addresses (Module 04)
             |------------------------------------------------------------------
             |
             | No route here carries a customer id. The actor is the token, so
             | there is no ownership check to forget and no id for a caller to
             | change. Addresses are addressed by their own uuid and resolved
             | through a query already scoped to the authenticated customer.
             */
            Route::get('/customer/profile', [ProfileController::class, 'show'])
                ->name('api.v1.customer.profile.show');
            Route::patch('/customer/profile', [ProfileController::class, 'update'])
                ->name('api.v1.customer.profile.update');

            Route::prefix('customer/addresses')->group(function (): void {
                Route::get('/', [AddressController::class, 'index'])
                    ->name('api.v1.customer.addresses.index');
                Route::post('/', [AddressController::class, 'store'])
                    ->name('api.v1.customer.addresses.store');
                Route::get('/{address}', [AddressController::class, 'show'])
                    ->name('api.v1.customer.addresses.show');
                Route::patch('/{address}', [AddressController::class, 'update'])
                    ->name('api.v1.customer.addresses.update');
                Route::delete('/{address}', [AddressController::class, 'destroy'])
                    ->name('api.v1.customer.addresses.destroy');
                Route::post('/{address}/default', [AddressController::class, 'makeDefault'])
                    ->name('api.v1.customer.addresses.default');
            });

            /*
             |------------------------------------------------------------------
             | Trip planner (Module 05)
             |------------------------------------------------------------------
             |
             | Same shape, same reason: no customer id in any path. `/current` is
             | declared before `/{trip}` so it is matched as a literal rather
             | than captured as a trip id — the reverse order would send
             | "current" to ownedByOrFail() and answer 404 for the home screen.
             |
             | There is no DELETE. A trip is discarded, never removed: it is a
             | record of an intention, and Module 08's orders will point at one.
             |
             | Place lookup is authenticated too. An open endpoint on a server
             | holding a metered provider key is somebody else's free geocoder.
             */
            Route::prefix('customer/places')->group(function (): void {
                Route::get('/search', [PlaceController::class, 'search'])
                    ->name('api.v1.customer.places.search');
                Route::post('/reverse-geocode', [PlaceController::class, 'reverseGeocode'])
                    ->name('api.v1.customer.places.reverse');
                Route::get('/{place}', [PlaceController::class, 'show'])
                    ->where('place', '.*')
                    ->name('api.v1.customer.places.show');
            });

            Route::prefix('customer/trips')->group(function (): void {
                Route::get('/', [TripController::class, 'index'])
                    ->name('api.v1.customer.trips.index');
                Route::post('/', [TripController::class, 'store'])
                    ->name('api.v1.customer.trips.store');
                Route::get('/current', [TripController::class, 'current'])
                    ->name('api.v1.customer.trips.current');
                Route::get('/{trip}', [TripController::class, 'show'])
                    ->name('api.v1.customer.trips.show');
                Route::post('/{trip}/discard', [TripController::class, 'discard'])
                    ->name('api.v1.customer.trips.discard');

                // Module 06. `routes` is plural and nested under the trip
                // because a route has no existence away from one — there is no
                // /customer/routes/{id}, and so no id for a caller to walk.
                Route::get('/{trip}/routes', [TripRouteController::class, 'index'])
                    ->name('api.v1.customer.trips.routes.index');

                // POST, not GET: it writes, and it may call a billed provider. A
                // GET that can spend money is a GET that spends money on every
                // screen rebuild.
                Route::post('/{trip}/route/calculate', [TripRouteController::class, 'calculate'])
                    ->name('api.v1.customer.trips.routes.calculate');

                Route::post('/{trip}/routes/{route}/select', [TripRouteController::class, 'select'])
                    ->name('api.v1.customer.trips.routes.select');

                // Module 07. Nested under the trip for the same reason routes
                // are: "restaurants on this journey" has no meaning away from
                // one, and there is no route id in the path because the route is
                // whichever one the customer selected on their own trip.
                //
                // Its own throttle. This is the most expensive endpoint in the
                // application — a corridor query plus up to a dozen billed
                // provider calls — and the general public allowance is sized for
                // reads that cost a query.
                Route::get('/{trip}/restaurants', [TripRestaurantController::class, 'index'])
                    ->middleware('throttle:discovery')
                    ->name('api.v1.customer.trips.restaurants.index');

                // Module 09. Registered after the list, and the two cannot
                // shadow each other: `/restaurants` and `/restaurants/{uuid}`
                // differ in segment count.
                //
                // Same throttle as the list, and for a subtler reason than it
                // looks. Opening a detail screen calls no routing provider —
                // the route context comes from the list's cache — but it does
                // reach `discover()`, and a cold cache there costs exactly what
                // the list costs. Sharing the budget is what stops a loop over
                // restaurant uuids from being a cheaper way to spend it.
                Route::get('/{trip}/restaurants/{restaurant}', [TripRestaurantDetailController::class, 'show'])
                    ->middleware('throttle:discovery')
                    ->name('api.v1.customer.trips.restaurants.show');

                // Module 10. Nested under the restaurant, which is nested under
                // the trip: a menu has no meaning without a restaurant, and the
                // restaurant is only reachable through the customer's own
                // journey.
                //
                // The general authenticated allowance rather than the discovery
                // throttle. Reading a menu is a database read behind a warm
                // cache — a customer scrolling and searching one should not be
                // spending the corridor-search budget, and cannot: the
                // expensive half is already cached before either of these
                // handlers runs.
                Route::get('/{trip}/restaurants/{restaurant}/menu', [RestaurantMenuController::class, 'index'])
                    ->name('api.v1.customer.trips.restaurants.menu.index');

                Route::get('/{trip}/restaurants/{restaurant}/menu/items/{item}', [RestaurantMenuController::class, 'show'])
                    ->name('api.v1.customer.trips.restaurants.menu.items.show');

                /*
                 | The cart (Module 11).
                 |
                 | Nested under the restaurant for the same reason the menu is:
                 | a cart line is a dish from one kitchen on one journey, and
                 | the path is what proves the customer is entitled to both.
                 |
                 | Idempotency is not opt-in here — the middleware honours an
                 | `Idempotency-Key` header on any unsafe request — but it is
                 | what makes a retry after a lost response safe, so it is
                 | mentioned where somebody reading the routes will see it.
                 */
                Route::post('/{trip}/restaurants/{restaurant}/cart/items', [CartItemController::class, 'store'])
                    ->name('api.v1.customer.trips.restaurants.cart.items.store');

                Route::get('/{trip}/cart', [CartItemController::class, 'show'])
                    ->name('api.v1.customer.trips.cart.show');
            });
        });
});

/*
 | A request to an unknown endpoint answers in the documented error contract rather
 | than falling through to a bare HTML 404.
 |
 | This MUST be Route::fallback() and not Route::any('{any}'). A catch-all `any`
 | route matches before every route registered after it and matches every HTTP
 | method, so it silently shadows later routes and makes a genuine 405 impossible.
 | fallback() is consulted only when no other route matched at all.
 */
Route::fallback(static fn (): JsonResponse => ApiResponse::error(
    ApiErrorCode::NotFound,
    'Unknown API endpoint. The current API version is '.config('foodonthego.api.current_version').'.',
))->name('api.fallback');
