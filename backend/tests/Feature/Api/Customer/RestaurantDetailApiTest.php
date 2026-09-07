<?php

declare(strict_types=1);

namespace Tests\Feature\Api\Customer;

use App\Enums\ApiErrorCode;
use App\Enums\RestaurantStatus;
use App\Models\Restaurant;
use App\Models\RestaurantMedia;
use App\Models\Trip;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Cache;
use Tests\Support\CustomerFactory;
use Tests\Support\RestaurantFixtures;
use Tests\TestCase;

/**
 * One restaurant on a customer's route, as a client sees it.
 *
 * The two things this file exists to prove are both negative: that knowing a
 * restaurant's uuid buys nothing a customer was not already entitled to, and
 * that opening this screen costs no routing call.
 */
final class RestaurantDetailApiTest extends TestCase
{
    use RefreshDatabase;

    private User $rahul;

    private string $token;

    private Trip $trip;

    protected function setUp(): void
    {
        parent::setUp();

        Cache::flush();

        $this->rahul = CustomerFactory::rahul();
        $this->token = CustomerFactory::tokenFor($this->rahul);
        $this->trip = RestaurantFixtures::tripWithSelectedRoute($this->rahul);
    }

    private function asRahul(): self
    {
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', 'Bearer '.$this->token);
    }

    private function url(string $restaurant, ?Trip $trip = null): string
    {
        return '/api/v1/customer/trips/'.($trip ?? $this->trip)->uuid.'/restaurants/'.$restaurant;
    }

    private function onRoute(string $name = 'Highway Spice Kitchen'): Restaurant
    {
        return RestaurantFixtures::nearRoute(0.4, 800, $name);
    }

    // --- the happy path ------------------------------------------------------

    public function test_a_customer_opens_a_restaurant_on_their_route(): void
    {
        $restaurant = $this->onRoute();

        $this->asRahul()->getJson($this->url($restaurant->uuid))
            ->assertOk()
            ->assertJsonPath('data.id', $restaurant->uuid)
            ->assertJsonPath('data.name', 'Highway Spice Kitchen')
            ->assertJsonStructure(['data' => [
                'id', 'name', 'location', 'cuisines', 'facilities', 'availability',
                'description', 'public_phone', 'media',
                'ordering' => ['state', 'can_order', 'can_browse_menu'],
                'hours' => ['timezone', 'today', 'week', 'current_window', 'next_open_at'],
                'route' => [
                    'proximity_meters',
                    'detour_distance_meters',
                    'detour_duration_seconds',
                    'distance_ahead_meters',
                    'time_ahead_seconds',
                    'requires_backtracking',
                ],
                'generated_at',
            ]]);
    }

    public function test_the_route_figures_are_the_ones_the_list_showed(): void
    {
        $restaurant = $this->onRoute();

        $fromList = $this->asRahul()
            ->getJson('/api/v1/customer/trips/'.$this->trip->uuid.'/restaurants')
            ->assertOk()
            ->json('data.restaurants.0.route');

        $fromDetail = $this->asRahul()->getJson($this->url($restaurant->uuid))
            ->assertOk()
            ->json('data.route');

        // A card saying "4 min detour" and a screen saying "9 min" is the kind
        // of disagreement a customer never forgives. The detail reuses the
        // discovery projection rather than computing a second one.
        $this->assertSame($fromList, $fromDetail);
    }

    public function test_the_hours_come_back_as_a_week_with_the_shut_days_in_it(): void
    {
        $restaurant = RestaurantFixtures::nearRoute(0.4, 800, 'Weekday Kitchen', open: false);

        foreach ([1, 2, 3] as $day) {
            $restaurant->openingHours()->create([
                'day_of_week' => $day,
                'opens_at' => '09:00:00',
                'closes_at' => '17:00:00',
            ]);
        }

        $hours = $this->asRahul()->getJson($this->url($restaurant->uuid))
            ->assertOk()
            ->json('data.hours');

        $this->assertCount(7, $hours['week']);
        $this->assertSame([], $hours['week'][0]['windows']);
        $this->assertCount(1, $hours['week'][1]['windows']);
        $this->assertSame('Asia/Kolkata', $hours['timezone']);
    }

    // --- eligibility, which a uuid does not unlock ---------------------------

    public function test_a_suspended_restaurant_cannot_be_opened_by_its_uuid(): void
    {
        $suspended = Restaurant::factory()->discoverable()->suspended()->named('Suspended Dhaba')
            ->at(...RestaurantFixtures::offset(
                0.4, 800, RestaurantFixtures::ORIGIN, RestaurantFixtures::DESTINATION,
            ))
            ->create();

        $response = $this->asRahul()->getJson($this->url($suspended->uuid))
            ->assertNotFound()
            ->assertJsonPath('error.code', ApiErrorCode::RestaurantUnavailable->value);

        // Not one word about the business.
        $this->assertStringNotContainsString('Suspended Dhaba', $response->content());
    }

    public function test_an_unverified_restaurant_cannot_be_opened_by_its_uuid(): void
    {
        $pending = Restaurant::factory()->discoverable()->pendingVerification()->named('Pending')
            ->at(...RestaurantFixtures::offset(
                0.4, 800, RestaurantFixtures::ORIGIN, RestaurantFixtures::DESTINATION,
            ))
            ->create();

        $this->asRahul()->getJson($this->url($pending->uuid))
            ->assertNotFound()
            ->assertJsonPath('error.code', ApiErrorCode::RestaurantUnavailable->value);
    }

    public function test_a_disabled_restaurant_cannot_be_opened_by_its_uuid(): void
    {
        $disabled = Restaurant::factory()->discoverable()->disabled()->named('Disabled')
            ->at(...RestaurantFixtures::offset(
                0.4, 800, RestaurantFixtures::ORIGIN, RestaurantFixtures::DESTINATION,
            ))
            ->create();

        $this->asRahul()->getJson($this->url($disabled->uuid))
            ->assertNotFound()
            ->assertJsonPath('error.code', ApiErrorCode::RestaurantUnavailable->value);
    }

    public function test_a_permanently_closed_restaurant_cannot_be_opened_by_its_uuid(): void
    {
        $gone = $this->onRoute('Gone For Good');
        $gone->forceFill(['status' => RestaurantStatus::ClosedPermanently])->save();

        $this->asRahul()->getJson($this->url($gone->uuid))
            ->assertNotFound()
            ->assertJsonPath('error.code', ApiErrorCode::RestaurantUnavailable->value);
    }

    public function test_a_missing_restaurant_and_a_withdrawn_one_answer_the_same_status(): void
    {
        $suspended = Restaurant::factory()->discoverable()->suspended()
            ->at(...RestaurantFixtures::offset(
                0.4, 800, RestaurantFixtures::ORIGIN, RestaurantFixtures::DESTINATION,
            ))
            ->create();

        $missing = $this->asRahul()
            ->getJson($this->url('00000000-0000-4000-8000-000000000000'))
            ->assertNotFound();

        $withdrawn = $this->asRahul()->getJson($this->url($suspended->uuid))->assertNotFound();

        // Both 404. A 403 on the suspended one would tell anybody holding a
        // list of uuids exactly which businesses this platform has suspended.
        $this->assertSame(404, $missing->status());
        $this->assertSame(404, $withdrawn->status());
    }

    public function test_a_restaurant_that_is_simply_elsewhere_says_so(): void
    {
        $elsewhere = Restaurant::factory()->discoverable()->named('Mumbai Kitchen')
            ->at(19.0760, 72.8777)
            ->create();

        // Trading, and the customer may see it — it is just not on this
        // journey, so its detour and distance-ahead do not exist for this
        // route. Inventing them is the one thing this product must not do.
        $this->asRahul()->getJson($this->url($elsewhere->uuid))
            ->assertStatus(409)
            ->assertJsonPath('error.code', ApiErrorCode::RestaurantOutsideRoute->value);
    }

    public function test_a_restaurant_withdrawn_between_the_list_and_the_tap(): void
    {
        $restaurant = $this->onRoute();

        // Warm the discovery cache, the way a customer scrolling the list does.
        $this->asRahul()->getJson('/api/v1/customer/trips/'.$this->trip->uuid.'/restaurants')
            ->assertOk();

        $restaurant->forceFill(['status' => RestaurantStatus::Suspended])->save();

        // The race the module has to survive: it was on screen a second ago.
        $this->asRahul()->getJson($this->url($restaurant->uuid))
            ->assertNotFound()
            ->assertJsonPath('error.code', ApiErrorCode::RestaurantUnavailable->value);
    }

    // --- ownership and route state -------------------------------------------

    public function test_an_unauthenticated_call_reaches_no_restaurant(): void
    {
        $restaurant = $this->onRoute();

        $this->getJson($this->url($restaurant->uuid))->assertUnauthorized();
    }

    public function test_a_foreign_trip_is_not_found(): void
    {
        $restaurant = $this->onRoute();

        $ananya = CustomerFactory::ananya();
        $hers = RestaurantFixtures::tripWithSelectedRoute($ananya);

        $this->asRahul()->getJson($this->url($restaurant->uuid, $hers))->assertNotFound();
    }

    public function test_a_trip_with_no_route_is_refused_before_the_restaurant_matters(): void
    {
        $restaurant = $this->onRoute();
        $bare = Trip::factory()->ownedBy($this->rahul)->create();

        $this->asRahul()->getJson($this->url($restaurant->uuid, $bare))
            ->assertStatus(409)
            ->assertJsonPath('error.code', ApiErrorCode::RouteNotReady->value);
    }

    public function test_a_route_whose_endpoints_moved_is_refused(): void
    {
        $restaurant = $this->onRoute();

        $this->trip->forceFill([
            'destination_latitude' => 19.0760,
            'destination_longitude' => 72.8777,
        ])->save();

        $this->asRahul()->getJson($this->url($restaurant->uuid))
            ->assertStatus(409)
            ->assertJsonPath('error.code', ApiErrorCode::RouteNotReady->value);
    }

    // --- privacy --------------------------------------------------------------

    public function test_the_response_carries_no_private_restaurant_data(): void
    {
        $restaurant = $this->onRoute();

        $restaurant->forceFill([
            'owner_name' => 'Meera Kulkarni',
            'owner_phone' => '+919812345678',
            'owner_email' => 'owner@example.test',
            'tax_identifier' => '07AABCU9603R1ZM',
            'bank_account_reference' => 'HDFC-XXXX-4412',
            'commission_rate' => 18.50,
            'internal_notes' => 'Late on settlements. Watch.',
            'public_phone' => '+911412345678',
        ])->save();

        $body = $this->asRahul()->getJson($this->url($restaurant->uuid))->assertOk()->content();

        // Asserted against the raw body: a leak nested three levels down inside
        // a relation would still be a leak, and a structural assertion would
        // not see it.
        foreach ([
            'Meera Kulkarni', '+919812345678', 'owner@example.test',
            '07AABCU9603R1ZM', 'HDFC-XXXX-4412', '18.50', 'Late on settlements',
            'owner_name', 'owner_phone', 'owner_email', 'tax_identifier',
            'bank_account_reference', 'commission_rate', 'internal_notes',
            'verification_status', 'is_discoverable', 'deleted_at',
        ] as $secret) {
            $this->assertStringNotContainsString($secret, $body, "leaked: {$secret}");
        }

        // The published business number is a different column and is allowed.
        $this->assertStringContainsString('+911412345678', $body);
    }

    public function test_no_internal_database_key_is_exposed(): void
    {
        $restaurant = $this->onRoute();

        $data = $this->asRahul()->getJson($this->url($restaurant->uuid))->assertOk()->json('data');

        $this->assertMatchesRegularExpression('/^[0-9a-f-]{36}$/', $data['id']);
        $this->assertArrayNotHasKey('restaurant_id', $data);
        $this->assertStringNotContainsString(
            (string) $restaurant->id,
            json_encode($data['id'], JSON_THROW_ON_ERROR),
        );
    }

    public function test_markup_in_a_restaurants_own_text_comes_back_as_text(): void
    {
        $restaurant = $this->onRoute('<script>alert(1)</script> Kitchen');
        $restaurant->forceFill([
            'description' => '<img src=x onerror="alert(1)"> Great food',
        ])->save();

        $data = $this->asRahul()->getJson($this->url($restaurant->uuid))->assertOk()->json('data');

        // Stored and returned verbatim, as data. It is the renderer's job not
        // to execute it — Flutter draws text, and a future React surface must
        // not hand this to dangerouslySetInnerHTML. What must NOT happen here
        // is silent mangling that hides the problem from whoever finds it.
        $this->assertSame('<script>alert(1)</script> Kitchen', $data['name']);
        $this->assertStringContainsString('onerror', $data['description']);
    }

    // --- optional metadata, honestly absent ----------------------------------

    public function test_a_restaurant_with_nothing_optional_omits_it_rather_than_inventing_it(): void
    {
        $restaurant = RestaurantFixtures::nearRoute(
            0.4, 800, 'Bare Bones Stop', cuisines: ['Fast Food'], facilities: [],
        );
        $restaurant->forceFill(['price_level' => null])->save();

        $data = $this->asRahul()->getJson($this->url($restaurant->uuid))->assertOk()->json('data');

        $this->assertNull($data['description']);
        $this->assertNull($data['public_phone']);
        $this->assertNull($data['price_level']);
        $this->assertNull($data['rating']);
        $this->assertNull($data['review_count']);
        $this->assertSame([], $data['media']);
        $this->assertSame([], $data['facilities']);
    }

    public function test_a_rating_that_does_not_exist_is_null_rather_than_zero(): void
    {
        $restaurant = $this->onRoute();

        $data = $this->asRahul()->getJson($this->url($restaurant->uuid))->assertOk()->json('data');

        // Not 0.0, which a customer reads as "everybody hated it".
        $this->assertNull($data['rating']);
        $this->assertNull($data['review_count']);
    }

    // --- media ----------------------------------------------------------------

    public function test_media_comes_back_in_order_with_its_captions(): void
    {
        $restaurant = $this->onRoute();

        foreach ([
            ['position' => 1, 'alt_text' => 'The terrace at dusk'],
            ['position' => 0, 'alt_text' => 'The dining room'],
        ] as $image) {
            RestaurantMedia::add($restaurant, [
                'url' => 'https://cdn.example.test/'.$image['position'].'.jpg',
                'alt_text' => $image['alt_text'],
                'position' => $image['position'],
                'is_active' => true,
            ]);
        }

        $media = $this->asRahul()->getJson($this->url($restaurant->uuid))
            ->assertOk()
            ->json('data.media');

        $this->assertSame(
            ['The dining room', 'The terrace at dusk'],
            array_column($media, 'alt_text'),
        );
    }

    public function test_an_unmoderated_image_never_reaches_a_customer(): void
    {
        $restaurant = $this->onRoute();

        RestaurantMedia::add($restaurant, [
            'url' => 'https://cdn.example.test/awaiting-review.jpg',
            'position' => 0,
            'is_active' => false,
        ]);

        $body = $this->asRahul()->getJson($this->url($restaurant->uuid))->assertOk()->content();

        // Uploaded and not yet looked at. Defaulting to invisible puts the
        // mistake on the safe side.
        $this->assertStringNotContainsString('awaiting-review', $body);
    }

    public function test_a_thumbnail_falls_back_to_the_full_image(): void
    {
        $restaurant = $this->onRoute();

        RestaurantMedia::add($restaurant, [
            'url' => 'https://cdn.example.test/full.jpg',
            'position' => 0,
            'is_active' => true,
        ]);

        $image = $this->asRahul()->getJson($this->url($restaurant->uuid))
            ->assertOk()
            ->json('data.media.0');

        // A client that asked for a thumbnail and got null renders a hole.
        $this->assertSame('https://cdn.example.test/full.jpg', $image['thumbnail_url']);
        $this->assertNull($image['alt_text']);
    }

    // --- ordering state --------------------------------------------------------

    public function test_an_open_restaurant_may_be_ordered_from(): void
    {
        $restaurant = $this->onRoute();

        $this->asRahul()->getJson($this->url($restaurant->uuid))
            ->assertOk()
            ->assertJsonPath('data.ordering.state', 'OPEN_ACCEPTING')
            ->assertJsonPath('data.ordering.can_order', true);
    }

    public function test_a_paused_kitchen_is_open_and_not_orderable(): void
    {
        $restaurant = $this->onRoute();
        $restaurant->forceFill(['is_accepting_orders' => false])->save();

        $this->asRahul()->getJson($this->url($restaurant->uuid))
            ->assertOk()
            ->assertJsonPath('data.availability', 'NOT_ACCEPTING_ORDERS')
            ->assertJsonPath('data.ordering.state', 'OPEN_PAUSED')
            ->assertJsonPath('data.ordering.can_order', false)
            // The menu is still worth reading: the pause may lift before the
            // traveller arrives.
            ->assertJsonPath('data.ordering.can_browse_menu', true);
    }

    public function test_a_closed_restaurant_says_when_it_opens_again(): void
    {
        // Pinned, like the availability tests it shares a fixture with. A
        // restaurant opening at 02:00 local is genuinely OPEN between 02:00 and
        // 03:00 IST — 20:30 to 21:30 UTC — and this assertion would fail there
        // because the code was right. 06:30 UTC is noon in Kolkata: hours from
        // either edge of the window and from either soon-threshold.
        Carbon::setTestNow('2026-09-07 06:30:00');
        $restaurant = RestaurantFixtures::nearRoute(0.4, 800, 'Shut Cafe', open: false);
        RestaurantFixtures::openDaily($restaurant, '02:00:00', '03:00:00');

        $data = $this->asRahul()->getJson($this->url($restaurant->uuid))
            ->assertOk()
            ->assertJsonPath('data.ordering.state', 'CLOSED')
            ->assertJsonPath('data.ordering.can_order', false)
            ->json('data');

        $this->assertNotNull($data['hours']['next_open_at']);
        $this->assertNull($data['hours']['current_window']);
    }

    public function test_a_restaurant_with_no_hours_on_file_is_unavailable_not_open(): void
    {
        $restaurant = RestaurantFixtures::nearRoute(0.4, 800, 'Hours Unknown', open: false);

        $this->asRahul()->getJson($this->url($restaurant->uuid))
            ->assertOk()
            ->assertJsonPath('data.availability', 'UNKNOWN')
            ->assertJsonPath('data.ordering.state', 'UNAVAILABLE')
            ->assertJsonPath('data.ordering.can_order', false)
            ->assertJsonPath('data.hours.next_open_at', null);
    }

    public function test_a_pause_applied_after_the_list_was_read_is_reflected(): void
    {
        $restaurant = $this->onRoute();

        $this->asRahul()->getJson('/api/v1/customer/trips/'.$this->trip->uuid.'/restaurants')
            ->assertOk()
            ->assertJsonPath('data.restaurants.0.availability', 'OPEN');

        $restaurant->forceFill(['is_accepting_orders' => false])->save();

        // The discovery result may be five minutes old. The detail screen reads
        // the row again and must not present a stale "accepting orders".
        $this->asRahul()->getJson($this->url($restaurant->uuid))
            ->assertOk()
            ->assertJsonPath('data.ordering.state', 'OPEN_PAUSED');
    }

    // --- cost -----------------------------------------------------------------

    public function test_opening_a_restaurant_is_served_from_the_discovery_cache(): void
    {
        $restaurant = $this->onRoute();

        $this->asRahul()->getJson('/api/v1/customer/trips/'.$this->trip->uuid.'/restaurants')
            ->assertOk()
            ->assertJsonPath('data.meta.from_cache', false);

        // Every subsequent open reuses the corridor search. This is the
        // module's cost guarantee, and it is why the detail endpoint asks
        // Module 07 rather than searching for itself.
        foreach (range(1, 3) as $ignored) {
            $this->asRahul()->getJson($this->url($restaurant->uuid))
                ->assertOk()
                ->assertJsonPath('data.route_from_cache', true);
        }
    }

    public function test_the_endpoint_is_rate_limited(): void
    {
        config(['foodonthego.rate_limits.discovery' => 3]);

        $restaurant = $this->onRoute();

        foreach (range(1, 3) as $ignored) {
            $this->asRahul()->getJson($this->url($restaurant->uuid))->assertOk();
        }

        // Sharing the list's budget is what stops a loop over uuids from being
        // a cheaper way to spend it.
        $this->asRahul()->getJson($this->url($restaurant->uuid))->assertStatus(429);
    }

    // --- read-only -------------------------------------------------------------

    public function test_a_customer_has_no_way_to_change_a_restaurant(): void
    {
        $restaurant = $this->onRoute();

        foreach (['put', 'patch', 'delete', 'post'] as $method) {
            $response = $this->asRahul()->json(strtoupper($method), $this->url($restaurant->uuid));

            // 405 or 404 — never a success. There is no customer-facing write
            // route for a restaurant's hours, facilities, price or coordinates.
            $this->assertContains(
                $response->status(),
                [404, 405],
                "{$method} was accepted",
            );
        }

        $this->assertSame('Highway Spice Kitchen', $restaurant->fresh()->name);
    }
}
