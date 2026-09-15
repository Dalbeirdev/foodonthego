<?php

declare(strict_types=1);

namespace App\Http\Controllers\Api\V1\Customer;

use App\Http\Requests\Customer\StoreAddressRequest;
use App\Http\Requests\Customer\UpdateAddressRequest;
use App\Http\Responses\ApiResponse;
use App\Models\CustomerAddress;
use App\Models\User;
use App\Services\Address\CustomerAddressService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Saved addresses, always scoped to the authenticated customer.
 *
 * Every method that takes an address resolves it through
 * {@see CustomerAddressService::ownedByOrFail()} rather than by route-model
 * binding. Binding would load the row first and leave the ownership check as a
 * separate step somebody could omit; this way there is one path to an address
 * and it cannot return one belonging to anybody else.
 */
final class AddressController
{
    public function __construct(private readonly CustomerAddressService $addresses) {}

    public function index(Request $request): JsonResponse
    {
        $addresses = $this->addresses->listFor($this->customer($request));

        return ApiResponse::ok(
            $addresses->map(static fn (CustomerAddress $a): array => $a->toApiArray())->all(),
        );
    }

    public function show(Request $request, string $address): JsonResponse
    {
        $found = $this->addresses->ownedByOrFail($this->customer($request), $address);

        return ApiResponse::ok($found->toApiArray());
    }

    public function store(StoreAddressRequest $request): JsonResponse
    {
        $created = $this->addresses->create(
            $this->customer($request),
            $request->addressAttributes(),
            // Null — "the request said nothing" — is not the same as false. The
            // service turns null into "default if this is the first address".
            $request->defaultPreference() === true,
        );

        return ApiResponse::created($created->toApiArray());
    }

    public function update(UpdateAddressRequest $request, string $address): JsonResponse
    {
        $customer = $this->customer($request);
        $found = $this->addresses->ownedByOrFail($customer, $address);

        $updated = $this->addresses->update(
            $customer,
            $found,
            $request->addressAttributes(),
            $request->defaultPreference(),
        );

        return ApiResponse::ok($updated->toApiArray());
    }

    public function destroy(Request $request, string $address): JsonResponse
    {
        $customer = $this->customer($request);
        $found = $this->addresses->ownedByOrFail($customer, $address);

        $this->addresses->delete($customer, $found);

        return ApiResponse::noContent();
    }

    /**
     * Makes one address the default.
     *
     * A dedicated endpoint as well as `PATCH {"is_default": true}`, because the
     * two are different intents: this one changes nothing else and is safe to
     * retry, which matters for a control somebody taps in a list.
     */
    public function makeDefault(Request $request, string $address): JsonResponse
    {
        $customer = $this->customer($request);
        $found = $this->addresses->ownedByOrFail($customer, $address);

        return ApiResponse::ok(
            $this->addresses->makeDefault($customer, $found)->toApiArray(),
        );
    }

    private function customer(Request $request): User
    {
        /** @var User $customer */
        $customer = $request->user();

        return $customer;
    }
}
