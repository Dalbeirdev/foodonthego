<?php

declare(strict_types=1);

namespace Tests\Unit;

use App\Services\Routing\DevelopmentRouteProvider;
use App\Services\Routing\GoogleRouteProvider;
use App\Services\Routing\RouteFailureKind;
use App\Services\Routing\RouteProviderException;
use App\Services\Routing\RouteRequest;
use App\Services\Routing\UnconfiguredRouteProvider;
use App\Support\Route\PolylineCodec;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\Client\Factory as HttpFactory;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

/**
 * The three routing providers.
 *
 * The Google one is exercised against a **stubbed HTTP transport**, not against
 * Google. That is a deliberate limit and it is stated plainly in this module's
 * evidence: no Routes credentials exist in this environment and the provider
 * refuses unauthenticated callers, so what these tests establish is that the
 * adapter sends the right request and reads the documented response *shape*.
 * Whether Google's live responses match that shape is verified the first time a
 * key exists, and until then the module reports live route verification as
 * pending rather than passed.
 *
 * The fixtures below follow the documented Routes API (v2) `computeRoutes`
 * shapes.
 */
final class RouteProviderTest extends TestCase
{
    private const DELHI = [28.5494, 77.2001];

    private const JAIPUR = [26.8242, 75.8122];

    private function google(array $stub): GoogleRouteProvider
    {
        Http::fake($stub);

        return new GoogleRouteProvider(
            http: $this->app->make(HttpFactory::class),
            apiKey: 'test-key',
            timeoutSeconds: 12,
            maxAlternatives: 3,
            languageCode: 'en-IN',
        );
    }

    private function request(bool $alternatives = true, bool $trafficAware = true): RouteRequest
    {
        return new RouteRequest(
            originLatitude: self::DELHI[0],
            originLongitude: self::DELHI[1],
            destinationLatitude: self::JAIPUR[0],
            destinationLongitude: self::JAIPUR[1],
            withAlternatives: $alternatives,
            trafficAware: $trafficAware,
        );
    }

    private static function polyline(): string
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

    /** @return array<string, mixed> */
    private static function route(string $duration, ?string $static, int $metres = 278_000): array
    {
        $route = [
            'distanceMeters' => $metres,
            'duration' => $duration,
            'polyline' => ['encodedPolyline' => self::polyline()],
            'description' => 'NH 48',
            'viewport' => [
                'high' => ['latitude' => 28.6, 'longitude' => 77.3],
                'low' => ['latitude' => 26.8, 'longitude' => 75.8],
            ],
        ];

        if ($static !== null) {
            $route['staticDuration'] = $static;
        }

        return $route;
    }

    // --- what the adapter sends --------------------------------------------

    public function test_the_key_and_the_field_mask_are_sent_as_headers(): void
    {
        $provider = $this->google(['*' => Http::response(['routes' => []])]);

        $provider->calculate($this->request());

        Http::assertSent(function ($request): bool {
            // In the header, never a query string: a key in a URL reaches access
            // logs, proxy logs and referrer headers. And a field mask, because
            // Routes v2 bills by the fields requested.
            return $request->hasHeader('X-Goog-Api-Key', 'test-key')
                && $request->hasHeader('X-Goog-FieldMask')
                && ! str_contains($request->url(), 'test-key');
        });
    }

    public function test_the_field_mask_asks_for_exactly_what_is_read(): void
    {
        $provider = $this->google(['*' => Http::response(['routes' => []])]);

        $provider->calculate($this->request());

        Http::assertSent(function ($request): bool {
            $mask = $request->header('X-Goog-FieldMask')[0];

            foreach ([
                'routes.distanceMeters',
                'routes.duration',
                'routes.staticDuration',
                'routes.polyline.encodedPolyline',
            ] as $field) {
                if (! str_contains($mask, $field)) {
                    return false;
                }
            }

            // A wildcard would bill for every field Google has.
            return ! str_contains($mask, '*');
        });
    }

    public function test_traffic_aware_routing_sends_a_preference_and_a_departure_time(): void
    {
        $provider = $this->google(['*' => Http::response(['routes' => []])]);

        $provider->calculate($this->request(trafficAware: true));

        Http::assertSent(function ($request): bool {
            $body = $request->data();

            return ($body['routingPreference'] ?? null) === 'TRAFFIC_AWARE'
                // The traffic model has to be anchored to a moment, or there is
                // nothing for it to be aware of.
                && isset($body['departureTime'])
                && ($body['travelMode'] ?? null) === 'DRIVE';
        });
    }

    public function test_traffic_unaware_routing_sends_no_departure_time(): void
    {
        $provider = $this->google(['*' => Http::response(['routes' => []])]);

        $provider->calculate($this->request(trafficAware: false));

        Http::assertSent(function ($request): bool {
            $body = $request->data();

            return ($body['routingPreference'] ?? null) === 'TRAFFIC_UNAWARE'
                && ! isset($body['departureTime']);
        });
    }

    public function test_alternatives_are_asked_for_only_when_wanted(): void
    {
        $provider = $this->google(['*' => Http::response(['routes' => []])]);

        $provider->calculate($this->request(alternatives: false));

        // Each alternative costs the same as the primary route, so this is a
        // billing decision rather than a default worth leaving on.
        Http::assertSent(fn ($request): bool => $request->data()['computeAlternativeRoutes'] === false);
    }

    public function test_no_avoidance_is_forced_on_the_customer(): void
    {
        $provider = $this->google(['*' => Http::response(['routes' => []])]);

        $provider->calculate($this->request());

        Http::assertSent(function ($request): bool {
            $body = json_encode($request->data());

            // Forcing avoid-tolls or avoid-highways would silently hand every
            // customer a worse route than the one they would have chosen.
            return ! str_contains($body, 'avoidTolls')
                && ! str_contains($body, 'avoidHighways')
                && ! str_contains($body, 'avoidFerries');
        });
    }

    // --- the two durations --------------------------------------------------

    public function test_static_duration_is_the_base_and_duration_is_the_traffic_one(): void
    {
        $provider = $this->google([
            '*' => Http::response(['routes' => [self::route(duration: '17100s', static: '16200s')]]),
        ]);

        $option = $provider->calculate($this->request())->options[0];

        // The single most important mapping in this adapter. Routes v2 moves
        // `duration` with the traffic model and leaves `staticDuration` alone;
        // reading them the other way round would make every route look as though
        // traffic were costing exactly nothing.
        $this->assertSame(16_200, $option->durationSeconds);
        $this->assertSame(17_100, $option->trafficDurationSeconds);
        $this->assertSame(900, $option->trafficDelaySeconds());
    }

    public function test_identical_durations_are_not_reported_as_traffic_information(): void
    {
        $provider = $this->google([
            '*' => Http::response(['routes' => [self::route(duration: '16200s', static: '16200s')]]),
        ]);

        $option = $provider->calculate($this->request())->options[0];

        // "Traffic is adding zero seconds" is a claim about the roads. Absence
        // of a traffic reading is not that claim.
        $this->assertSame(16_200, $option->durationSeconds);
        $this->assertNull($option->trafficDurationSeconds);
        $this->assertNull($option->trafficDelaySeconds());
    }

    public function test_a_response_without_a_static_duration_has_no_traffic_figure(): void
    {
        $provider = $this->google([
            '*' => Http::response(['routes' => [self::route(duration: '16200s', static: null)]]),
        ]);

        $option = $provider->calculate($this->request())->options[0];

        // TRAFFIC_UNAWARE: `duration` is itself the traffic-free figure, so the
        // base is populated and nothing is invented for the other.
        $this->assertSame(16_200, $option->durationSeconds);
        $this->assertNull($option->trafficDurationSeconds);
    }

    public function test_a_traffic_duration_faster_than_the_base_is_not_a_time_saving(): void
    {
        $provider = $this->google([
            '*' => Http::response(['routes' => [self::route(duration: '15000s', static: '16200s')]]),
        ]);

        $option = $provider->calculate($this->request())->options[0];

        // Two figures computed under different assumptions, not twenty minutes
        // saved by traffic. Reporting it as a delay of minus twenty would be
        // nonsense on a screen.
        $this->assertNull($option->trafficDelaySeconds());
    }

    // --- reading the response -----------------------------------------------

    public function test_it_reads_distance_summary_bounds_and_geometry(): void
    {
        $provider = $this->google([
            '*' => Http::response(['routes' => [self::route('17100s', '16200s')]]),
        ]);

        $option = $provider->calculate($this->request())->options[0];

        $this->assertSame(278_000, $option->distanceMeters);
        $this->assertSame('NH 48', $option->summary);
        $this->assertSame(0, $option->index);
        $this->assertEqualsWithDelta(28.6, $option->bounds->north, 0.001);
        $this->assertNotSame('', $option->encodedPolyline);
    }

    public function test_alternatives_come_back_in_provider_order(): void
    {
        $provider = $this->google([
            '*' => Http::response(['routes' => [
                self::route('17100s', '16200s'),
                self::route('17700s', '17040s', 265_000),
            ]]),
        ]);

        $options = $provider->calculate($this->request())->options;

        $this->assertCount(2, $options);
        // Index 0 is the provider's own recommendation, and the ordering is
        // meaning rather than presentation.
        $this->assertSame(0, $options[0]->index);
        $this->assertSame(1, $options[1]->index);
        $this->assertSame(265_000, $options[1]->distanceMeters);
    }

    public function test_more_alternatives_than_configured_are_dropped(): void
    {
        Http::fake(['*' => Http::response(['routes' => array_fill(0, 6, self::route('17100s', '16200s'))])]);

        $provider = new GoogleRouteProvider(
            http: $this->app->make(HttpFactory::class),
            apiKey: 'test-key',
            timeoutSeconds: 12,
            maxAlternatives: 2,
            languageCode: 'en-IN',
        );

        // Three is a choice; ten is a list nobody reads.
        $this->assertCount(2, $provider->calculate($this->request())->options);
    }

    public function test_no_routes_is_an_empty_result_and_not_a_failure(): void
    {
        $provider = $this->google(['*' => Http::response([])]);

        $result = $provider->calculate($this->request());

        // Routes v2 omits `routes` entirely when there is no route. That is the
        // provider answering, not failing, and the difference decides whether the
        // customer is told to retry or to change where they are going.
        $this->assertTrue($result->isEmpty());
    }

    public function test_an_alternative_with_no_geometry_is_skipped_rather_than_half_built(): void
    {
        $provider = $this->google([
            '*' => Http::response(['routes' => [
                ['distanceMeters' => 278_000, 'duration' => '17100s'],
                self::route('17100s', '16200s'),
            ]]),
        ]);

        $options = $provider->calculate($this->request())->options;

        $this->assertCount(1, $options);
        // Re-indexed, so the surviving route is the recommended one rather than
        // carrying a gap where a broken sibling was.
        $this->assertSame(0, $options[0]->index);
    }

    public function test_an_undecodable_polyline_is_skipped(): void
    {
        $provider = $this->google([
            '*' => Http::response(['routes' => [[
                'distanceMeters' => 278_000,
                'duration' => '17100s',
                'staticDuration' => '16200s',
                'polyline' => ['encodedPolyline' => "\x01\x02\x03"],
            ]]]),
        ]);

        $this->assertTrue($provider->calculate($this->request())->isEmpty());
    }

    // --- failures -----------------------------------------------------------

    public function test_a_rate_limit_is_distinguishable_from_an_outage(): void
    {
        $provider = $this->google(['*' => Http::response(['error' => ['message' => 'quota']], 429)]);

        try {
            $provider->calculate($this->request());
            $this->fail('a 429 should have raised');
        } catch (RouteProviderException $e) {
            // The customer waits rather than retrying immediately, so this needs
            // its own kind.
            $this->assertSame(RouteFailureKind::RateLimited, $e->kind);
        }
    }

    public function test_a_refused_key_is_its_own_kind(): void
    {
        $provider = $this->google(['*' => Http::response(['error' => ['message' => 'API key not valid']], 403)]);

        try {
            $provider->calculate($this->request());
            $this->fail('a 403 should have raised');
        } catch (RouteProviderException $e) {
            $this->assertSame(RouteFailureKind::NotAuthorised, $e->kind);
            // The upstream message names our key state. It reaches the log and
            // no further.
            $this->assertStringNotContainsString('API key not valid', $e->getMessage());
        }
    }

    public function test_a_server_error_is_an_outage(): void
    {
        $provider = $this->google(['*' => Http::response('', 503)]);

        try {
            $provider->calculate($this->request());
            $this->fail('a 503 should have raised');
        } catch (RouteProviderException $e) {
            $this->assertSame(RouteFailureKind::Unavailable, $e->kind);
        }
    }

    public function test_a_body_that_is_not_json_is_an_invalid_response(): void
    {
        $provider = $this->google(['*' => Http::response('<html>gateway</html>', 200)]);

        try {
            $provider->calculate($this->request());
            $this->fail('a non-JSON body should have raised');
        } catch (RouteProviderException $e) {
            // Ours to fix, not the customer's to retry — a gateway page means
            // something between here and Google is answering for it.
            $this->assertSame(RouteFailureKind::InvalidResponse, $e->kind);
        }
    }

    public function test_a_connection_failure_is_an_outage(): void
    {
        Http::fake(fn () => throw new ConnectionException('Connection refused'));

        $provider = new GoogleRouteProvider(
            http: $this->app->make(HttpFactory::class),
            apiKey: 'test-key',
            timeoutSeconds: 12,
            maxAlternatives: 3,
            languageCode: 'en-IN',
        );

        try {
            $provider->calculate($this->request());
            $this->fail('a connection failure should have raised');
        } catch (RouteProviderException $e) {
            $this->assertSame(RouteFailureKind::Unavailable, $e->kind);
        }
    }

    public function test_a_timeout_is_told_apart_from_an_outage(): void
    {
        Http::fake(fn () => throw new ConnectionException(
            'cURL error 28: Operation timed out after 12000 milliseconds',
        ));

        $provider = new GoogleRouteProvider(
            http: $this->app->make(HttpFactory::class),
            apiKey: 'test-key',
            timeoutSeconds: 12,
            maxAlternatives: 3,
            languageCode: 'en-IN',
        );

        try {
            $provider->calculate($this->request());
            $this->fail('a timeout should have raised');
        } catch (RouteProviderException $e) {
            $this->assertSame(RouteFailureKind::Timeout, $e->kind);
        }
    }

    // --- the unconfigured provider ------------------------------------------

    public function test_the_unconfigured_provider_refuses_every_call(): void
    {
        try {
            (new UnconfiguredRouteProvider)->calculate($this->request());
            $this->fail('the unconfigured provider should refuse');
        } catch (RouteProviderException $e) {
            $this->assertStringContainsString('ROUTE_PROVIDER', $e->getMessage());
            $this->assertSame(RouteFailureKind::NotAuthorised, $e->kind);
        }
    }

    // --- the development provider -------------------------------------------

    public function test_the_development_provider_refuses_to_exist_in_production(): void
    {
        $this->expectException(\RuntimeException::class);

        new DevelopmentRouteProvider(isProduction: true);
    }

    public function test_the_development_provider_never_claims_a_traffic_reading(): void
    {
        $option = (new DevelopmentRouteProvider(isProduction: false))
            ->calculate($this->request())
            ->options[0];

        // It has no idea what the traffic is, and a made-up delay is the single
        // most misleading number this module could produce.
        $this->assertNull($option->trafficDurationSeconds);
        $this->assertNull($option->trafficDelaySeconds());
    }

    public function test_the_development_provider_names_itself_in_every_route_it_returns(): void
    {
        $result = (new DevelopmentRouteProvider(isProduction: false))->calculate($this->request());

        // Stored in `trip_routes.provider` and returned in the API payload, so a
        // synthetic row is identifiable for ever — in the database, in a log, and
        // on the screen.
        $this->assertSame('development', $result->provider);
        $this->assertStringContainsString('not a real route', (string) $result->options[0]->summary);
    }

    public function test_the_development_provider_invents_no_alternatives(): void
    {
        $result = (new DevelopmentRouteProvider(isProduction: false))->calculate($this->request());

        // Fabricating a second route would invent a choice the customer does not
        // have. The module reports its alternative test as NOT APPLICABLE
        // instead.
        $this->assertCount(1, $result->options);
    }

    public function test_the_development_provider_answers_no_route_for_one_place(): void
    {
        $result = (new DevelopmentRouteProvider(isProduction: false))->calculate(new RouteRequest(
            originLatitude: 28.5494,
            originLongitude: 77.2001,
            destinationLatitude: 28.5494,
            destinationLongitude: 77.2001,
        ));

        $this->assertTrue($result->isEmpty());
    }
}
