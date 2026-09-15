<?php

declare(strict_types=1);

namespace App\Http\Controllers\Api\V1\Customer;

use App\Http\Responses\ApiResponse;
use App\Models\User;
use App\Services\Restaurant\RestaurantDetailService;
use App\Services\Trip\TripService;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * One restaurant, on this customer's route.
 *
 * Nested under the trip for the same reason the list is: "how far ahead is
 * this, and what does stopping cost" has no meaning away from a journey, and a
 * detail screen that answered without one would be a generic restaurant page —
 * which is the thing this product is deliberately not.
 *
 * The restaurant is a uuid in the path and nothing else. There is no route id
 * to substitute, no coordinates to tamper with, and no flag that could turn an
 * ineligible restaurant into a visible one: eligibility is enforced by
 * {@see RestaurantDetailService} asking Module 07 what is on the route and
 * looking for this uuid in the answer.
 *
 * Read-only, and there is no sibling write endpoint. A customer cannot edit a
 * restaurant's hours, facilities, price level or availability, because no route
 * exists through which they could.
 */
final class TripRestaurantDetailController
{
    public function __construct(
        private readonly TripService $trips,
        private readonly RestaurantDetailService $detail,
    ) {}

    public function show(Request $request, string $trip, string $restaurant): JsonResponse
    {
        /** @var User $customer */
        $customer = $request->user();

        // The same single path Modules 05 to 08 use. Somebody else's journey is
        // not found rather than found-and-refused.
        $found = $this->trips->ownedByOrFail($customer, $trip);

        return ApiResponse::ok(
            $this->detail->detail($found, $restaurant, CarbonImmutable::now())->toApiArray(),
        );
    }
}
