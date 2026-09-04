<?php

declare(strict_types=1);

namespace App\Http\Controllers\Api\V1\Customer;

use App\Http\Responses\ApiResponse;
use App\Models\User;
use App\Services\Discovery\RestaurantDiscoveryService;
use App\Services\Trip\TripService;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Restaurants along a trip's selected route.
 *
 * One endpoint, one verb, and no identifier in the path but the trip's own. The
 * trip is resolved through {@see TripService::ownedByOrFail()} — the same single
 * path Modules 05 and 06 use — so a journey belonging to somebody else is not
 * found rather than found-and-refused, and there is nothing in the request for a
 * caller to tamper with.
 *
 * Note what is **not** a parameter. The route is not: it is whichever route the
 * customer selected, read from their own trip, so there is no route id to
 * substitute for somebody else's. Filters and sort orders are not: they belong
 * to Module 08, and adding them here would fix their shape before that module
 * has been designed.
 *
 * `GET` rather than `POST` even though it can reach a billed provider. Discovery
 * is a read — it writes nothing, and a customer reopening it expects what they
 * saw before. The spending is controlled where it should be, by a cache and a
 * hard evaluation budget, rather than by making the verb inconvenient.
 */
final class TripRestaurantController
{
    public function __construct(
        private readonly TripService $trips,
        private readonly RestaurantDiscoveryService $discovery,
    ) {}

    public function index(Request $request, string $trip): JsonResponse
    {
        /** @var User $customer */
        $customer = $request->user();

        $found = $this->trips->ownedByOrFail($customer, $trip);

        $result = $this->discovery->discover($found, CarbonImmutable::now());

        return ApiResponse::ok($result->toApiArray());
    }
}
