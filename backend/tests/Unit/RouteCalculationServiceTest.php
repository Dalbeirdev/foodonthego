<?php

declare(strict_types=1);

namespace Tests\Unit;

use App\Enums\ApiErrorCode;
use App\Enums\RouteStatus;
use App\Exceptions\ApiException;
use App\Models\Trip;
use App\Models\TripRoute;
use App\Models\User;
use App\Services\Routing\RouteBounds;
use App\Services\Routing\RouteCalculationService;
use App\Services\Routing\RouteFailureKind;
use App\Services\Routing\RouteOption;
use App\Services\Routing\RouteProvider;
use App\Services\Routing\RouteProviderException;
use App\Services\Routing\RouteRequest;
use App\Services\Routing\RouteResult;
use App\Services\Routing\RouteValidator;
use App\Support\Route\PolylineCodec;
use Carbon\CarbonImmutable;
use Illuminate\Contracts\Cache\Repository;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Support\CustomerFactory;
use Tests\TestCase;

/**
 * The service that turns a trip into routes.
 *
 * Two things it is judged on here above all others. **It must not call the
 * provider when it does not have to** — every call is billed, and the screen
 * that shows a route is the one people reopen. And **it must not half-store**:
 * a trip marked READY with no routes under it, or routes with no selection, is
 * corruption that every later module inherits.
 */
final class RouteCalculationServiceTest extends TestCase
{
    use RefreshDatabase;

    private const DELHI = [28.5494, 77.2001];

    private const JAIPUR = [26.8242, 75.8122];

    private User $rahul;

    protected function setUp(): void
    {
        parent::setUp();

        $this->rahul = CustomerFactory::rahul();
    }

    private function trip(): Trip
    {
        return Trip::factory()->ownedBy($this->rahul)->create();
    }

    private function service(RouteProvider $provider): RouteCalculationService
    {
        return new RouteCalculationService(
            provider: $provider,
            validator: new RouteValidator(maxPolylineBytes: 512_000, endpointToleranceMetres: 5_000),
            cache: $this->app->make(Repository::class),
        );
    }

    /** A decodable line from Hauz Khas to Jaipur airport, for the doubles above. */
    public static function line(): string
    {
        $points = [];

        for ($i = 0; $i <= 20; $i++) {
            $fraction = $i / 20;
            $points[] = [
                self::DELHI[0] + (self::JAIPUR[0] - self::DELHI[0]) * $fraction,
                self::DELHI[1] + (self::JAIPUR[1] - self::DELHI[1]) * $fraction,
            ];
        }

        return PolylineCodec::encode($points);
    }

    private function now(): CarbonImmutable
    {
        return CarbonImmutable::parse('2026-09-05T09:00:00Z');
    }

    // --- cost control -------------------------------------------------------

    public function test_a_fresh_route_is_served_without_calling_the_provider(): void
    {
        $provider = new RecordingRouteProvider;
        $trip = $this->trip();

        $this->service($provider)->calculate($trip, $this->now());
        $this->assertSame(1, $provider->calls);

        // The cost control. Opening the route screen twice must cost once.
        $this->service($provider)->calculate($trip->refresh(), $this->now()->addMinutes(2));
        $this->assertSame(1, $provider->calls);
    }

    public function test_a_stale_route_is_recalculated(): void
    {
        $provider = new RecordingRouteProvider;
        $trip = $this->trip();

        $this->service($provider)->calculate($trip, $this->now());

        // Past the freshness window: the geometry has not changed, but the
        // traffic figure on it is no longer something we will call current.
        $freshness = (int) config('foodonthego.routing.freshness_seconds');
        $this->service($provider)->calculate($trip->refresh(), $this->now()->addSeconds($freshness + 60));

        $this->assertSame(2, $provider->calls);
    }

    public function test_a_forced_refresh_calls_the_provider_even_when_fresh(): void
    {
        $provider = new RecordingRouteProvider;
        $trip = $this->trip();

        $this->service($provider)->calculate($trip, $this->now());
        $this->service($provider)->calculate($trip->refresh(), $this->now(), force: true);

        $this->assertSame(2, $provider->calls);
    }

    public function test_repeated_calculation_replaces_rather_than_accumulates(): void
    {
        $provider = new RecordingRouteProvider(alternatives: 3);
        $trip = $this->trip();

        for ($i = 0; $i < 5; $i++) {
            $this->service($provider)->calculate($trip->refresh(), $this->now(), force: true);
        }

        // Five calculations, one logical route set. Ten taps must not produce
        // thirty rows.
        $this->assertSame(3, TripRoute::query()->forTrip($trip)->count());
        $this->assertSame(1, TripRoute::query()->forTrip($trip)->where('is_selected', true)->count());
    }

    // --- what gets stored ---------------------------------------------------

    public function test_a_successful_calculation_stores_metres_and_seconds(): void
    {
        $trip = $this->trip();

        $routes = $this->service(new RecordingRouteProvider)->calculate($trip, $this->now());

        $route = $routes->first();
        $this->assertSame(278_000, $route->distance_meters);
        $this->assertSame(16_200, $route->duration_seconds);
        $this->assertSame(17_100, $route->traffic_duration_seconds);
        $this->assertSame(900, $route->trafficDelaySeconds());
        // Never a formatted string: "278 km" cannot be summed or shown in miles.
        $this->assertIsInt($route->distance_meters);
    }

    public function test_the_recommended_route_is_selected_by_default(): void
    {
        $trip = $this->trip();

        $routes = $this->service(new RecordingRouteProvider(alternatives: 3))->calculate($trip, $this->now());

        // A customer who never opens the alternatives still has a route.
        $selected = $routes->firstWhere('is_selected', true);
        $this->assertSame(0, $selected->provider_route_index);
        $this->assertTrue($selected->is_recommended);
    }

    public function test_success_marks_the_trip_ready(): void
    {
        $trip = $this->trip();

        $this->service(new RecordingRouteProvider)->calculate($trip, $this->now());

        $this->assertSame(RouteStatus::Ready, $trip->refresh()->route_status);
    }

    public function test_the_trip_is_never_ready_without_routes_underneath_it(): void
    {
        $trip = $this->trip();

        $this->service(new RecordingRouteProvider)->calculate($trip, $this->now());

        // The invariant every later module inherits.
        $this->assertSame(RouteStatus::Ready, $trip->refresh()->route_status);
        $this->assertGreaterThan(0, TripRoute::query()->forTrip($trip)->count());
    }

    public function test_the_calculation_time_is_recorded(): void
    {
        $trip = $this->trip();

        $routes = $this->service(new RecordingRouteProvider)->calculate($trip, $this->now());

        // What a later module uses to decide a recalculation is due.
        $this->assertTrue($this->now()->equalTo($routes->first()->calculated_at));
    }

    // --- failures -----------------------------------------------------------

    public function test_a_provider_outage_marks_the_trip_failed_and_stores_nothing(): void
    {
        $trip = $this->trip();

        try {
            $this->service(new FailingRouteProvider(RouteFailureKind::Unavailable))
                ->calculate($trip, $this->now());
            $this->fail('an outage should have raised');
        } catch (ApiException $e) {
            $this->assertSame(ApiErrorCode::RouteProviderUnavailable, $e->errorCode);
        }

        $this->assertSame(RouteStatus::Failed, $trip->refresh()->route_status);
        $this->assertSame(0, TripRoute::query()->forTrip($trip)->count());
    }

    public function test_a_timeout_has_its_own_code(): void
    {
        $trip = $this->trip();

        try {
            $this->service(new FailingRouteProvider(RouteFailureKind::Timeout))->calculate($trip, $this->now());
            $this->fail('a timeout should have raised');
        } catch (ApiException $e) {
            $this->assertSame(ApiErrorCode::RouteTimeout, $e->errorCode);
        }
    }

    public function test_a_rate_limit_has_its_own_code(): void
    {
        $trip = $this->trip();

        try {
            $this->service(new FailingRouteProvider(RouteFailureKind::RateLimited))->calculate($trip, $this->now());
            $this->fail('a rate limit should have raised');
        } catch (ApiException $e) {
            // The customer waits rather than retrying immediately.
            $this->assertSame(ApiErrorCode::RouteProviderRateLimited, $e->errorCode);
        }
    }

    public function test_a_refused_key_never_tells_the_customer_about_our_key(): void
    {
        $trip = $this->trip();

        try {
            $this->service(new FailingRouteProvider(RouteFailureKind::NotAuthorised))->calculate($trip, $this->now());
            $this->fail('an authorisation failure should have raised');
        } catch (ApiException $e) {
            // An operational emergency for us, an outage for them.
            $this->assertSame(ApiErrorCode::RouteProviderUnavailable, $e->errorCode);
            $this->assertStringNotContainsString('key', strtolower($e->getMessage()));
        }
    }

    public function test_no_route_is_told_apart_from_a_failure(): void
    {
        $trip = $this->trip();

        try {
            $this->service(new EmptyRouteProvider)->calculate($trip, $this->now());
            $this->fail('an empty result should have raised');
        } catch (ApiException $e) {
            // Retrying will be told the same thing; the answer is to change an
            // endpoint, and the code has to say so.
            $this->assertSame(ApiErrorCode::RouteNoRouteFound, $e->errorCode);
        }

        $this->assertSame(RouteStatus::NoRoute, $trip->refresh()->route_status);
    }

    public function test_a_response_that_fails_validation_is_our_problem_not_the_customers(): void
    {
        $trip = $this->trip();

        try {
            $this->service(new MalformedRouteProvider)->calculate($trip, $this->now());
            $this->fail('a malformed result should have raised');
        } catch (ApiException $e) {
            $this->assertSame(ApiErrorCode::RouteResponseInvalid, $e->errorCode);
        }

        // Not NO_ROUTE: the provider found something, we could not use it.
        $this->assertSame(RouteStatus::Failed, $trip->refresh()->route_status);
        $this->assertSame(0, TripRoute::query()->forTrip($trip)->count());
    }

    public function test_a_transient_failure_does_not_destroy_a_working_route(): void
    {
        $trip = $this->trip();
        $this->service(new RecordingRouteProvider)->calculate($trip, $this->now());

        try {
            $this->service(new FailingRouteProvider(RouteFailureKind::Unavailable))
                ->calculate($trip->refresh(), $this->now(), force: true);
        } catch (ApiException) {
            // Expected.
        }

        // The geometry is still valid for these endpoints. Replacing a usable
        // route with an error state punishes the customer for our outage.
        $trip->refresh();
        $this->assertSame(RouteStatus::Ready, $trip->route_status);
        $this->assertSame(1, TripRoute::query()->forTrip($trip)->count());
    }

    public function test_no_route_does_clear_a_previous_route(): void
    {
        $trip = $this->trip();
        $this->service(new RecordingRouteProvider)->calculate($trip, $this->now());

        try {
            $this->service(new EmptyRouteProvider)->calculate($trip->refresh(), $this->now(), force: true);
        } catch (ApiException) {
            // Expected.
        }

        // The provider has just said this journey cannot be driven. Anything
        // stored describes a route it says does not exist.
        $this->assertSame(RouteStatus::NoRoute, $trip->refresh()->route_status);
        $this->assertSame(0, TripRoute::query()->forTrip($trip)->count());
    }

    // --- eligibility, before a provider is troubled -------------------------

    public function test_a_discarded_trip_is_not_routed(): void
    {
        $provider = new RecordingRouteProvider;
        $trip = Trip::factory()->ownedBy($this->rahul)->discarded()->create();

        try {
            $this->service($provider)->calculate($trip, $this->now());
            $this->fail('a discarded trip should not be routed');
        } catch (ApiException $e) {
            $this->assertSame(ApiErrorCode::TripNotEditable, $e->errorCode);
        }

        $this->assertSame(0, $provider->calls);
    }

    public function test_two_endpoints_in_the_same_place_never_reach_the_provider(): void
    {
        $provider = new RecordingRouteProvider;

        $trip = Trip::factory()->ownedBy($this->rahul)->create([
            'destination_latitude' => self::DELHI[0],
            'destination_longitude' => self::DELHI[1],
            'origin_latitude' => self::DELHI[0],
            'origin_longitude' => self::DELHI[1],
        ]);

        try {
            $this->service($provider)->calculate($trip, $this->now());
            $this->fail('the same place at both ends should not be routed');
        } catch (ApiException $e) {
            $this->assertSame(ApiErrorCode::SameLocation, $e->errorCode);
        }

        // Module 05's rule, enforced again here so a caller arriving another way
        // cannot spend a billed call on it.
        $this->assertSame(0, $provider->calls);
    }

    public function test_an_impossible_coordinate_never_reaches_the_provider(): void
    {
        $provider = new RecordingRouteProvider;

        $trip = Trip::factory()->ownedBy($this->rahul)->create();
        // Written past the model, the way a bad importer or a repair script
        // would: this service is the last thing standing before a billed call.
        Trip::query()->whereKey($trip->getKey())->update(['origin_latitude' => 0, 'origin_longitude' => 0]);

        try {
            $this->service($provider)->calculate($trip->refresh(), $this->now());
            $this->fail('Null Island should not be routed');
        } catch (ApiException $e) {
            $this->assertSame(ApiErrorCode::RouteInputInvalid, $e->errorCode);
        }

        $this->assertSame(0, $provider->calls);
    }

    // --- endpoint change ----------------------------------------------------

    public function test_moving_an_endpoint_invalidates_the_route(): void
    {
        $trip = $this->trip();
        $this->service(new RecordingRouteProvider)->calculate($trip, $this->now());
        $this->assertSame(RouteStatus::Ready, $trip->refresh()->route_status);

        // The customer changes where they are going.
        Trip::query()->whereKey($trip->getKey())->update([
            'destination_latitude' => 30.7412,
            'destination_longitude' => 76.7825,
            'destination_name' => 'Sector 17 Plaza',
        ]);

        $invalidated = $this->service(new RecordingRouteProvider)
            ->invalidateIfEndpointsChanged($trip->refresh());

        $this->assertTrue($invalidated);
        // A stale route is worse than none: real geometry for the wrong journey,
        // and entirely convincing.
        $this->assertSame(RouteStatus::NotCalculated, $trip->refresh()->route_status);
        $this->assertSame(0, TripRoute::query()->forTrip($trip)->count());
    }

    public function test_an_unchanged_trip_is_not_invalidated(): void
    {
        $trip = $this->trip();
        $this->service(new RecordingRouteProvider)->calculate($trip, $this->now());

        $this->assertFalse(
            $this->service(new RecordingRouteProvider)->invalidateIfEndpointsChanged($trip->refresh()),
        );
        $this->assertSame(RouteStatus::Ready, $trip->refresh()->route_status);
    }

    public function test_a_stale_route_is_never_returned_as_the_selection(): void
    {
        $trip = $this->trip();
        $this->service(new RecordingRouteProvider)->calculate($trip, $this->now());

        Trip::query()->whereKey($trip->getKey())->update(['destination_latitude' => 30.7412]);

        $this->assertNull($this->service(new RecordingRouteProvider)->selectedRouteFor($trip->refresh()));
    }
}

/**
 * A provider that answers predictably, counts what it was asked, and can be
 * made to fail or to find nothing **without being replaced**.
 *
 * The mutability is not laziness. Laravel caches a resolved controller on the
 * `Route` object, and routes outlive a single request inside one test process —
 * so swapping a container binding halfway through a feature test changes what
 * `make()` returns and *not* what the already-constructed controller holds. A
 * double with a switch tests the recovery path honestly; a second
 * `$app->instance()` call silently tests nothing.
 */
final class RecordingRouteProvider implements RouteProvider
{
    public int $calls = 0;

    public ?RouteRequest $lastRequest = null;

    /** Set to make the next call fail in a particular way. */
    public ?RouteFailureKind $failWith = null;

    /** Set to make the next call succeed with no route at all. */
    public bool $findsNothing = false;

    public function __construct(private readonly int $alternatives = 1) {}

    public function name(): string
    {
        return 'recording';
    }

    public function calculate(RouteRequest $request): RouteResult
    {
        $this->calls++;
        $this->lastRequest = $request;

        if ($this->failWith !== null) {
            throw new RouteProviderException(
                $this->failWith,
                'quota exceeded for project fotg-123, key AIza…',
            );
        }

        if ($this->findsNothing) {
            return new RouteResult([], $this->name());
        }

        $options = [];

        for ($index = 0; $index < $this->alternatives; $index++) {
            $options[] = new RouteOption(
                index: $index,
                distanceMeters: 278_000 - ($index * 13_000),
                durationSeconds: 16_200 + ($index * 840),
                trafficDurationSeconds: $index === 0 ? 17_100 : null,
                encodedPolyline: RouteCalculationServiceTest::line(),
                bounds: new RouteBounds(north: 28.5494, south: 26.8242, east: 77.2001, west: 75.8122),
                summary: $index === 0 ? 'NH 48' : 'NH 148N',
            );
        }

        return new RouteResult($options, $this->name());
    }
}

/** A provider that is down, in a particular way. */
final class FailingRouteProvider implements RouteProvider
{
    public function __construct(private readonly RouteFailureKind $kind) {}

    public function name(): string
    {
        return 'failing';
    }

    public function calculate(RouteRequest $request): RouteResult
    {
        throw new RouteProviderException($this->kind, 'quota exceeded for project fotg-123, key AIza…');
    }
}

/** A provider that found no driving route. Successful, and empty. */
final class EmptyRouteProvider implements RouteProvider
{
    public function name(): string
    {
        return 'empty';
    }

    public function calculate(RouteRequest $request): RouteResult
    {
        return new RouteResult([], $this->name());
    }
}

/** A provider whose answer will not survive validation. */
final class MalformedRouteProvider implements RouteProvider
{
    public function name(): string
    {
        return 'malformed';
    }

    public function calculate(RouteRequest $request): RouteResult
    {
        return new RouteResult([new RouteOption(
            index: 0,
            // Negative distance, zero duration, unusable geometry: every rule at
            // once.
            distanceMeters: -1,
            durationSeconds: 0,
            trafficDurationSeconds: null,
            encodedPolyline: "\x01\x02\x03",
            bounds: new RouteBounds(north: 1, south: 2, east: 3, west: 4),
            summary: null,
        )], $this->name());
    }
}
