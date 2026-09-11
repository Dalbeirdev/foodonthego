<?php

declare(strict_types=1);

namespace App\Http\Controllers\Api\V1\Customer;

use App\Enums\ApiErrorCode;
use App\Exceptions\ApiException;
use App\Http\Responses\ApiResponse;
use App\Models\User;
use App\Services\Cart\CartService;
use App\Services\Cart\CustomizationSelection;
use App\Services\Cart\CustomizationValidator;
use App\Services\Cart\MenuItemPricingService;
use App\Services\Menu\CustomerMenuService;
use App\Services\Restaurant\RestaurantDetailService;
use App\Services\Trip\TripService;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Adding a configured dish to a customer's cart.
 *
 * The one thing this controller does not do is decide anything about money.
 * The request carries selections — which dish, which size, which options, how
 * many — and every figure that ends up in the database is calculated here from
 * rows read in this request. A client cannot send a price, because there is no
 * field to send it in and nothing that would read it.
 *
 * The order of the work below is the security model, and it is deliberate:
 *
 *   trip ownership → restaurant eligibility → ordering state → item →
 *   configuration validity → availability → price → cart rules → write
 *
 * Ownership before eligibility, because somebody else's journey is not found
 * rather than found-and-refused. Eligibility before the item, because a
 * suspended restaurant's menu must not be reachable by anyone who has an item
 * id. Availability before price, because pricing something the kitchen has run
 * out of is arithmetic nobody needs.
 *
 * The write is one transaction, so a line without its options cannot exist.
 *
 * Adding to a cart calls no routing provider. Eligibility goes through Module
 * 07's cached discovery result, exactly as the menu screen does.
 */
final class CartItemController
{
    public function __construct(
        private readonly TripService $trips,
        private readonly RestaurantDetailService $detail,
        private readonly CustomerMenuService $menu,
        private readonly CustomizationValidator $validator,
        private readonly MenuItemPricingService $pricing,
        private readonly CartService $carts,
    ) {}

    /**
     * @throws ApiException
     */
    public function store(Request $request, string $trip, string $restaurant): JsonResponse
    {
        /** @var User $customer */
        $customer = $request->user();

        $found = $this->trips->ownedByOrFail($customer, $trip);

        $now = CarbonImmutable::now();
        $context = $this->detail->orderingContext($found, $restaurant, $now);

        // Whether a cart may be filled at all. A paused kitchen and a closed
        // one are both refused: a cart line is a promise to collect food, and
        // one nobody is cooking is a promise the platform cannot keep. Browsing
        // stays open, which is Module 10's business and unaffected.
        if (! $context->ordering->canOrder()) {
            throw new ApiException(
                ApiErrorCode::RestaurantNotAcceptingOrders,
                'This restaurant is not accepting orders right now.',
                ['ordering_state' => $context->ordering->value],
            );
        }

        // Read before anything is looked up, so a malformed body is refused
        // without a database round trip.
        $selection = CustomizationSelection::fromRequest($request);

        $menuItem = $this->menu->itemForCustomization(
            $context->discovered->restaurant,
            $selection->itemUuid,
        );

        if ($menuItem === null) {
            // No such dish, another restaurant's dish, or one withdrawn from
            // the menu. Answered identically, as everywhere else in this
            // product: telling them apart lets anybody with a list of ids map
            // a competitor's menu.
            throw new ApiException(
                ApiErrorCode::ItemNotFound,
                'That menu item could not be found.',
            );
        }

        $resolved = $this->validator->validate($menuItem, $selection);
        $priced = $this->pricing->price($resolved);

        // Never more than the customer was shown. A dish that has gone up since
        // the screen loaded is refused with the new figure, so they agree to it
        // before it is charged.
        $this->pricing->assertQuoteStillHolds($priced, $selection->quotedUnitPriceMinor);

        $addition = $this->carts->add(
            customer: $customer,
            trip: $found,
            restaurant: $context->discovered->restaurant,
            resolved: $resolved,
            priced: $priced,
        );

        return ApiResponse::created($addition->toApiArray());
    }
}
