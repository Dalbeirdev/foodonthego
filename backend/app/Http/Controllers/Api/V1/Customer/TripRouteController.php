<?php

declare(strict_types=1);

namespace App\Http\Controllers\Api\V1\Customer;

use App\Http\Responses\ApiResponse;
use App\Models\Trip;
use App\Models\TripRoute;
use App\Models\User;
use App\Services\Routing\RouteCalculationService;
use App\Services\Routing\RouteSelectionService;
use App\Services\Trip\TripService;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Routes for a trip, always scoped to the authenticated customer.
 *
 * No method uses route-model binding and no path carries a customer id: the trip
 * is resolved through {@see TripService::ownedByOrFail()}, which is the same
 * single path Module 05 uses, and the route is then resolved *within that trip*.
 * A route belonging to somebody else's journey is not found rather than
 * found-and-refused.
 *
 * Nothing here accepts a distance, a duration, a polyline or a selection flag.
 * The only thing a customer sends is which of the routes we calculated they
 * want; everything else comes from the provider by way of the backend.
 */
final class TripRouteController
{
    public function __construct(
        private readonly TripService $trips,
        private readonly RouteCalculationService $routes,
        private readonly RouteSelectionService $selection,
    ) {}

    /**
     * The routes already calculated for a trip.
     *
     * Deliberately does **not** calculate. A GET that could spend money is a GET
     * that spends money every time a screen rebuilds, and this module's largest
     * cost risk is exactly that.
     */
    public function index(Request $request, string $trip): JsonResponse
    {
        $found = $this->trips->ownedByOrFail($this->customer($request), $trip);

        // Checked on read as well as on write, so a route cannot outlive an
        // endpoint change made by any path.
        $this->routes->invalidateIfEndpointsChanged($found);

        return ApiResponse::ok($this->payload($found));
    }

    /**
     * Calculates a route, or returns the one already known.
     *
     * POST rather than GET because it may call a billed third party and it
     * writes. `refresh=true` skips the freshness window — for an explicit "work
     * it out again", never for an ordinary screen open.
     */
    public function calculate(Request $request, string $trip): JsonResponse
    {
        $found = $this->trips->ownedByOrFail($this->customer($request), $trip);

        $this->routes->invalidateIfEndpointsChanged($found);

        $this->routes->calculate(
            $found,
            CarbonImmutable::now(),
            force: $request->boolean('refresh'),
        );

        return ApiResponse::ok($this->payload($found->refresh()));
    }

    /** Chooses one of the calculated routes. */
    public function select(Request $request, string $trip, string $route): JsonResponse
    {
        $found = $this->trips->ownedByOrFail($this->customer($request), $trip);

        $this->routes->invalidateIfEndpointsChanged($found);

        $this->selection->select($found->refresh(), $route);

        return ApiResponse::ok($this->payload($found->refresh()));
    }

    /**
     * One shape for all three endpoints.
     *
     * The trip travels with its routes so a client never has to hold two
     * responses together to know what to draw — and so `route_status` and the
     * routes can never disagree in something a screen has already rendered.
     *
     * @return array<string, mixed>
     */
    private function payload(Trip $trip): array
    {
        $routes = $this->routes->routesFor($trip);

        return [
            'trip' => $trip->toApiArray(),
            'routes' => $routes
                ->map(static fn (TripRoute $route): array => $route->toApiArray())
                ->values()
                ->all(),
        ];
    }

    private function customer(Request $request): User
    {
        /** @var User $customer */
        $customer = $request->user();

        return $customer;
    }
}
