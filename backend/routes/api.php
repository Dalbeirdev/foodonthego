<?php

declare(strict_types=1);

use App\Enums\ApiErrorCode;
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
| Module 01 deliberately ships only health and meta. Feature routes arrive with
| the modules that implement them, each behind the middleware it needs.
*/

Route::prefix('v1')->group(function (): void {
    // Unauthenticated and unthrottled: an orchestrator polling liveness must not be
    // able to rate-limit itself out of a healthy verdict.
    Route::get('/health/live', [HealthController::class, 'live'])->name('api.v1.health.live');
    Route::get('/health/ready', [HealthController::class, 'ready'])->name('api.v1.health.ready');

    Route::middleware('throttle:api-public')->group(function (): void {
        Route::get('/meta', MetaController::class)->name('api.v1.meta');
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
