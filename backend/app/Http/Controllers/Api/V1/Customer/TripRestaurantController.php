<?php

declare(strict_types=1);

namespace App\Http\Controllers\Api\V1\Customer;

use App\Http\Responses\ApiResponse;
use App\Models\User;
use App\Services\Discovery\DiscoveryQuery;
use App\Services\Discovery\DiscoveryRefiner;
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
 * substitute for somebody else's.
 *
 * Module 08 added search, filters, a sort and pagination — all of them optional,
 * all of them validated by {@see DiscoveryQuery} before any work begins, and all
 * of them applied by {@see DiscoveryRefiner} to a set Module 07 has already
 * decided the customer may see. A search cannot reach the database, so a search
 * cannot resurrect a suspended restaurant.
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
        private readonly DiscoveryRefiner $refiner,
    ) {}

    public function index(Request $request, string $trip): JsonResponse
    {
        /** @var User $customer */
        $customer = $request->user();

        $found = $this->trips->ownedByOrFail($customer, $trip);

        // Read and validated before anything expensive happens, so a malformed
        // filter costs a 422 rather than a corridor search.
        $query = DiscoveryQuery::fromRequest($request);

        // The expensive half, cached per route and **not** per filter: changing
        // a cuisine or a sort reuses this entirely and calls no provider. That
        // is the module's central cost guarantee, and it is a consequence of
        // the two calls being separate rather than of anything either one does.
        $discovered = $this->discovery->discover($found, CarbonImmutable::now());

        // The cheap half: search, filter, sort, paginate — over a set that is
        // already eligible, in memory, touching neither the database nor a
        // provider.
        $refined = $this->refiner->refine($discovered, $query);

        return ApiResponse::ok($refined->toApiArray());
    }
}
