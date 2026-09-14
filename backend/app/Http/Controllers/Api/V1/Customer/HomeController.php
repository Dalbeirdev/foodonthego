<?php

declare(strict_types=1);

namespace App\Http\Controllers\Api\V1\Customer;

use App\Http\Controllers\Controller;
use App\Http\Responses\ApiResponse;
use App\Models\Order;
use App\Models\User;
use App\Services\Orders\OrderStateMachine;
use App\Services\Trip\TripService;
use App\Support\Orders\OrderPresenter;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Everything the Home screen needs, in one request.
 *
 * ## Why this exists
 *
 * Home asks four questions — who is this, do they have a journey running, do
 * they have an order running, is anything waiting for them. Answered separately
 * that is four round trips before the first useful pixel, on a connection that
 * by definition belongs to somebody driving.
 *
 * ## Why it is not a new feature
 *
 * It composes and does not decide. The current journey comes from
 * {@see TripService::currentFor()}, which is the same call the Trips tab makes;
 * "active" for an order is {@see OrderStateMachine::activeStatuses()}, which is
 * a property of the transition table rather than a list written here, so an
 * order stops being active the moment its last outgoing edge is removed and
 * this class is not edited. Both are presented through the same presenters the
 * dedicated endpoints use, so Home and the Orders tab cannot describe the same
 * order differently.
 *
 * ## What it costs
 *
 * Nothing external. No routing provider, no places provider, no payment
 * gateway. Opening Home must not spend money, and a test asserts it does not:
 * a customer who opens the app twenty times while parked has cost nothing.
 */
final class HomeController extends Controller
{
    public function __construct(private readonly TripService $trips) {}

    public function __invoke(Request $request): JsonResponse
    {
        /** @var User $customer */
        $customer = $request->user();

        return ApiResponse::ok([
            /*
             | The profile, unchanged from GET /customer/profile.
             |
             | Home needs a name to greet with, and taking it from the same
             | method the profile screen uses means the greeting cannot drift
             | from the profile — and that a field redacted there is redacted
             | here, without this controller having to know which.
             */
            'customer' => $customer->toCustomerProfile(),

            /*
             | The journey in progress, or null.
             |
             | Null is a first-class answer and the client renders an empty
             | state for it. It is not an error and must not be reported as one.
             */
            'active_trip' => $this->trips->currentFor($customer)?->toApiArray(),

            'active_order' => $this->activeOrder($customer),

            /*
             | Notifications do not exist yet — no table, no service, no
             | endpoint. `supported: false` says so in the payload rather than
             | returning a zero that a client would render as a real "nothing
             | waiting for you". A badge is drawn from `unread`, which is null,
             | so nothing is drawn. When notifications are built this becomes
             | true and a number, and no client changes.
             */
            'notification_summary' => [
                'supported' => false,
                'unread' => null,
            ],
        ]);
    }

    /**
     * The one order the customer most needs to see, or null.
     *
     * Soonest pickup wins, not most recently placed — a customer with two live
     * orders cares about the one they have to collect next. The id breaks ties
     * so two requests in a row cannot disagree.
     *
     * @return array<string, mixed>|null
     */
    private function activeOrder(User $customer): ?array
    {
        $order = Order::query()
            ->where('customer_id', $customer->id)
            ->whereNotNull('placed_at')
            ->whereIn('status', OrderStateMachine::activeStatuses())
            // Without this the presenter fetches the restaurant separately, so
            // the endpoint built to remove round trips would add one.
            ->with('restaurant')
            ->orderBy('pickup_start_at')
            ->orderBy('id')
            ->first();

        return $order === null ? null : OrderPresenter::summary($order);
    }
}
