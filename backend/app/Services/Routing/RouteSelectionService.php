<?php

declare(strict_types=1);

namespace App\Services\Routing;

use App\Enums\ApiErrorCode;
use App\Enums\RouteStatus;
use App\Exceptions\ApiException;
use App\Models\Trip;
use App\Models\TripRoute;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

/**
 * Choosing which of a trip's routes is the one.
 *
 * Small, and load-bearing: Module 07 will search for restaurants along
 * *the selected route*, so "which one is selected" stops being a display
 * preference and becomes the input to everything downstream.
 */
final class RouteSelectionService
{
    /**
     * Selects a route by its public id.
     *
     * Scoped to the trip in the query itself, so a route belonging to somebody
     * else's journey is not found rather than found-and-refused. There is no
     * branch here that could accidentally be reached with another customer's
     * row in hand.
     *
     * @throws ApiException
     */
    public function select(Trip $trip, string $routeUuid): TripRoute
    {
        $route = TripRoute::query()
            ->forTrip($trip)
            ->where('uuid', $routeUuid)
            ->first();

        if ($route === null) {
            // The same 404 a route that never existed gets. Distinguishing them
            // would confirm which ids are real.
            Log::info('route.selection_denied', [
                'trip_uuid' => $trip->uuid,
            ]);

            throw new ApiException(
                ApiErrorCode::RouteNotFound,
                'That route is no longer available for this journey.',
            );
        }

        if (! $trip->route_status->hasUsableRoute()) {
            throw new ApiException(
                ApiErrorCode::RouteSelectionInvalid,
                'This journey has no calculated route to choose from.',
            );
        }

        // A route calculated for endpoints that have since moved must not become
        // the selected one — that is precisely how a stale route survives into
        // the next module.
        if (! $route->matchesEndpointsOf($trip)) {
            throw new ApiException(
                ApiErrorCode::RouteStale,
                'This journey has changed since that route was worked out. Calculate it again.',
            );
        }

        if ($route->is_selected) {
            // Idempotent rather than an error. Selecting the route that is
            // already selected is what a double tap looks like.
            return $route;
        }

        return DB::transaction(function () use ($trip, $route): TripRoute {
            // Cleared first, then set. The database holds a unique index over
            // "the trip id, when selected", so setting the new one before
            // clearing the old would be refused by the engine — which is the
            // invariant doing its job, but the wrong order to meet it in.
            TripRoute::query()
                ->forTrip($trip)
                ->where('is_selected', true)
                ->update(['is_selected' => false]);

            $route->forceFill(['is_selected' => true])->save();

            return $route->refresh();
        });
    }

    /**
     * The selected route for a trip, or null.
     *
     * Null for a trip with no usable route *and* for one whose routes no longer
     * match its endpoints — the caller cannot tell the difference and should not
     * have to: in both cases there is nothing to show.
     */
    public function selected(Trip $trip): ?TripRoute
    {
        if ($trip->route_status !== RouteStatus::Ready) {
            return null;
        }

        $route = TripRoute::query()->forTrip($trip)->where('is_selected', true)->first();

        return $route !== null && $route->matchesEndpointsOf($trip) ? $route : null;
    }
}
