<?php

declare(strict_types=1);

use App\Enums\ApiErrorCode;
use App\Http\Controllers\Api\V1\Auth\CustomerOtpController;
use App\Http\Controllers\Api\V1\Auth\CustomerRegistrationController;
use App\Http\Controllers\Api\V1\Auth\SessionController;
use App\Http\Controllers\Api\V1\Customer\AddressController;
use App\Http\Controllers\Api\V1\Customer\ProfileController;
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
