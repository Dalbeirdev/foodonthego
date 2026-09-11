<?php

declare(strict_types=1);

namespace Tests\Feature\Api\Customer;

use App\Logging\StructuredLogger;
use App\Models\Trip;
use App\Models\User;
use App\Services\Routing\RouteCalculationService;
use App\Services\Routing\RouteFailureKind;
use App\Services\Routing\RouteProvider;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Log;
use Tests\Support\CustomerFactory;
use Tests\TestCase;
use Tests\Unit\RecordingRouteProvider;

/**
 * A route is the most revealing thing this application stores.
 *
 * An address says where somebody lives. A route says where they will be, when,
 * by which road, and — read across a few of them — what their week looks like.
 * None of it belongs in an operational log.
 *
 * This reads what the application actually wrote to disk during a full round of
 * route operations, rather than asserting on a redaction helper. The risk is not
 * a missed key; it is a call site that logged the whole provider payload because
 * it was convenient at the time.
 */
final class RouteLoggingTest extends TestCase
{
    use RefreshDatabase;

    private User $rahul;

    private string $token;

    private string $logFile;

    private RecordingRouteProvider $provider;

    protected function setUp(): void
    {
        parent::setUp();

        $this->rahul = CustomerFactory::rahul();
        $this->token = CustomerFactory::tokenFor($this->rahul);

        $this->provider = new RecordingRouteProvider(alternatives: 2);
        $this->app->instance(RouteProvider::class, $this->provider);
        $this->app->forgetInstance(RouteCalculationService::class);

        $this->logFile = storage_path('logs/testing-route-'.getmypid().'.log');
        @unlink($this->logFile);

        config([
            'logging.default' => 'testing-route',
            'logging.channels.testing-route' => [
                'driver' => 'single',
                'path' => $this->logFile,
                'level' => 'debug',
                'tap' => [StructuredLogger::class],
            ],
        ]);

        Log::forgetChannel('testing-route');
    }

    protected function tearDown(): void
    {
        @unlink($this->logFile);

        parent::tearDown();
    }

    private function asRahul(): self
    {
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', 'Bearer '.$this->token);
    }

    private function log(): string
    {
        return is_file($this->logFile) ? (string) file_get_contents($this->logFile) : '';
    }

    private function runAFullRound(): Trip
    {
        $trip = Trip::factory()->ownedBy($this->rahul)->create();
        $url = "/api/v1/customer/trips/{$trip->uuid}";

        $this->asRahul()->postJson("{$url}/route/calculate")->assertOk();

        $routes = $this->asRahul()->getJson("{$url}/routes")->json('data.routes');
        $this->asRahul()->postJson("{$url}/routes/{$routes[1]['route_id']}/select")->assertOk();

        return $trip->refresh();
    }

    public function test_no_route_geometry_reaches_the_log(): void
    {
        $trip = $this->runAFullRound();
        $polyline = $trip->routes()->first()->encoded_polyline;

        // Geometry is the whole journey, point by point. Logging it would put a
        // customer's movements in a file that gets shipped to a log aggregator.
        $this->assertStringNotContainsString($polyline, $this->log());
        $this->assertStringNotContainsString(substr($polyline, 0, 24), $this->log());
    }

    public function test_no_place_and_no_coordinate_reaches_the_log(): void
    {
        $this->runAFullRound();
        $log = $this->log();

        foreach ([
            'Hauz Khas', 'Jaipur', 'Sanganer', 'Rajasthan',
            '28.5494', '77.2001', '26.8242', '75.8122',
        ] as $needle) {
            $this->assertStringNotContainsString($needle, $log);
        }
    }

    public function test_no_distance_or_duration_reaches_the_log(): void
    {
        $this->runAFullRound();

        // Where somebody is going is inferable from how far and how long.
        $this->assertStringNotContainsString('278000', $this->log());
        $this->assertStringNotContainsString('16200', $this->log());
    }

    public function test_the_lifecycle_is_logged_by_record_and_actor(): void
    {
        $trip = $this->runAFullRound();
        $log = $this->log();

        $this->assertStringContainsString('route.calculated', $log);
        $this->assertStringContainsString($trip->uuid, $log);
        $this->assertStringContainsString('recording', $log);
    }

    public function test_a_calculation_records_how_many_routes_and_whether_traffic_came_back(): void
    {
        $this->runAFullRound();

        $line = $this->firstLineContaining($this->log(), 'route.calculated');

        // Operationally useful — the alternative count and whether the traffic
        // model answered — and it says nothing about where anybody is going.
        $this->assertStringContainsString('route_count', $line);
        $this->assertStringContainsString('has_traffic', $line);
        $this->assertStringContainsString('latency_ms', $line);
    }

    public function test_a_provider_failure_is_logged_without_its_message(): void
    {
        $this->provider->failWith = RouteFailureKind::RateLimited;
        $trip = Trip::factory()->ownedBy($this->rahul)->create();

        $this->asRahul()->postJson("/api/v1/customer/trips/{$trip->uuid}/route/calculate")
            ->assertStatus(429);

        $log = $this->log();

        $this->assertStringContainsString('route.calculation_failed', $log);
        $this->assertStringContainsString('rate_limited', $log);
        // The provider's own words name our project, our key state and our quota.
        $this->assertStringNotContainsString('AIza', $log);
        $this->assertStringNotContainsString('fotg-123', $log);
        $this->assertStringNotContainsString('quota exceeded', $log);
    }

    public function test_a_no_route_answer_is_logged_as_its_own_event(): void
    {
        $this->provider->findsNothing = true;
        $trip = Trip::factory()->ownedBy($this->rahul)->create();

        $this->asRahul()->postJson("/api/v1/customer/trips/{$trip->uuid}/route/calculate")
            ->assertStatus(422);

        // Distinguished from a failure, because the operational response is
        // different: a rising no-route rate is a data problem, not an outage.
        $this->assertStringContainsString('route.no_route', $this->log());
    }

    private function firstLineContaining(string $log, string $needle): string
    {
        foreach (explode("\n", $log) as $line) {
            if (str_contains($line, $needle)) {
                return $line;
            }
        }

        $this->fail("no log line contained \"{$needle}\"");
    }
}
