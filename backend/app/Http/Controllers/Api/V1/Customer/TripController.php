<?php

declare(strict_types=1);

namespace App\Http\Controllers\Api\V1\Customer;

use App\Enums\ApiErrorCode;
use App\Enums\TripStatus;
use App\Exceptions\ApiException;
use App\Http\Requests\Customer\StoreTripRequest;
use App\Http\Responses\ApiResponse;
use App\Models\Trip;
use App\Models\User;
use App\Services\Trip\TripService;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Trips, always scoped to the authenticated customer.
 *
 * No method uses route-model binding: binding would load the row and leave the
 * ownership check as a separate step somebody could omit.
 * {@see TripService::ownedByOrFail()} is the only path to a trip.
 */
final class TripController
{
    public function __construct(private readonly TripService $trips) {}

    public function index(Request $request): JsonResponse
    {
        $trips = $this->trips->listFor($this->customer($request), $this->statusFilter($request));

        return ApiResponse::ok(
            $trips->map(static fn (Trip $t): array => $t->toApiArray())->all(),
        );
    }

    /**
     * The customer's current trip, or null.
     *
     * Its own endpoint rather than "the first item of the list", because the home
     * screen wants exactly this and a home screen that downloads every trip to
     * render one gets slower the longer somebody uses the app.
     */
    public function current(Request $request): JsonResponse
    {
        $trip = $this->trips->currentFor($this->customer($request));

        return ApiResponse::ok($trip?->toApiArray());
    }

    public function show(Request $request, string $trip): JsonResponse
    {
        $found = $this->trips->ownedByOrFail($this->customer($request), $trip);

        return ApiResponse::ok($found->toApiArray());
    }

    public function store(StoreTripRequest $request): JsonResponse
    {
        $created = $this->trips->create(
            $this->customer($request),
            $request->tripAttributes(),
            CarbonImmutable::now(),
        );

        return ApiResponse::created($created->toApiArray());
    }

    /**
     * Discards a trip.
     *
     * A POST to a named action rather than `PATCH {"status": "CANCELLED"}`.
     * `status` is never an accepted field anywhere in this module, so there is no
     * request shape that can set a trip to an arbitrary state.
     */
    public function discard(Request $request, string $trip): JsonResponse
    {
        $customer = $this->customer($request);
        $found = $this->trips->ownedByOrFail($customer, $trip);

        return ApiResponse::ok(
            $this->trips->discard($customer, $found, CarbonImmutable::now())->toApiArray(),
        );
    }

    /** @throws ApiException */
    private function statusFilter(Request $request): ?TripStatus
    {
        $raw = $request->query('status');

        if ($raw === null || $raw === '') {
            return null;
        }

        $status = is_string($raw) ? TripStatus::tryFrom($raw) : null;

        if ($status === null) {
            throw new ApiException(
                ApiErrorCode::ValidationFailed,
                'Unknown status.',
                ['fields' => ['status' => [
                    'Choose one of: '.implode(', ', TripStatus::values()).'.',
                ]]],
            );
        }

        return $status;
    }

    private function customer(Request $request): User
    {
        /** @var User $customer */
        $customer = $request->user();

        return $customer;
    }
}
