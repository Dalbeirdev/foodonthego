<?php

declare(strict_types=1);

namespace App\Http\Controllers\Api\V1\Customer;

use App\Enums\ApiErrorCode;
use App\Exceptions\ApiException;
use App\Http\Requests\Customer\CancelTripRequest;
use App\Http\Requests\Customer\StoreTripRequest;
use App\Http\Requests\Customer\UpdateTripRequest;
use App\Http\Responses\ApiResponse;
use App\Models\Trip;
use App\Models\User;
use App\Services\Trip\TripScope;
use App\Services\Trip\TripService;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Journeys, always scoped to the authenticated customer.
 *
 * As with saved addresses, no method uses route-model binding: binding would
 * load the row and leave the ownership check as a separate step somebody could
 * omit. {@see TripService::ownedByOrFail()} is the only path to a journey.
 */
final class TripController
{
    public function __construct(private readonly TripService $trips) {}

    public function index(Request $request): JsonResponse
    {
        $now = CarbonImmutable::now();
        $scope = $this->scopeFrom($request);

        $trips = $this->trips->listFor($this->customer($request), $scope, $now);

        return ApiResponse::ok(
            $trips->map(static fn (Trip $t): array => $t->toApiArray($now))->all(),
        );
    }

    /**
     * The soonest journey still ahead, or null.
     *
     * Its own endpoint rather than "the first item of the upcoming list" because
     * the home screen wants exactly this and nothing else, and a home screen that
     * downloads twenty journeys to render one is a home screen that gets slower
     * the longer somebody uses the app.
     */
    public function next(Request $request): JsonResponse
    {
        $now = CarbonImmutable::now();
        $trip = $this->trips->nextFor($this->customer($request), $now);

        return ApiResponse::ok($trip?->toApiArray($now));
    }

    public function show(Request $request, string $trip): JsonResponse
    {
        $found = $this->trips->ownedByOrFail($this->customer($request), $trip);

        return ApiResponse::ok($found->toApiArray(CarbonImmutable::now()));
    }

    public function store(StoreTripRequest $request): JsonResponse
    {
        $now = CarbonImmutable::now();

        $created = $this->trips->create(
            $this->customer($request),
            $request->tripAttributes(),
            $now,
        );

        return ApiResponse::created($created->toApiArray($now));
    }

    public function update(UpdateTripRequest $request, string $trip): JsonResponse
    {
        $now = CarbonImmutable::now();
        $customer = $this->customer($request);
        $found = $this->trips->ownedByOrFail($customer, $trip);

        $updated = $this->trips->update($customer, $found, $request->tripAttributes(), $now);

        return ApiResponse::ok($updated->toApiArray($now));
    }

    /**
     * Cancels a journey.
     *
     * A POST to a named action rather than `PATCH {"status": "CANCELLED"}`. The
     * difference is not cosmetic: `status` is never an accepted field anywhere in
     * this module, so there is no request shape that can set a journey to an
     * arbitrary state.
     */
    public function cancel(CancelTripRequest $request, string $trip): JsonResponse
    {
        $now = CarbonImmutable::now();
        $customer = $this->customer($request);
        $found = $this->trips->ownedByOrFail($customer, $trip);

        $cancelled = $this->trips->cancel($customer, $found, $request->reason(), $now);

        return ApiResponse::ok($cancelled->toApiArray($now));
    }

    /** @throws ApiException */
    private function scopeFrom(Request $request): TripScope
    {
        $raw = $request->query('scope');

        if ($raw === null || $raw === '') {
            return TripScope::Upcoming;
        }

        $scope = is_string($raw) ? TripScope::tryFrom($raw) : null;

        if ($scope === null) {
            throw new ApiException(
                ApiErrorCode::ValidationFailed,
                'Unknown scope.',
                ['fields' => ['scope' => [
                    'Choose one of: '.implode(', ', TripScope::values()).'.',
                ]]],
            );
        }

        return $scope;
    }

    private function customer(Request $request): User
    {
        /** @var User $customer */
        $customer = $request->user();

        return $customer;
    }
}
