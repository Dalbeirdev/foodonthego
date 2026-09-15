<?php

declare(strict_types=1);

namespace App\Http\Controllers\Api\V1\Customer;

use App\Http\Requests\Customer\UpdateProfileRequest;
use App\Http\Responses\ApiResponse;
use App\Models\User;
use App\Services\Profile\CustomerProfileService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * The signed-in customer's own profile.
 *
 * There is no `{customerId}` in any route here, and that is deliberate: a
 * self-service endpoint that takes an id is one ownership check away from being
 * an IDOR, and the check can be forgotten. Taking the actor from the token means
 * there is nothing to forget.
 */
final class ProfileController
{
    public function __construct(private readonly CustomerProfileService $profiles) {}

    public function show(Request $request): JsonResponse
    {
        /** @var User $customer */
        $customer = $request->user();

        return ApiResponse::ok($customer->toCustomerProfile());
    }

    public function update(UpdateProfileRequest $request): JsonResponse
    {
        /** @var User $customer */
        $customer = $request->user();

        // `validated()`, not `all()`. The request declares no rule for phone,
        // role or status, so those keys are not in what comes back — a body
        // carrying them is accepted and ignored rather than rejected, because
        // rejecting would tell a prober which field names are interesting.
        $updated = $this->profiles->update($customer, $request->validated());

        return ApiResponse::ok($updated->toCustomerProfile());
    }
}
