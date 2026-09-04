<?php

declare(strict_types=1);

namespace App\Services\Trip;

use App\Enums\ApiErrorCode;
use App\Enums\LocationSourceType;
use App\Enums\RouteStatus;
use App\Enums\TripStatus;
use App\Exceptions\ApiException;
use App\Models\Trip;
use App\Models\User;
use App\Services\Address\CustomerAddressService;
use App\Support\Trip\LocationSelection;
use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

/**
 * Every read and write of a trip goes through here.
 *
 * Four responsibilities:
 *
 *  - **Ownership.** The customer is the authenticated actor. `ownedByOrFail()` is
 *    the only way to reach one trip, and it answers the same 404 for "does not
 *    exist" and "belongs to somebody else".
 *  - **Endpoint resolution.** A request may name a saved address instead of
 *    supplying a place. Resolving it goes through
 *    {@see CustomerAddressService::ownedByOrFail()}, so creating a trip *from
 *    somebody else's saved address* fails exactly the way reading it fails. That
 *    is the subtle IDOR in this module, and it is closed by reusing Module 04's
 *    single path rather than querying addresses here.
 *  - **Usability.** Both endpoints must have real coordinates in range, and they
 *    must not be the same place. Both are checked here as well as in the form
 *    request, because the service is the boundary a future importer or console
 *    command would also come through.
 *  - **Honesty.** A created trip is `ROUTE_PENDING` / `NOT_CALCULATED`, and there
 *    is nowhere to put a distance or an ETA.
 */
final class TripService
{
    public function __construct(
        private readonly CustomerAddressService $addresses,
    ) {}

    /** @return Collection<int, Trip> */
    public function listFor(User $customer, ?TripStatus $status = null, int $limit = 25): Collection
    {
        $query = Trip::query()->ownedBy($customer)->newestFirst();

        if ($status !== null) {
            $query->where('status', $status);
        }

        return $query->limit($limit)->get();
    }

    /**
     * The trip the home screen leads with: the most recent one still live.
     *
     * Null is an ordinary answer, and the home screen renders nothing for trips
     * when it gets one.
     */
    public function currentFor(User $customer): ?Trip
    {
        return Trip::query()->ownedBy($customer)->active()->newestFirst()->first();
    }

    /**
     * Finds one trip belonging to this customer.
     *
     * Not-yours and does-not-exist give the identical answer: distinguishing them
     * turns the endpoint into an oracle for which identifiers are real.
     *
     * @throws ApiException
     */
    public function ownedByOrFail(User $customer, string $uuid): Trip
    {
        $trip = Trip::query()->ownedBy($customer)->where('uuid', $uuid)->first();

        if ($trip === null) {
            Log::info('trip.access_denied', [
                'actor_id' => $customer->uuid,
                'trip_uuid' => $uuid,
            ]);

            throw new ApiException(ApiErrorCode::TripNotFound, 'That journey does not exist.');
        }

        return $trip;
    }

    /**
     * Creates a trip.
     *
     * @param  array<string, mixed>  $attributes  Already validated and allow-listed.
     *
     * @throws ApiException
     */
    public function create(User $customer, array $attributes, CarbonImmutable $now): Trip
    {
        $origin = $this->resolveEndpoint($customer, (array) $attributes['origin'], 'origin');
        $destination = $this->resolveEndpoint($customer, (array) $attributes['destination'], 'destination');

        $this->assertUsableCoordinates($origin, 'origin');
        $this->assertUsableCoordinates($destination, 'destination');
        $this->assertDistinctPlaces($origin, $destination);

        return DB::transaction(function () use ($customer, $origin, $destination): Trip {
            // Locked for the transaction: the count decides whether the limit is
            // reached, and two concurrent creates would both read the old count
            // and both pass.
            $pending = Trip::query()
                ->ownedBy($customer)
                ->active()
                ->lockForUpdate()
                ->count();

            $limit = (int) config('foodonthego.trips.max_pending_per_customer');
            if ($pending >= $limit) {
                throw new ApiException(
                    ApiErrorCode::TripLimitReached,
                    "You have {$limit} journeys waiting to be planned. Discard one to create another.",
                );
            }

            $trip = new Trip;
            $trip->customer_id = $customer->getKey();
            $trip->status = TripStatus::RoutePending;
            // Module 05 does not calculate anything, and this is the column that
            // says so out loud rather than leaving a distance at zero.
            $trip->route_status = RouteStatus::NotCalculated;
            $trip->forceFill($origin->toColumns('origin'));
            $trip->forceFill($destination->toColumns('destination'));
            $trip->save();

            // Re-read so the response is what the database holds: decimal columns
            // round-trip to a fixed scale, and a create that disagreed with a
            // later fetch of the same trip is a defect this project has already
            // had once.
            $trip->refresh();

            // The event, the record and the actor. Never the places: where
            // somebody is travelling from and to is the most sensitive thing this
            // module holds, and an operational log is the wrong place for it.
            Log::info('trip.created', [
                'actor_id' => $customer->uuid,
                'trip_uuid' => $trip->uuid,
                'origin_source' => $origin->sourceType->value,
                'destination_source' => $destination->sourceType->value,
                'route_status' => $trip->route_status->value,
            ]);

            return $trip;
        });
    }

    /**
     * Discards a trip the customer no longer wants.
     *
     * Cancelled rather than deleted: a trip is a record of an intention, and
     * Module 08's orders will point at one. Discarding an already-discarded trip
     * is refused rather than silently accepted — the customer is looking at a
     * stale screen, and answering "done" would hide that from them.
     *
     * @throws ApiException
     */
    public function discard(User $customer, Trip $trip, CarbonImmutable $now): Trip
    {
        if (! $trip->isDiscardable()) {
            throw new ApiException(
                ApiErrorCode::TripNotEditable,
                'That journey has already been discarded.',
            );
        }

        $trip->status = TripStatus::Cancelled;
        $trip->cancelled_at = $now;
        $trip->save();
        $trip->refresh();

        Log::info('trip.discarded', [
            'actor_id' => $customer->uuid,
            'trip_uuid' => $trip->uuid,
        ]);

        return $trip;
    }

    /**
     * Turns one end of a request into a snapshot.
     *
     * The saved-address branch is the security-relevant one. It does **not**
     * query `customer_addresses` — it asks Module 04's service, which is scoped
     * to the authenticated customer and throws the same 404 it throws for a
     * direct read. So a trip cannot be created from an address the caller cannot
     * see, and trying tells them nothing about whether it exists.
     *
     * @param  array<string, mixed>  $input
     *
     * @throws ApiException
     */
    private function resolveEndpoint(User $customer, array $input, string $field): LocationSelection
    {
        $sourceType = LocationSourceType::from((string) $input['source_type']);

        if ($sourceType !== LocationSourceType::SavedAddress) {
            return LocationSelection::fromInput($input, $sourceType);
        }

        $addressUuid = $input['saved_address_id'] ?? null;

        if (! is_string($addressUuid) || $addressUuid === '') {
            throw new ApiException(
                ApiErrorCode::ValidationFailed,
                'A saved place needs to say which saved address it is.',
                ['fields' => [$field.'.saved_address_id' => ['Choose a saved address.']]],
            );
        }

        $address = $this->addresses->ownedByOrFail($customer, $addressUuid);

        // Module 04 allows an address with no coordinates. A trip does not, and
        // the app is expected to send the customer back to resolve it rather than
        // have something plausible filled in on their behalf.
        if ($address->latitude === null || $address->longitude === null) {
            Log::info('trip.saved_address_not_located', [
                'actor_id' => $customer->uuid,
                'address_uuid' => $address->uuid,
            ]);

            throw new ApiException(
                ApiErrorCode::SavedAddressNotLocated,
                'That saved address does not have a precise map location yet.',
                ['fields' => [$field => ['Find this address on the map before using it for a journey.']]],
            );
        }

        return LocationSelection::fromSavedAddress($address);
    }

    /**
     * Coordinates must be real numbers in range.
     *
     * Checked again here after the form request, because a value that is merely
     * *numeric* is not the point: latitude 999 is numeric, and a trip written
     * with it would be routed off the planet by Module 06.
     *
     * @throws ApiException
     */
    private function assertUsableCoordinates(LocationSelection $selection, string $field): void
    {
        $latitude = $selection->latitudeAsFloat();
        $longitude = $selection->longitudeAsFloat();

        $inRange = $latitude >= -90 && $latitude <= 90
            && $longitude >= -180 && $longitude <= 180;

        // (0, 0) is a real point in the Gulf of Guinea and the classic value of an
        // uninitialised coordinate. Nothing this product plans a journey through
        // is there, so refusing it costs nothing and catches a whole class of
        // client bug.
        $isNullIsland = abs($latitude) < 0.0001 && abs($longitude) < 0.0001;

        if ($inRange && ! $isNullIsland) {
            return;
        }

        throw new ApiException(
            ApiErrorCode::InvalidCoordinates,
            'That place does not have a usable location.',
            ['fields' => [$field => ['We could not use that location. Choose the place again.']]],
        );
    }

    /** @throws ApiException */
    private function assertDistinctPlaces(LocationSelection $origin, LocationSelection $destination): void
    {
        $threshold = (float) config('foodonthego.trips.same_location_threshold_metres');

        if (! $origin->isSamePlaceAs($destination, $threshold)) {
            return;
        }

        throw new ApiException(
            ApiErrorCode::SameLocation,
            'Your starting point and destination are the same. Choose a different destination.',
            ['fields' => ['destination' => [
                'Your starting point and destination are the same. Choose a different destination.',
            ]]],
        );
    }
}
