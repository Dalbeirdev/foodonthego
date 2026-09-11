<?php

declare(strict_types=1);

namespace App\Http\Controllers\Api\V1\Customer;

use App\Exceptions\ApiException;
use App\Http\Responses\ApiResponse;
use App\Services\Payments\PaymentService;
use App\Support\Orders\OrderPresenter;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Starting a payment, and reporting back what happened.
 *
 * **Neither endpoint accepts an amount.** There is no field for one, so a
 * request carrying `amount` parses to exactly the same thing as a request
 * without it. That is the same rule Module 11 established for cart pricing, and
 * it matters more here: this is the last point at which a client could try to
 * decide what it owes.
 */
final class PaymentController
{
    public function __construct(
        private readonly PaymentService $payments,
    ) {}

    /**
     * The provider order to open a checkout against.
     *
     * @throws ApiException
     */
    public function intent(Request $request, string $order): JsonResponse
    {
        $found = OrderController::ownedOrFail($request, $order);

        $payment = $this->payments->createIntent($found);

        return ApiResponse::ok(OrderPresenter::intent($found, $payment));
    }

    /**
     * What the app came back with after the customer paid.
     *
     * The three fields are the provider's, relayed by a device this server does
     * not control. They are checked — signature, then binding, then amount — and
     * the order moves only if the provider itself agrees. A caller that posts a
     * plausible-looking triple gets a 422 and no order state change.
     *
     * @throws ApiException
     */
    public function verify(Request $request, string $order): JsonResponse
    {
        $found = OrderController::ownedOrFail($request, $order);

        $validated = $request->validate([
            'provider_order_id' => ['required', 'string', 'max:80'],
            'provider_payment_id' => ['required', 'string', 'max:80'],
            'signature' => ['required', 'string', 'max:255'],
        ]);

        $this->payments->verifyClientCallback(
            $found,
            $validated['provider_order_id'],
            $validated['provider_payment_id'],
            $validated['signature'],
        );

        $found->refresh()->loadMissing(['items.modifiers', 'restaurant']);

        return ApiResponse::ok(OrderPresenter::detail($found));
    }
}
