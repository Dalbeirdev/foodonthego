<?php

declare(strict_types=1);

use App\Enums\ApiErrorCode;
use App\Http\Controllers\Api\V1\Admin\AdminRestaurantController;
use App\Http\Controllers\Api\V1\Auth\CustomerOtpController;
use App\Http\Controllers\Api\V1\Auth\CustomerRegistrationController;
use App\Http\Controllers\Api\V1\Auth\SessionController;
use App\Http\Controllers\Api\V1\Customer\AddressController;
use App\Http\Controllers\Api\V1\Customer\CartController;
use App\Http\Controllers\Api\V1\Customer\CartItemController;
use App\Http\Controllers\Api\V1\Customer\CheckoutController;
use App\Http\Controllers\Api\V1\Customer\OrderController;
use App\Http\Controllers\Api\V1\Customer\PaymentController;
use App\Http\Controllers\Api\V1\Customer\PickupController;
use App\Http\Controllers\Api\V1\Customer\PlaceController;
use App\Http\Controllers\Api\V1\Customer\ProfileController;
use App\Http\Controllers\Api\V1\Customer\RestaurantMenuController;
use App\Http\Controllers\Api\V1\Customer\TripController;
use App\Http\Controllers\Api\V1\Customer\TripRestaurantController;
use App\Http\Controllers\Api\V1\Customer\TripRestaurantDetailController;
use App\Http\Controllers\Api\V1\Customer\TripRouteController;
use App\Http\Controllers\Api\V1\HealthController;
use App\Http\Controllers\Api\V1\MetaController;
use App\Http\Controllers\Api\V1\Restaurant\TenantMenuItemController;
use App\Http\Controllers\Api\V1\Restaurant\TenantOrderController;
use App\Http\Controllers\Api\V1\Restaurant\TenantRestaurantController;
use App\Http\Controllers\Api\V1\Webhooks\RazorpayWebhookController;
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

                /*
                 | Managing the cart (Module 12).
                 |
                 | Not nested under the restaurant, and that is not an
                 | oversight: a cart already knows which kitchen it belongs to,
                 | and a path that repeated it would let a request name a
                 | restaurant its cart disagrees with. The journey is what the
                 | customer has to own; everything else is read from the cart.
                 |
                 | Zero is not an argument to PATCH. A client that means
                 | "remove" says DELETE — see docs/27-cart-management.md.
                 */
                Route::get('/{trip}/cart', [CartController::class, 'show'])
                    ->name('api.v1.customer.trips.cart.show');

                Route::patch('/{trip}/cart/items/{item}', [CartController::class, 'updateItem'])
                    ->name('api.v1.customer.trips.cart.items.update');

                Route::delete('/{trip}/cart/items/{item}', [CartController::class, 'destroyItem'])
                    ->name('api.v1.customer.trips.cart.items.destroy');

                Route::delete('/{trip}/cart', [CartController::class, 'destroy'])
                    ->name('api.v1.customer.trips.cart.destroy');

                /*
                 | Price revalidation.
                 |
                 | A GET because it is a read: it re-prices every line against
                 | the live menu and reports, and it writes nothing at all. A
                 | POST would suggest otherwise, and the one thing this endpoint
                 | must never be understood to do is correct a cart on the
                 | customer's behalf.
                 */
                Route::get('/{trip}/cart/revalidate', [CartController::class, 'revalidate'])
                    ->name('api.v1.customer.trips.cart.revalidate');

                /*
                 | Pickup time (Module 13).
                 |
                 | Options is a POST, and deliberately. It is a calculation over
                 | live state whose answers are short-lived and whose side
                 | effect is writing those answers down; a GET would invite a
                 | client, a proxy or a browser to treat a menu of pickup times
                 | as something worth keeping.
                 |
                 | Selection is a PUT because there is one pickup time per cart
                 | and choosing again replaces it. Neither endpoint accepts a
                 | timestamp — the client holds an opaque id and the server
                 | holds what it meant, which is the whole of why there is
                 | nothing here to tamper with.
                 |
                 | No order is created by either. No payment. No reservation.
                 */
                Route::post('/{trip}/cart/pickup-options', [PickupController::class, 'options'])
                    ->name('api.v1.customer.trips.cart.pickup.options');

                Route::put('/{trip}/cart/pickup-selection', [PickupController::class, 'select'])
                    ->name('api.v1.customer.trips.cart.pickup.select');

                /*
                 | Pre-checkout validation.
                 |
                 | A POST that writes nothing, which is the one place in this
                 | file the verb is not about side effects. It renders a
                 | point-in-time judgement — may this be paid for — and a GET
                 | invites a client, a proxy or a browser to reuse a yes that
                 | was true a minute ago. Module 12's revalidate reports facts
                 | and is a GET; a stale fact is a fact, and a stale judgement
                 | is somebody at a payment screen for a kitchen that has shut.
                 |
                 | Nothing is created here and nothing is reserved. Module 14
                 | will check all of it again.
                 */
                Route::post('/{trip}/cart/pre-checkout-validate', [PickupController::class, 'preCheckout'])
                    ->name('api.v1.customer.trips.cart.precheckout');

                /*
                 | Checkout (Module 14).
                 |
                 | Prepare answers "what is being bought, when, and for how
                 | much". Validate answers "is all of that still true". Both
                 | POST, for the caching reason this file already records
                 | against pre-checkout: these render a judgement, and a cached
                 | yes is somebody at a payment screen for a kitchen that shut.
                 |
                 | NEITHER READS MONEY FROM THE REQUEST. There is no field in
                 | which a subtotal, a tax figure, a discount or a total could
                 | arrive, because nothing below looks for one.
                 |
                 | No order is created here. No payment. No Razorpay object.
                 | Module 15 owns that boundary.
                 */
                Route::post('/{trip}/checkout/prepare', [CheckoutController::class, 'prepare'])
                    ->name('api.v1.customer.trips.checkout.prepare');

                Route::post('/{trip}/checkout/{checkout}/validate', [CheckoutController::class, 'validate'])
                    ->name('api.v1.customer.trips.checkout.validate');

                /*
                 | Placing the order (Module 15).
                 |
                 | The quote becomes an order. Still no amount in the request:
                 | the price is the one the server quoted, read from the quote
                 | row, and there is no field through which another could
                 | arrive.
                 |
                 | Idempotent. A double tap answers 200 with the order that
                 | already exists rather than 201 with a second one, and the
                 | unique index on orders.checkout_quote_id is what makes that
                 | true even when two requests race.
                 */
                Route::post('/{trip}/checkout/{checkout}/order', [OrderController::class, 'place'])
                    ->name('api.v1.customer.trips.checkout.order');
            });

            /*
             |------------------------------------------------------------------
             | Orders and payment (Module 15)
             |------------------------------------------------------------------
             |
             | NEITHER PAYMENT ROUTE ACCEPTS AN AMOUNT. `intent` reads the
             | order's total; `verify` takes three provider identifiers and
             | nothing else. A request carrying `amount` parses to the same
             | thing as one without it.
             |
             | `verify` relays what the app was told by the provider. It is
             | checked rather than believed — signature, then binding, then
             | amount, against the provider itself — and nothing a client can
             | post is capable of moving an order to PAID on its own say-so.
             */
            Route::get('/customer/orders', [OrderController::class, 'index'])
                ->name('api.v1.customer.orders.index');

            Route::get('/customer/orders/{order}', [OrderController::class, 'show'])
                ->name('api.v1.customer.orders.show');

            Route::post('/customer/orders/{order}/payment-intent', [PaymentController::class, 'intent'])
                ->name('api.v1.customer.orders.payment.intent');

            Route::post('/customer/orders/{order}/payment/verify', [PaymentController::class, 'verify'])
                ->name('api.v1.customer.orders.payment.verify');
        });

    /*
     |--------------------------------------------------------------------------
     | The restaurant surface — tenant-scoped (Module 14T)
     |--------------------------------------------------------------------------
     |
     | Not the operator dashboard. This is the smallest surface that makes tenant
     | isolation testable the way it must be tested: over HTTP, with a real token,
     | substituting an identifier that belongs to somebody else. A service method
     | cannot be IDOR-tested; only a route can.
     |
     | THREE GATES, IN ORDER, AND EACH DOES A DIFFERENT JOB.
     |
     |   auth:sanctum   — is there a session at all
     |   role:...       — is this the kind of account that belongs on this surface
     |   the tenant scope + policy, inside every controller — which restaurants,
     |                    and how deeply
     |
     | The role gate alone would let any restaurant_manager reach every
     | restaurant on the platform, which is precisely the failure this module
     | exists to prevent. It is a surface check, never a tenancy check.
     |
     | No login mints a token for these roles yet, by design — the isolation is
     | what is being built, and authenticating an operator is a later module. The
     | boundary is here first so that login arrives behind something already
     | tested rather than alongside something new.
     */
    Route::middleware([
        'auth:sanctum',
        'role:restaurant_owner,restaurant_manager,restaurant_staff',
        'throttle:api-public',
    ])->prefix('restaurant')->group(function (): void {
        Route::get('/restaurants', [TenantRestaurantController::class, 'index'])
            ->name('api.v1.restaurant.restaurants.index');

        Route::get('/restaurants/{restaurant}', [TenantRestaurantController::class, 'show'])
            ->name('api.v1.restaurant.restaurants.show');

        Route::patch('/restaurants/{restaurant}', [TenantRestaurantController::class, 'update'])
            ->name('api.v1.restaurant.restaurants.update');

        Route::get('/restaurants/{restaurant}/menu/items', [TenantMenuItemController::class, 'index'])
            ->name('api.v1.restaurant.menu.items.index');

        /*
         | The indirect path, and the reason this route exists.
         |
         | A menu item by its own id, with no restaurant anywhere in the request.
         | Nothing here names a tenant, so nothing here can be trusted to scope
         | one — the controller reaches back through the owning restaurant
         | instead. This is the shape that leaks in real systems, and it is
         | tested by name.
         */
        Route::get('/menu/items/{item}', [TenantMenuItemController::class, 'show'])
            ->name('api.v1.restaurant.menu.items.show');

        /*
         | Orders, tenant-scoped (Module 15).
         |
         | `show` is the indirect path again, and this time it carries a
         | customer's name and what they paid. An unscoped lookup here hands one
         | restaurant's takings to another.
         */
        Route::get('/orders', [TenantOrderController::class, 'index'])
            ->name('api.v1.restaurant.orders.index');

        Route::get('/orders/{order}', [TenantOrderController::class, 'show'])
            ->name('api.v1.restaurant.orders.show');
    });

    /*
     |--------------------------------------------------------------------------
     | The platform surface — grant-scoped (Module 14T)
     |--------------------------------------------------------------------------
     |
     | A super administrator with no grant reaches nothing. That is the whole
     | assertion, and it is the one that stops being true the moment somebody
     | adds a policy `before()` hook that returns true for an admin.
     */
    Route::middleware([
        'auth:sanctum',
        'role:support_agent,admin,super_admin',
        'throttle:api-public',
    ])->prefix('admin')->group(function (): void {
        Route::get('/restaurants', [AdminRestaurantController::class, 'index'])
            ->name('api.v1.admin.restaurants.index');
    });

    /*
     |--------------------------------------------------------------------------
     | Provider webhooks (Module 15)
     |--------------------------------------------------------------------------
     |
     | Unauthenticated, and it has to be: Razorpay has no account on this
     | platform and no token to present. What replaces authentication is an HMAC
     | over the raw request body, checked before anything else happens and before
     | anything at all is written.
     |
     | NOT behind `auth:sanctum`, and equally NOT behind a shared secret in the
     | URL. A secret in a path ends up in access logs, proxy logs and error
     | reports; the signature does not.
     |
     | The throttle is deliberately the public one rather than something tighter.
     | A provider retrying a burst of deliveries after an outage is normal
     | traffic, and rate-limiting it into failure would turn a brief outage into
     | a set of orders permanently marked unpaid.
     */
    Route::post('/webhooks/razorpay', RazorpayWebhookController::class)
        ->middleware('throttle:api-public')
        ->name('api.v1.webhooks.razorpay');
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
