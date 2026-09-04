<?php

declare(strict_types=1);

namespace Tests\Unit;

use App\Enums\ApiErrorCode;
use App\Enums\LocationSourceType;
use App\Enums\RouteStatus;
use App\Enums\TripStatus;
use App\Exceptions\ApiException;
use App\Models\CustomerAddress;
use App\Models\Trip;
use App\Models\User;
use App\Services\Address\CustomerAddressService;
use App\Services\Trip\TripService;
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\Support\CustomerFactory;
use Tests\TestCase;

/**
 * Trip creation, the rules that decide whether a trip is usable, and the
 * ownership boundary.
 *
 * Every coordinate in this file is a real position of a real place, because the
 * same-location rule works in metres: random pairs would make it untestable and
 * would occasionally collide by accident.
 */
final class TripServiceTest extends TestCase
{
    use RefreshDatabase;

    private TripService $service;

    private CustomerAddressService $addresses;

    private User $rahul;

    private User $ananya;

    private CarbonImmutable $now;

    /** Hauz Khas Village, New Delhi. */
    private const DELHI = ['latitude' => 28.5494, 'longitude' => 77.2001];

    /** Jaipur International Airport. */
    private const JAIPUR = ['latitude' => 26.8242, 'longitude' => 75.8122];

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
    private function place(array $overrides = []): array
    {
        return array_merge([
            'source_type' => LocationSourceType::PlaceSearch->value,
            'display_name' => 'Hauz Khas Village',
            'formatted_address' => 'Hauz Khas, New Delhi, Delhi 110016',
            'place_id' => 'dev:hauz-khas',
            'city' => 'New Delhi',
            'region' => 'Delhi',
            'country_code' => 'IN',
        ], self::DELHI, $overrides);
    }

    /** @param array<string, mixed> $overrides */
    private function jaipur(array $overrides = []): array
    {
        return $this->place(array_merge([
            'display_name' => 'Jaipur International Airport',
            'formatted_address' => 'Airport Road, Sanganer, Jaipur, Rajasthan',
            'place_id' => 'dev:jaipur-airport',
            'city' => 'Jaipur',
            'region' => 'Rajasthan',
        ], self::JAIPUR, $overrides));
    }

    /** @param array<string, mixed> $overrides */
    private function attributes(array $overrides = []): array
    {
        return array_merge([
            'origin' => $this->place(),
            'destination' => $this->jaipur(),
        ], $overrides);
    }

    private function savedAddress(User $owner, bool $located = true): CustomerAddress
    {
        $address = $this->addresses->create($owner, [
            'type' => 'HOME',
            'label' => 'Home',
            'address_line_1' => '12 Green Park Road',
            'city' => 'New Delhi',
            'state' => 'Delhi',
            'postal_code' => '110016',
            'country_code' => 'IN',
        ] + ($located ? ['latitude' => '28.5590', 'longitude' => '77.2070'] : []),
            makeDefault: false,
        );

        return $address;
    }

    // --- creation ---------------------------------------------------------

    public function test_a_trip_is_created_for_the_authenticated_customer(): void
    {
        $trip = $this->service->create($this->rahul, $this->attributes(), $this->now);

        $this->assertSame($this->rahul->getKey(), $trip->customer_id);
        $this->assertSame('New Delhi', $trip->origin_city);
        $this->assertSame('Jaipur', $trip->destination_city);
    }

    public function test_a_new_trip_waits_for_a_route_and_claims_nothing_about_one(): void
    {
        $trip = $this->service->create($this->rahul, $this->attributes(), $this->now);

        // The two statuses this module is allowed to produce, and no others.
        $this->assertSame(TripStatus::RoutePending, $trip->status);
        $this->assertSame(RouteStatus::NotCalculated, $trip->route_status);

        // There is nowhere to put a distance, a duration or an ETA, which is the
        // strongest possible guarantee that none was fabricated.
        foreach (['distance', 'duration', 'polyline', 'eta'] as $absent) {
            $this->assertArrayNotHasKey($absent, $trip->getAttributes());
        }
    }

    public function test_coordinates_are_stored_at_the_precision_of_the_column(): void
    {
        $trip = $this->service->create($this->rahul, $this->attributes(), $this->now);

        $this->assertSame('28.5494000', $trip->origin_latitude);
        $this->assertSame('75.8122000', $trip->destination_longitude);
    }

    public function test_the_source_of_each_end_is_recorded(): void
    {
        $address = $this->savedAddress($this->rahul);

        $trip = $this->service->create($this->rahul, $this->attributes([
            'origin' => [
                'source_type' => LocationSourceType::SavedAddress->value,
                'saved_address_id' => $address->uuid,
            ],
        ]), $this->now);

        $this->assertSame(LocationSourceType::SavedAddress, $trip->origin_source_type);
        $this->assertSame(LocationSourceType::PlaceSearch, $trip->destination_source_type);
    }

    public function test_a_current_location_endpoint_is_accepted(): void
    {
        $trip = $this->service->create($this->rahul, $this->attributes([
            'origin' => $this->place([
                'source_type' => LocationSourceType::CurrentLocation->value,
                'display_name' => 'Current location',
                'place_id' => null,
            ]),
        ]), $this->now);

        $this->assertSame(LocationSourceType::CurrentLocation, $trip->origin_source_type);
        $this->assertNull($trip->origin_place_id);
    }

    // --- saved addresses --------------------------------------------------

    public function test_a_saved_address_is_snapshotted_with_its_coordinates(): void
    {
        $address = $this->savedAddress($this->rahul);

        $trip = $this->service->create($this->rahul, $this->attributes([
            'origin' => [
                'source_type' => LocationSourceType::SavedAddress->value,
                'saved_address_id' => $address->uuid,
            ],
        ]), $this->now);

        $this->assertSame($address->getKey(), $trip->origin_saved_address_id);
        $this->assertSame($address->formatted_address, $trip->origin_formatted_address);
        $this->assertSame('28.5590000', $trip->origin_latitude);
    }

    public function test_editing_the_saved_address_later_does_not_rewrite_the_trip(): void
    {
        $address = $this->savedAddress($this->rahul);
        $trip = $this->service->create($this->rahul, $this->attributes([
            'origin' => [
                'source_type' => LocationSourceType::SavedAddress->value,
                'saved_address_id' => $address->uuid,
            ],
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

        // The trip still says where the customer was setting off from when they
        // created it. A foreign key alone would have moved it to Mumbai.
        $this->assertSame('New Delhi', $trip->origin_city);
    }

    public function test_a_saved_address_with_no_map_location_is_refused_rather_than_guessed(): void
    {
        $address = $this->savedAddress($this->rahul, located: false);

        $this->expectException(ApiException::class);

        try {
            $this->service->create($this->rahul, $this->attributes([
                'origin' => [
                    'source_type' => LocationSourceType::SavedAddress->value,
                    'saved_address_id' => $address->uuid,
                ],
            ]), $this->now);
        } catch (ApiException $e) {
            // Not "address not found" — it is the customer's own address, and it
            // exists. What is missing is a position, and the app's job is to go
            // and get one rather than have something plausible filled in.
            $this->assertSame(ApiErrorCode::SavedAddressNotLocated, $e->errorCode);
            throw $e;
        }
    }

    public function test_a_trip_cannot_be_created_from_another_customers_saved_address(): void
    {
        $hers = $this->savedAddress($this->ananya);

        $this->expectException(ApiException::class);

        try {
            $this->service->create($this->rahul, $this->attributes([
                'origin' => [
                    'source_type' => LocationSourceType::SavedAddress->value,
                    'saved_address_id' => $hers->uuid,
                ],
            ]), $this->now);
        } catch (ApiException $e) {
            // The same answer a direct read of that address gives. Anything else
            // would confirm the address exists.
            $this->assertSame(ApiErrorCode::AddressNotFound, $e->errorCode);
            throw $e;
        }
    }

    // --- coordinates ------------------------------------------------------

    public function test_a_latitude_out_of_range_is_refused(): void
    {
        $this->expectException(ApiException::class);

        try {
            $this->service->create($this->rahul, $this->attributes([
                'origin' => $this->place(['latitude' => 999, 'longitude' => -999]),
            ]), $this->now);
        } catch (ApiException $e) {
            $this->assertSame(ApiErrorCode::InvalidCoordinates, $e->errorCode);
            throw $e;
        }
    }

    public function test_null_island_is_refused(): void
    {
        // (0, 0) is a real point in the Gulf of Guinea and the classic value of
        // an uninitialised coordinate. Nothing this product plans through is
        // there, so refusing it costs nothing and catches a class of client bug.
        $this->expectException(ApiException::class);

        $this->service->create($this->rahul, $this->attributes([
            'origin' => $this->place(['latitude' => 0, 'longitude' => 0]),
        ]), $this->now);
    }

    public function test_a_boundary_coordinate_is_still_accepted(): void
    {
        // -90/180 is a real place. A range check written with `<` instead of
        // `<=` would refuse the poles and the date line.
        $trip = $this->service->create($this->rahul, $this->attributes([
            'origin' => $this->place(['latitude' => -90, 'longitude' => 180, 'place_id' => 'dev:pole']),
        ]), $this->now);

        $this->assertSame('-90.0000000', $trip->origin_latitude);
    }

    // --- same location ----------------------------------------------------

    public function test_the_same_place_id_at_both_ends_is_refused(): void
    {
        $this->expectException(ApiException::class);

        try {
            $this->service->create($this->rahul, $this->attributes([
                'destination' => $this->place(),
            ]), $this->now);
        } catch (ApiException $e) {
            $this->assertSame(ApiErrorCode::SameLocation, $e->errorCode);
            throw $e;
        }
    }

    public function test_the_same_saved_address_at_both_ends_is_refused(): void
    {
        $address = $this->savedAddress($this->rahul);
        $endpoint = [
            'source_type' => LocationSourceType::SavedAddress->value,
            'saved_address_id' => $address->uuid,
        ];

        $this->expectException(ApiException::class);

        $this->service->create(
            $this->rahul,
            ['origin' => $endpoint, 'destination' => $endpoint],
            $this->now,
        );
    }

    public function test_two_different_sources_for_one_building_are_refused(): void
    {
        // The case the distance rule exists for: the same airport reached once
        // from a search and once from a device fix, with different ids and
        // different display text, forty metres apart.
        $this->expectException(ApiException::class);

        $this->service->create($this->rahul, [
            'origin' => $this->jaipur(),
            'destination' => $this->place([
                'source_type' => LocationSourceType::CurrentLocation->value,
                'display_name' => 'Current location',
                'place_id' => null,
                'latitude' => 26.8245,
                'longitude' => 75.8124,
            ]),
        ], $this->now);
    }

    public function test_a_genuinely_short_journey_is_still_allowed(): void
    {
        // Connaught Place to Hauz Khas is about 9 km. A generous same-location
        // radius would refuse real short journeys, which is why the threshold is
        // a building rather than a neighbourhood.
        $trip = $this->service->create($this->rahul, [
            'origin' => $this->place(),
            'destination' => $this->place([
                'display_name' => 'Connaught Place',
                'place_id' => 'dev:connaught-place',
                'latitude' => 28.6315,
                'longitude' => 77.2167,
            ]),
        ], $this->now);

        $this->assertSame('Connaught Place', $trip->destination_name);
    }

    public function test_two_addresses_in_one_street_are_not_the_same_place(): void
    {
        // ~200 m apart: two different buildings, and a legitimate journey.
        $trip = $this->service->create($this->rahul, [
            'origin' => $this->place(['place_id' => 'dev:a', 'latitude' => 28.5494, 'longitude' => 77.2001]),
            'destination' => $this->place(['place_id' => 'dev:b', 'latitude' => 28.5512, 'longitude' => 77.2001]),
        ], $this->now);

        $this->assertNotNull($trip->uuid);
    }

    // --- limits and ownership ---------------------------------------------

    public function test_the_pending_limit_counts_only_live_trips(): void
    {
        $limit = (int) config('foodonthego.trips.max_pending_per_customer');

        // Discarded trips are history and never consume the allowance.
        Trip::factory()->count(5)->ownedBy($this->rahul)->discarded()->create();
        Trip::factory()->count($limit)->ownedBy($this->rahul)->create();

        $this->expectException(ApiException::class);

        try {
            $this->service->create($this->rahul, $this->attributes(), $this->now);
        } catch (ApiException $e) {
            $this->assertSame(ApiErrorCode::TripLimitReached, $e->errorCode);
            throw $e;
        }
    }

    public function test_a_trip_belonging_to_somebody_else_is_not_found(): void
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

    public function test_a_missing_trip_and_a_foreign_trip_answer_identically(): void
    {
        $hers = Trip::factory()->ownedBy($this->ananya)->create();

        $missing = null;
        $notMine = null;

        try {
            $this->service->ownedByOrFail($this->rahul, (string) Str::uuid());
        } catch (ApiException $e) {
            $missing = [$e->errorCode, $e->getMessage()];
        }

        try {
            $this->service->ownedByOrFail($this->rahul, $hers->uuid);
        } catch (ApiException $e) {
            $notMine = [$e->errorCode, $e->getMessage()];
        }

        $this->assertSame($missing, $notMine);
    }

    public function test_a_list_never_reaches_another_customers_trips(): void
    {
        Trip::factory()->count(3)->ownedBy($this->ananya)->create();

        $this->assertCount(0, $this->service->listFor($this->rahul));
    }

    public function test_the_current_trip_is_the_newest_live_one(): void
    {
        Trip::factory()->ownedBy($this->rahul)->discarded()->create();
        $newest = Trip::factory()->ownedBy($this->rahul)->delhiToAgra()->create();

        $this->assertSame($newest->uuid, $this->service->currentFor($this->rahul)?->uuid);
    }

    public function test_there_is_no_current_trip_when_every_one_was_discarded(): void
    {
        Trip::factory()->count(2)->ownedBy($this->rahul)->discarded()->create();

        $this->assertNull($this->service->currentFor($this->rahul));
    }

    // --- discarding -------------------------------------------------------

    public function test_discarding_records_the_decision(): void
    {
        $trip = $this->service->create($this->rahul, $this->attributes(), $this->now);

        $discarded = $this->service->discard($this->rahul, $trip, $this->now);

        $this->assertSame(TripStatus::Cancelled, $discarded->status);
        $this->assertNotNull($discarded->cancelled_at);
    }

    public function test_discarding_twice_is_refused_rather_than_silently_accepted(): void
    {
        $trip = $this->service->create($this->rahul, $this->attributes(), $this->now);
        $this->service->discard($this->rahul, $trip, $this->now);

        $this->expectException(ApiException::class);

        // Answering "done" would hide from the customer that they are looking at
        // a screen that is out of date.
        $this->service->discard($this->rahul, $trip->fresh(), $this->now);
    }

    public function test_a_discarded_trip_leaves_the_live_list(): void
    {
        $trip = $this->service->create($this->rahul, $this->attributes(), $this->now);
        $this->service->discard($this->rahul, $trip, $this->now);

        $this->assertCount(0, $this->service->listFor($this->rahul, TripStatus::RoutePending));
        $this->assertCount(1, $this->service->listFor($this->rahul, TripStatus::Cancelled));
    }
}
