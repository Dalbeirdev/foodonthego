<?php

declare(strict_types=1);

namespace App\Services\Discovery;

use App\Models\Restaurant;

/**
 * The single answer to "may a customer be shown this restaurant".
 *
 * One service, called from one place, rather than a `where` clause in each
 * controller that happens to need one. The reason is not tidiness: eligibility
 * conditions scattered across call sites drift, and the way they drift is that
 * one of them is missed and a suspended restaurant appears in a list nobody was
 * looking at. There is exactly one rule, and it is here.
 *
 * The SQL half of the same rule is {@see Restaurant::scopeDiscoverable()},
 * which exists so the decision can be pushed into the index rather than applied
 * to rows already read. Two expressions of one rule is a duplication with a
 * cost, and it is paid by a test that builds every combination of the inputs and
 * asserts the scope and this service never disagree.
 */
final class RestaurantDiscoveryEligibilityService
{
    /**
     * Whether this restaurant may appear in a customer's discovery results.
     *
     * Note what is *not* here. Being closed is not ineligibility — a traveller
     * two hours away cares about a restaurant that opens at six — and neither is
     * being paused. Those are availability, they are shown as availability, and
     * the customer decides. What is here is the set of conditions under which
     * showing the restaurant at all would be wrong.
     */
    public function isEligible(Restaurant $restaurant): bool
    {
        return $this->reasonIneligible($restaurant) === null;
    }

    /**
     * Why not, for logs and for operator support.
     *
     * Never returned to a customer: "this restaurant is suspended" tells anybody
     * who can guess a name something the platform has not decided to publish.
     *
     * @return null|'deleted'|'status'|'verification'|'not_discoverable'|'no_position'
     */
    public function reasonIneligible(Restaurant $restaurant): ?string
    {
        if ($restaurant->trashed()) {
            return 'deleted';
        }

        if (! $restaurant->status->permitsDiscovery()) {
            return 'status';
        }

        if (! $restaurant->verification_status->permitsDiscovery()) {
            return 'verification';
        }

        if (! $restaurant->is_discoverable) {
            return 'not_discoverable';
        }

        // A restaurant whose coordinates have never been established cannot be
        // placed on a route, and deriving a point from its address text would
        // put a marker on a map and a customer in a field. It is not
        // discoverable until somebody has established where it actually is.
        if (! $restaurant->hasPosition()) {
            return 'no_position';
        }

        return null;
    }
}
