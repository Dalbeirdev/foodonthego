<?php

declare(strict_types=1);

namespace Tests\Unit;

use App\Enums\ApiErrorCode;
use App\Enums\TripStatus;
use App\Exceptions\ApiException;
use App\Models\CustomerAddress;
use App\Models\Trip;
use App\Models\User;
use App\Services\Address\CustomerAddressService;
use App\Services\Trip\TripScope;
use App\Services\Trip\TripService;
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\Support\CustomerFactory;
use Tests\TestCase;

/**
 * The journey lifecycle and the ownership boundary.
 *
 * Every test injects its own "now" rather than letting the service read the
 * clock, because half the rules in this module are about time and a rule you can
 * only exercise by waiting is a rule that is never exercised.
 */
final class TripServiceTest extends TestCase
{
    use RefreshDatabase;

    private TripService $service;

    private CustomerAddressService $addresses;

    private User $rahul;

    private User $ananya;

    private CarbonImmutable $now;

    protected function setUp(): void
    {
        parent::setUp();

        $this->service = $this->app->make(TripService::class);
        $this->addresses = $this->app->make(CustomerAddressService::class);
        $this->rahul = CustomerFactory::rahul();
        $this->ananya = CustomerFactory::ananya();
        $this->now = CarbonImmutable::parse('2026-09-04T09:00:00Z');
    }

    /** @param array<string, mixed> $overrides */
    private function attributes(array $overrides = []): array
    {
        return array_merge([
            'origin' => [
                'label' => 'Home',
                'address_line' => 'Hauz Khas',
                'city' => 'New Delhi',
                'state' => 'Delhi',
                'country_code' => 'IN',
            ],
            'destination' => [
                'label' => 'Jaipur',
                'address_line' => 'MI Road',
                'city' => 'Jaipur',
                'state' => 'Rajasthan',
                'country_code' => 'IN',
            ],
            'departure_at' => $this->now->addDay()->toIso8601String(),
        ], $overrides);
    }

    /** @param array<string, mixed> $overrides */
    private function savedAddress(User $owner, array $overrides = []): CustomerAddress
    {
        return $this->addresses->create($owner, array_merge([
            'type' => 'HOME',
            'label' => 'Home',
            'address_line_1' => '12 Green Park Road',
            'city' => 'New Delhi',
            'state' => 'Delhi',
            'postal_code' => '110016',
            'country_code' => 'IN',
        ], $overrides), makeDefault: false);
    }

    public function test_a_journey_is_planned_for_the_authenticated_customer(): void
    {
        $trip = $this->service->create($this->rahul, $this->attributes(), $this->now);

        $this->assertSame($this->rahul->getKey(), $trip->customer_id);
        $this->assertSame(TripStatus::Planned, $trip->status);
        $this->assertSame('New Delhi', $trip->origin_city);
        $this->assertSame('Jaipur', $trip->destination_city);
    }

    public function test_coordinates_are_null_when_nothing_has_geocoded_the_places(): void
    {
        $trip = $this->service->create($this->rahul, $this->attributes(), $this->now);

        // The whole point. A plausible-looking coordinate here would become a
        // fabricated corridor in Module 09 and a fabricated cooking time after it.
        $this->assertNull($trip->origin_latitude);
        $this->assertNull($trip->origin_longitude);
        $this->assertNull($trip->destination_latitude);
        $this->assertNull($trip->destination_longitude);
        $this->assertNull($trip->origin_place_id);
    }

    public function test_an_endpoint_can_be_a_saved_address_and_is_snapshotted(): void
    {
        $address = $this->savedAddress($this->rahul);

        $trip = $this->service->create($this->rahul, $this->attributes([
            'origin' => ['address_id' => $address->uuid],
        ]), $this->now);

        $this->assertSame($address->getKey(), $trip->origin_address_id);
        $this->assertSame($address->formatted_address, $trip->origin_formatted_address);
        $this->assertSame('Home', $trip->origin_label);
    }

    public function test_editing_the_saved_address_later_does_not_rewrite_the_journey(): void
    {
        $address = $this->savedAddress($this->rahul);
        $trip = $this->service->create($this->rahul, $this->attributes([
            'origin' => ['address_id' => $address->uuid],
        ]), $this->now);

        $this->addresses->update($this->rahul, $address, [
            'type' => 'HOME',
            'label' => 'Old Flat',
            'address_line_1' => '99 Somewhere Else',
            'city' => 'Mumbai',
            'state' => 'Maharashtra',
            'postal_code' => '400001',
            'country_code' => 'IN',
        ], null);

        $trip->refresh();

        // The journey still says where the traveller was setting off from when
        // they planned it. A foreign key alone would have silently moved it to
        // Mumbai.
        $this->assertSame('New Delhi', $trip->origin_city);
        $this->assertSame('Home', $trip->origin_label);
    }

    public function test_a_journey_cannot_be_planned_from_another_customers_saved_address(): void
    {
        $ananyasAddress = $this->savedAddress($this->ananya, ['label' => 'Ananya Home']);

        $this->expectException(ApiException::class);

        try {
            $this->service->create($this->rahul, $this->attributes([
                'origin' => ['address_id' => $ananyasAddress->uuid],
            ]), $this->now);
        } catch (ApiException $e) {
            // The same answer a direct read of that address gives. Anything else
            // would confirm the address exists.
            $this->assertSame(ApiErrorCode::AddressNotFound, $e->errorCode);
            throw $e;
        }
    }

    public function test_origin_and_destination_may_not_be_the_same_place(): void
    {
        $this->expectException(ApiException::class);

        $this->service->create($this->rahul, $this->attributes([
            'destination' => [
                'label' => 'home again',
                'address_line' => 'hauz khas',
                'city' => 'NEW DELHI',
                'state' => 'Delhi',
                'country_code' => 'IN',
            ],
        ]), $this->now);
    }

    public function test_a_departure_in_the_past_is_refused(): void
    {
        $this->expectException(ApiException::class);

        $this->service->create($this->rahul, $this->attributes([
            'departure_at' => $this->now->subHour()->toIso8601String(),
        ]), $this->now);
    }

    public function test_an_arrival_before_departure_is_refused(): void
    {
        $this->expectException(ApiException::class);

        $this->service->create($this->rahul, $this->attributes([
            'expected_arrival_at' => $this->now->addHours(2)->toIso8601String(),
            'departure_at' => $this->now->addHours(5)->toIso8601String(),
        ]), $this->now);
    }

    public function test_an_arrival_time_is_kept_when_the_traveller_states_one(): void
    {
        $trip = $this->service->create($this->rahul, $this->attributes([
            'expected_arrival_at' => $this->now->addDay()->addHours(5)->toIso8601String(),
        ]), $this->now);

        $this->assertNotNull($trip->expected_arrival_at);
    }

    public function test_the_upcoming_limit_counts_only_journeys_still_ahead(): void
    {
        $limit = (int) config('foodonthego.trips.max_upcoming_per_customer');

        // History, however much of it, never consumes the allowance.
        Trip::factory()->count(5)->ownedBy($this->rahul)->departed()->create();

        for ($i = 1; $i <= $limit; $i++) {
            $this->service->create($this->rahul, $this->attributes([
                'departure_at' => $this->now->addDays($i)->toIso8601String(),
                'destination' => [
                    'label' => "Stop {$i}",
                    'city' => "City {$i}",
                    'country_code' => 'IN',
                ],
            ]), $this->now);
        }

        $this->expectException(ApiException::class);

        try {
            $this->service->create($this->rahul, $this->attributes([
                'destination' => ['label' => 'One too many', 'city' => 'Agra', 'country_code' => 'IN'],
            ]), $this->now);
        } catch (ApiException $e) {
            $this->assertSame(ApiErrorCode::TripLimitReached, $e->errorCode);
            throw $e;
        }
    }

    public function test_a_journey_belonging_to_somebody_else_is_not_found(): void
    {
        $trip = Trip::factory()->ownedBy($this->ananya)->create();

        $this->expectException(ApiException::class);

        try {
            $this->service->ownedByOrFail($this->rahul, $trip->uuid);
        } catch (ApiException $e) {
            $this->assertSame(ApiErrorCode::TripNotFound, $e->errorCode);
            throw $e;
        }
    }

    public function test_a_journey_that_does_not_exist_gives_the_identical_answer(): void
    {
        $missing = null;
        $notMine = null;

        $trip = Trip::factory()->ownedBy($this->ananya)->create();

        try {
            $this->service->ownedByOrFail($this->rahul, (string) Str::uuid());
        } catch (ApiException $e) {
            $missing = [$e->errorCode, $e->getMessage()];
        }

        try {
            $this->service->ownedByOrFail($this->rahul, $trip->uuid);
        } catch (ApiException $e) {
            $notMine = [$e->errorCode, $e->getMessage()];
        }

        // Byte-identical, so the endpoint cannot be walked to learn which ids
        // are real journeys belonging to real customers.
        $this->assertSame($missing, $notMine);
    }

    public function test_a_planned_journey_can_be_changed(): void
    {
        $trip = $this->service->create($this->rahul, $this->attributes(), $this->now);

        $updated = $this->service->update($this->rahul, $trip, [
            'traveller_count' => 3,
            'note' => '  Picking up my sister  ',
        ], $this->now);

        $this->assertSame(3, $updated->traveller_count);
        $this->assertSame('Picking up my sister', $updated->note);
    }

    public function test_a_departed_journey_can_no_longer_be_changed(): void
    {
        $trip = Trip::factory()->ownedBy($this->rahul)->departed()->create();

        $this->expectException(ApiException::class);

        try {
            $this->service->update($this->rahul, $trip, ['traveller_count' => 2], $this->now);
        } catch (ApiException $e) {
            $this->assertSame(ApiErrorCode::TripNotEditable, $e->errorCode);
            throw $e;
        }
    }

    public function test_a_cancelled_journey_can_no_longer_be_changed(): void
    {
        $trip = Trip::factory()->ownedBy($this->rahul)->cancelled()->create();

        $this->expectException(ApiException::class);

        $this->service->update($this->rahul, $trip, ['traveller_count' => 2], $this->now);
    }

    public function test_moving_only_the_origin_onto_the_existing_destination_is_refused(): void
    {
        $trip = $this->service->create($this->rahul, $this->attributes(), $this->now);

        $this->expectException(ApiException::class);

        // The request contains one endpoint, so the check has to compare against
        // what the journey *will be*, not against what was sent.
        $this->service->update($this->rahul, $trip, [
            'origin' => ['label' => 'Jaipur', 'address_line' => 'MI Road', 'city' => 'Jaipur', 'state' => 'Rajasthan', 'country_code' => 'IN'],
        ], $this->now);
    }

    public function test_a_departure_cannot_be_moved_into_the_past(): void
    {
        $trip = $this->service->create($this->rahul, $this->attributes(), $this->now);

        $this->expectException(ApiException::class);

        $this->service->update($this->rahul, $trip, [
            'departure_at' => $this->now->subDay()->toIso8601String(),
        ], $this->now);
    }

    public function test_an_arrival_can_be_cleared_with_an_explicit_null(): void
    {
        $trip = $this->service->create($this->rahul, $this->attributes([
            'expected_arrival_at' => $this->now->addDay()->addHours(5)->toIso8601String(),
        ]), $this->now);

        $updated = $this->service->update($this->rahul, $trip, [
            'expected_arrival_at' => null,
        ], $this->now);

        $this->assertNull($updated->expected_arrival_at);
    }

    public function test_cancelling_records_when_and_why(): void
    {
        $trip = $this->service->create($this->rahul, $this->attributes(), $this->now);

        $cancelled = $this->service->cancel($this->rahul, $trip, 'Meeting moved', $this->now);

        $this->assertSame(TripStatus::Cancelled, $cancelled->status);
        $this->assertNotNull($cancelled->cancelled_at);
        $this->assertSame('Meeting moved', $cancelled->cancellation_reason);
    }

    public function test_cancelling_twice_is_refused_rather_than_silently_accepted(): void
    {
        $trip = $this->service->create($this->rahul, $this->attributes(), $this->now);
        $this->service->cancel($this->rahul, $trip, null, $this->now);

        $this->expectException(ApiException::class);

        // Answering "done" would hide from the customer that they are looking at
        // a screen that is out of date.
        $this->service->cancel($this->rahul, $trip->fresh(), null, $this->now);
    }

    public function test_a_departed_journey_cannot_be_cancelled(): void
    {
        $trip = Trip::factory()->ownedBy($this->rahul)->departed()->create();

        $this->expectException(ApiException::class);

        $this->service->cancel($this->rahul, $trip, null, $this->now);
    }

    public function test_upcoming_excludes_cancelled_and_departed_journeys(): void
    {
        $ahead = Trip::factory()->ownedBy($this->rahul)->departingAt($this->now->addDays(2))->create();
        Trip::factory()->ownedBy($this->rahul)->departed()->create();
        Trip::factory()->ownedBy($this->rahul)->departingAt($this->now->addDays(3))->cancelled()->create();

        $upcoming = $this->service->listFor($this->rahul, TripScope::Upcoming, $this->now);

        $this->assertCount(1, $upcoming);
        $this->assertSame($ahead->uuid, $upcoming->first()?->uuid);
    }

    public function test_upcoming_is_ordered_soonest_first(): void
    {
        Trip::factory()->ownedBy($this->rahul)->departingAt($this->now->addDays(9))->create();
        $soonest = Trip::factory()->ownedBy($this->rahul)->departingAt($this->now->addDay())->create();
        Trip::factory()->ownedBy($this->rahul)->departingAt($this->now->addDays(4))->create();

        $upcoming = $this->service->listFor($this->rahul, TripScope::Upcoming, $this->now);

        $this->assertSame($soonest->uuid, $upcoming->first()?->uuid);
    }

    public function test_the_next_journey_is_the_soonest_one_still_ahead(): void
    {
        Trip::factory()->ownedBy($this->rahul)->departed()->create();
        $soonest = Trip::factory()->ownedBy($this->rahul)->departingAt($this->now->addHours(6))->create();
        Trip::factory()->ownedBy($this->rahul)->departingAt($this->now->addDays(3))->create();

        $this->assertSame($soonest->uuid, $this->service->nextFor($this->rahul, $this->now)?->uuid);
    }

    public function test_the_next_journey_is_null_when_there_is_none(): void
    {
        Trip::factory()->ownedBy($this->rahul)->departed()->create();

        $this->assertNull($this->service->nextFor($this->rahul, $this->now));
    }

    public function test_a_list_never_reaches_another_customers_journeys(): void
    {
        Trip::factory()->count(3)->ownedBy($this->ananya)->create();

        $this->assertCount(0, $this->service->listFor($this->rahul, TripScope::All, $this->now));
    }

    public function test_past_holds_departed_journeys_newest_first(): void
    {
        $older = Trip::factory()->ownedBy($this->rahul)->departingAt($this->now->subDays(9))->create();
        $newer = Trip::factory()->ownedBy($this->rahul)->departingAt($this->now->subDay())->create();

        $past = $this->service->listFor($this->rahul, TripScope::Past, $this->now);

        $this->assertSame([$newer->uuid, $older->uuid], $past->pluck('uuid')->all());
    }

    public function test_a_cancelled_journey_still_ahead_is_in_neither_upcoming_nor_past(): void
    {
        Trip::factory()->ownedBy($this->rahul)->departingAt($this->now->addDays(2))->cancelled()->create();

        $this->assertCount(0, $this->service->listFor($this->rahul, TripScope::Upcoming, $this->now));
        $this->assertCount(0, $this->service->listFor($this->rahul, TripScope::Past, $this->now));
        $this->assertCount(1, $this->service->listFor($this->rahul, TripScope::Cancelled, $this->now));
    }

    public function test_a_journey_departing_this_very_second_still_counts_as_upcoming(): void
    {
        $trip = Trip::factory()->ownedBy($this->rahul)->departingAt($this->now)->create();

        // The boundary, asserted rather than assumed: `>=`, not `>`.
        $this->assertSame($trip->uuid, $this->service->nextFor($this->rahul, $this->now)?->uuid);
        $this->assertTrue($trip->isEditable($this->now));
    }
}
