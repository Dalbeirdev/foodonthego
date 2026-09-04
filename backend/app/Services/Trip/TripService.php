<?php

declare(strict_types=1);

namespace App\Services\Trip;

use App\Enums\ApiErrorCode;
use App\Enums\TripStatus;
use App\Exceptions\ApiException;
use App\Models\Trip;
use App\Models\User;
use App\Services\Address\CustomerAddressService;
use App\Support\Trip\JourneyEndpoint;
use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

/**
 * Every read and write of a journey goes through here.
 *
 * Four responsibilities:
 *
 *  - **Ownership.** The customer is the authenticated actor. `ownedByOrFail()` is
 *    the only way to reach one journey, and it answers the same 404 for "does not
 *    exist" and "belongs to somebody else".
 *  - **Endpoint resolution.** A request may name a saved address instead of typing
 *    a place. Resolving it goes through {@see CustomerAddressService::ownedByOrFail()},
 *    so planning a journey *from somebody else's saved address* fails exactly the
 *    way reading it directly fails. That is the subtle IDOR in this module, and it
 *    is closed by reusing Module 04's one path rather than querying addresses here.
 *  - **The lifecycle.** Planned journeys can be changed; departed and cancelled
 *    ones cannot. Cancelling is idempotent in effect but not silent.
 *  - **Time.** Every comparison against "now" takes an injected clock, so the
 *    boundary cases — a departure one second away — are testable rather than
 *    hoped about.
 */
final class TripService
{
    public function __construct(
        private readonly CustomerAddressService $addresses,
    ) {}

    /**
     * @return Collection<int, Trip>
     */
    public function listFor(User $customer, TripScope $scope, CarbonImmutable $now): Collection
    {
        $query = Trip::query()->ownedBy($customer);

        return match ($scope) {
            TripScope::Upcoming => $query->upcoming($now)->get(),
            TripScope::Past => $query->past($now)->get(),
            TripScope::Cancelled => $query->cancelled()->get(),
            TripScope::All => $query->orderByDesc('departure_at')->get(),
        };
    }

    /**
     * The journey the home screen leads with: the soonest one still ahead.
     *
     * Null is a normal answer and the home screen renders nothing for journeys
     * when it gets one — an empty "Current journey" card is worse than no card.
     */
    public function nextFor(User $customer, CarbonImmutable $now): ?Trip
    {
        return Trip::query()->ownedBy($customer)->upcoming($now)->first();
    }

    /**
     * Finds one journey belonging to this customer.
     *
     * Not-yours and does-not-exist give the identical answer, for the reason
     * Module 04 gives at length: distinguishing them turns the endpoint into an
     * oracle for which identifiers are real.
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

            throw new ApiException(
                ApiErrorCode::TripNotFound,
                'That journey does not exist.',
            );
        }

        return $trip;
    }

    /**
     * Plans a journey.
     *
     * @param  array<string, mixed>  $attributes  Already validated and allow-listed.
     *
     * @throws ApiException
     */
    public function create(User $customer, array $attributes, CarbonImmutable $now): Trip
    {
        $origin = $this->resolveEndpoint($customer, $attributes['origin']);
        $destination = $this->resolveEndpoint($customer, $attributes['destination']);

        $this->assertDistinctPlaces($origin, $destination);

        $departure = CarbonImmutable::parse($attributes['departure_at'])->utc();

        // Also checked by the form request, and deliberately checked again here.
        // The request applies the configured grace against the wall clock; this
        // is the service's own boundary, and a caller that reaches `create()`
        // some other way — a console command, a future import — must not be able
        // to write a journey into the past.
        $this->assertDepartureIsAhead($departure, $now);

        $arrival = $this->arrivalFrom($attributes, $departure);

        return DB::transaction(function () use (
            $customer, $origin, $destination, $departure, $arrival, $attributes, $now
        ): Trip {
            // Locked for the transaction: the count decides whether the limit is
            // reached, and two concurrent creates would both read the old count
            // and both pass.
            $plannedCount = Trip::query()
                ->ownedBy($customer)
                ->where('status', TripStatus::Planned)
                ->where('departure_at', '>=', $now)
                ->lockForUpdate()
                ->count();

            $limit = (int) config('foodonthego.trips.max_upcoming_per_customer');
            if ($plannedCount >= $limit) {
                throw new ApiException(
                    ApiErrorCode::TripLimitReached,
                    "You can have up to {$limit} upcoming journeys. Cancel one to plan another.",
                );
            }

            $trip = new Trip;
            $trip->customer_id = $customer->getKey();
            $trip->status = TripStatus::Planned;
            $trip->forceFill($origin->toColumns('origin'));
            $trip->forceFill($destination->toColumns('destination'));
            $trip->departure_at = $departure;
            $trip->expected_arrival_at = $arrival;
            $trip->traveller_count = (int) ($attributes['traveller_count'] ?? 1);
            $trip->note = $this->nullIfBlank($attributes['note'] ?? null);
            $trip->save();

            // Re-read so the response is what the database holds. Decimal columns
            // round-trip to a fixed scale, and a create that disagreed with a
            // later fetch of the same journey is the Module 04 defect again.
            $trip->refresh();

            // Names the journey and the actor. Never the addresses: where somebody
            // is travelling from and to is the most sensitive thing this module
            // holds, and an operational log is the wrong place for it.
            Log::info('trip.created', [
                'actor_id' => $customer->uuid,
                'trip_uuid' => $trip->uuid,
                'from_saved_addresses' => [
                    'origin' => $origin->addressId !== null,
                    'destination' => $destination->addressId !== null,
                ],
                'has_coordinates' => $origin->latitude !== null && $destination->latitude !== null,
            ]);

            return $trip;
        });
    }

    /**
     * Changes a planned journey.
     *
     * Partial: an absent key means "leave it". An endpoint is replaced whole or
     * not at all — a half-updated endpoint (a new city against an old formatted
     * line) would be a place that does not exist.
     *
     * @param  array<string, mixed>  $attributes  Already validated and allow-listed.
     *
     * @throws ApiException
     */
    public function update(User $customer, Trip $trip, array $attributes, CarbonImmutable $now): Trip
    {
        $this->assertEditable($trip, $now);

        $origin = array_key_exists('origin', $attributes)
            ? $this->resolveEndpoint($customer, $attributes['origin'])
            : null;

        $destination = array_key_exists('destination', $attributes)
            ? $this->resolveEndpoint($customer, $attributes['destination'])
            : null;

        // Compared against what the journey will be, not against what was sent:
        // moving only the origin onto the existing destination is the same
        // mistake as sending both the same.
        $this->assertDistinctPlaces(
            $origin ?? $this->endpointOf($trip, 'origin'),
            $destination ?? $this->endpointOf($trip, 'destination'),
        );

        if ($origin !== null) {
            $trip->forceFill($origin->toColumns('origin'));
        }

        if ($destination !== null) {
            $trip->forceFill($destination->toColumns('destination'));
        }

        if (array_key_exists('departure_at', $attributes)) {
            $trip->departure_at = CarbonImmutable::parse($attributes['departure_at'])->utc();
        }

        if (array_key_exists('expected_arrival_at', $attributes)) {
            $trip->expected_arrival_at = $attributes['expected_arrival_at'] === null
                ? null
                : CarbonImmutable::parse($attributes['expected_arrival_at'])->utc();
        }

        if (array_key_exists('traveller_count', $attributes)) {
            $trip->traveller_count = (int) $attributes['traveller_count'];
        }

        if (array_key_exists('note', $attributes)) {
            $trip->note = $this->nullIfBlank($attributes['note']);
        }

        // Re-checked after the changes have been applied: a customer may move a
        // departure, but not to a moment that has already passed, and not so that
        // it lands after the arrival they stated.
        $this->assertDepartureIsAhead($trip->departure_at, $now);
        $this->assertArrivalAfterDeparture($trip->expected_arrival_at, $trip->departure_at);

        $changed = array_keys($trip->getDirty());
        $trip->save();
        $trip->refresh();

        Log::info('trip.updated', [
            'actor_id' => $customer->uuid,
            'trip_uuid' => $trip->uuid,
            // Field names, never values. "The origin changed" is operationally
            // useful; "the origin changed to 14 Rose Lane" is a location log.
            'fields' => $this->fieldNames($changed),
        ]);

        return $trip;
    }

    /**
     * Cancels a planned journey.
     *
     * Cancelling an already-cancelled journey is refused rather than silently
     * accepted: the customer is looking at a stale screen, and answering "done"
     * would hide that from them.
     *
     * @throws ApiException
     */
    public function cancel(User $customer, Trip $trip, ?string $reason, CarbonImmutable $now): Trip
    {
        if ($trip->isCancelled()) {
            throw new ApiException(
                ApiErrorCode::TripNotEditable,
                'That journey is already cancelled.',
            );
        }

        // A departed journey can no longer be cancelled — there is nothing left
        // to call off. It stays in the past list as a record of the plan.
        if ($trip->hasDeparted($now)) {
            throw new ApiException(
                ApiErrorCode::TripNotEditable,
                'That journey has already departed and can no longer be cancelled.',
            );
        }

        $trip->status = TripStatus::Cancelled;
        $trip->cancelled_at = $now;
        $trip->cancellation_reason = $this->nullIfBlank($reason);
        $trip->save();
        $trip->refresh();

        Log::info('trip.cancelled', [
            'actor_id' => $customer->uuid,
            'trip_uuid' => $trip->uuid,
            'gave_reason' => $trip->cancellation_reason !== null,
        ]);

        return $trip;
    }

    /**
     * Turns one end of a request into a snapshot.
     *
     * The saved-address branch is the security-relevant one. It does **not**
     * query `customer_addresses` — it asks Module 04's service, which is scoped
     * to the authenticated customer and throws the same 404 it throws for a
     * direct read. So a journey cannot be planned from an address the caller
     * cannot see, and trying tells them nothing about whether it exists.
     *
     * @param  array<string, mixed>  $input
     *
     * @throws ApiException
     */
    private function resolveEndpoint(User $customer, array $input): JourneyEndpoint
    {
        $savedAddressId = $input['address_id'] ?? null;

        if (is_string($savedAddressId) && $savedAddressId !== '') {
            return JourneyEndpoint::fromSavedAddress(
                $this->addresses->ownedByOrFail($customer, $savedAddressId),
            );
        }

        return JourneyEndpoint::fromInput($input);
    }

    private function endpointOf(Trip $trip, string $prefix): JourneyEndpoint
    {
        return new JourneyEndpoint(
            label: (string) $trip->{"{$prefix}_label"},
            formattedAddress: (string) $trip->{"{$prefix}_formatted_address"},
            city: (string) $trip->{"{$prefix}_city"},
            countryCode: (string) $trip->{"{$prefix}_country_code"},
            latitude: $trip->{"{$prefix}_latitude"},
            longitude: $trip->{"{$prefix}_longitude"},
            placeId: $trip->{"{$prefix}_place_id"},
            addressId: $trip->{"{$prefix}_address_id"},
        );
    }

    /** @throws ApiException */
    private function assertDistinctPlaces(JourneyEndpoint $origin, JourneyEndpoint $destination): void
    {
        if (! $origin->isSamePlaceAs($destination)) {
            return;
        }

        throw new ApiException(
            ApiErrorCode::ValidationFailed,
            'Your starting point and destination are the same place.',
            ['fields' => ['destination' => ['Choose a destination different from your starting point.']]],
        );
    }

    /** @throws ApiException */
    private function assertEditable(Trip $trip, CarbonImmutable $now): void
    {
        if ($trip->isEditable($now)) {
            return;
        }

        throw new ApiException(
            ApiErrorCode::TripNotEditable,
            $trip->isCancelled()
                ? 'That journey is cancelled and can no longer be changed.'
                : 'That journey has already departed and can no longer be changed.',
        );
    }

    /**
     * The same grace the form request applies, applied again here.
     *
     * It has to be the same number in both places or the two layers disagree:
     * a request the validator accepts would then be refused by the service, and
     * the customer would see a failure with no field to correct.
     *
     * @throws ApiException
     */
    private function assertDepartureIsAhead(?CarbonImmutable $departure, CarbonImmutable $now): void
    {
        $grace = (int) config('foodonthego.trips.departure_grace_minutes');
        $earliest = $now->subMinutes($grace);

        if ($departure !== null && $departure->greaterThanOrEqualTo($earliest)) {
            return;
        }

        throw new ApiException(
            ApiErrorCode::ValidationFailed,
            'Choose a departure time in the future.',
            ['fields' => ['departure_at' => ['Choose a departure time in the future.']]],
        );
    }

    /** @throws ApiException */
    private function assertArrivalAfterDeparture(?CarbonImmutable $arrival, ?CarbonImmutable $departure): void
    {
        if ($arrival === null || $departure === null || $arrival->greaterThan($departure)) {
            return;
        }

        throw new ApiException(
            ApiErrorCode::ValidationFailed,
            'Arrival has to be after departure.',
            ['fields' => ['expected_arrival_at' => ['Arrival has to be after departure.']]],
        );
    }

    /**
     * @param  array<string, mixed>  $attributes
     *
     * @throws ApiException
     */
    private function arrivalFrom(array $attributes, CarbonImmutable $departure): ?CarbonImmutable
    {
        $raw = $attributes['expected_arrival_at'] ?? null;

        if ($raw === null || $raw === '') {
            return null;
        }

        $arrival = CarbonImmutable::parse($raw)->utc();
        $this->assertArrivalAfterDeparture($arrival, $departure);

        return $arrival;
    }

    /**
     * Collapses the eight columns of an endpoint into one name for the log.
     *
     * @param  list<string>  $columns
     * @return list<string>
     */
    private function fieldNames(array $columns): array
    {
        $names = [];

        foreach ($columns as $column) {
            $names[] = match (true) {
                str_starts_with($column, 'origin_') => 'origin',
                str_starts_with($column, 'destination_') => 'destination',
                default => $column,
            };
        }

        return array_values(array_unique($names));
    }

    private function nullIfBlank(mixed $value): ?string
    {
        if (! is_string($value)) {
            return null;
        }

        $trimmed = trim($value);

        return $trimmed === '' ? null : $trimmed;
    }
}
