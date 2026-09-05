<?php

declare(strict_types=1);

namespace App\Services\Restaurant;

use App\Enums\ApiErrorCode;
use App\Enums\RestaurantOrderingState;
use App\Exceptions\ApiException;
use App\Models\Restaurant;
use App\Models\Trip;
use App\Services\Discovery\DiscoveredRestaurant;
use App\Services\Discovery\RestaurantAvailabilityService;
use App\Services\Discovery\RestaurantDiscoveryEligibilityService;
use App\Services\Discovery\RestaurantDiscoveryService;
use Carbon\CarbonImmutable;

/**
 * One restaurant, on this customer's route.
 *
 * The whole design is in the first line of {@see detail()}: it asks Module 07
 * what is on the route, and looks for the requested restaurant in the answer.
 *
 * Three things follow from that, none of which is a rule anybody has to
 * remember:
 *
 * 1. **Eligibility cannot be bypassed.** A suspended, unverified, disabled or
 *    permanently closed restaurant is not in the discovery result, so knowing
 *    its uuid buys nothing. There is no second query here with its own `where`
 *    clauses to get wrong.
 *
 * 2. **Opening this screen calls no routing provider.** `discover()` is cached
 *    per route and is the only thing in the application that can reach one. A
 *    customer tapping through five restaurants spends nothing.
 *
 * 3. **The figures match the card they tapped.** The detour and distance-ahead
 *    on this screen are the same objects the list rendered, not a second
 *    calculation that might round differently.
 *
 * The profile half — description, photographs, the weekly schedule — is a
 * separate, cheap read, because discovery deliberately does not load media or
 * pay for a fortnight's hours arithmetic for twenty restaurants at once.
 */
final class RestaurantDetailService
{
    public function __construct(
        private readonly RestaurantDiscoveryService $discovery,
        private readonly RestaurantDiscoveryEligibilityService $eligibility,
        private readonly RestaurantAvailabilityService $availability,
        private readonly RestaurantHoursService $hours,
    ) {}

    /**
     * @throws ApiException
     */
    public function detail(Trip $trip, string $restaurantUuid, CarbonImmutable $now): RestaurantDetail
    {
        // Not validated as a uuid first: a malformed identifier simply matches
        // nothing below, and answering it differently would tell a prober that
        // their guess had the right shape.
        $discovered = $this->onRoute($trip, $restaurantUuid, $now);

        // Everything the list did not need. One query for the row with its
        // media, cuisines, facilities and hours — not four, and not one per
        // relation.
        $restaurant = $this->profile($restaurantUuid);

        // The row that was just read is the authority on whether this is still
        // orderable. The discovery result may be up to five minutes old, and a
        // restaurant that paused its kitchen in the meantime must not be
        // presented as accepting orders.
        $discovered = $discovered->withRestaurant($restaurant);

        $availability = $this->availability->availabilityOf($restaurant, $now);

        return new RestaurantDetail(
            discovered: $discovered->withAvailability($availability),
            ordering: RestaurantOrderingState::resolve($restaurant->status, $availability),
            todayHours: ['windows' => $this->hours->today($restaurant, $now)],
            weeklyHours: $this->hours->week($restaurant, $now),
            currentWindow: $this->hours->currentWindow($restaurant, $now),
            nextOpenAt: $this->hours->nextOpenAt($restaurant, $now),
            timezone: $restaurant->timezone
                ?: (string) config('foodonthego.discovery.default_timezone'),
            generatedAt: $now,
            routeFromCache: $this->lastDiscoveryWasCached,
        );
    }

    private bool $lastDiscoveryWasCached = false;

    /**
     * The restaurant's place on this customer's route, or a refusal.
     *
     * @throws ApiException
     */
    private function onRoute(
        Trip $trip,
        string $restaurantUuid,
        CarbonImmutable $now,
    ): DiscoveredRestaurant {
        // Throws ROUTE_NOT_READY on a trip with no usable selected route,
        // exactly as the discovery list does. A detail screen reached without a
        // route is the same problem with the same answer.
        $result = $this->discovery->discover($trip, $now);

        $this->lastDiscoveryWasCached = $result->fromCache;

        foreach ($result->restaurants as $found) {
            if ($found->restaurant->uuid === $restaurantUuid) {
                return $found;
            }
        }

        // Not on the route. Two reasons, and they are told apart because the
        // customer's next move differs: a restaurant that exists and trades is
        // simply somewhere else, while one they were looking at a minute ago
        // has been withdrawn.
        throw $this->absent($restaurantUuid);
    }

    private function absent(string $restaurantUuid): ApiException
    {
        $restaurant = Restaurant::query()
            ->where('uuid', $restaurantUuid)
            ->first();

        if ($restaurant === null) {
            return new ApiException(
                ApiErrorCode::RestaurantNotFound,
                'That restaurant could not be found.',
            );
        }

        // Real, and no longer something a customer may see. Answered 404 like
        // the case above — a different status here would let anyone with a list
        // of uuids discover which businesses this platform has suspended.
        if (! $this->eligibility->isEligible($restaurant)) {
            return new ApiException(
                ApiErrorCode::RestaurantUnavailable,
                'This restaurant is no longer available.',
            );
        }

        // Real, trading, and not on this journey. Its detour and distance-ahead
        // do not exist for this route, and inventing them is the one thing this
        // product must never do.
        return new ApiException(
            ApiErrorCode::RestaurantOutsideRoute,
            'That restaurant is not on this route.',
        );
    }

    /**
     * The profile half: one query, every relation the screen needs.
     *
     * @throws ApiException
     */
    private function profile(string $restaurantUuid): Restaurant
    {
        $restaurant = Restaurant::query()
            ->with(['cuisines', 'facilities', 'openingHours', 'media'])
            ->where('uuid', $restaurantUuid)
            ->first();

        if ($restaurant === null) {
            // Deleted between the discovery read and this one. Vanishingly
            // rare, and answered rather than allowed to become a null
            // dereference three frames down.
            throw new ApiException(
                ApiErrorCode::RestaurantNotFound,
                'That restaurant could not be found.',
            );
        }

        return $restaurant;
    }
}
