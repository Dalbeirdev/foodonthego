<?php

declare(strict_types=1);

namespace Tests\Feature\Api\Customer;

use App\Logging\StructuredLogger;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Log;
use Tests\Support\CustomerFactory;
use Tests\Support\RestaurantFixtures;
use Tests\TestCase;

/**
 * What a discovery request writes to disk.
 *
 * A route is a description of where somebody will be. A *discovery* is that plus
 * where they intend to stop and roughly when, which is worse. So this reads the
 * log file the application actually wrote rather than asserting on a redaction
 * helper: the risk is not a missed key, it is a call site that logged the whole
 * result because it was convenient at the time.
 */
final class DiscoveryLoggingTest extends TestCase
{
    use RefreshDatabase;

    private User $rahul;

    private string $token;

    private string $logFile;

    protected function setUp(): void
    {
        parent::setUp();

        Cache::flush();

        $this->rahul = CustomerFactory::rahul();
        $this->token = CustomerFactory::tokenFor($this->rahul);

        $this->logFile = storage_path('logs/testing-discovery-'.getmypid().'.log');
        @unlink($this->logFile);

        config([
            'logging.default' => 'testing-discovery',
            'logging.channels.testing-discovery' => [
                'driver' => 'single',
                'path' => $this->logFile,
                'level' => 'debug',
                'tap' => [StructuredLogger::class],
            ],
        ]);

        Log::forgetChannel('testing-discovery');
    }

    protected function tearDown(): void
    {
        @unlink($this->logFile);

        parent::tearDown();
    }

    private function log(): string
    {
        return is_file($this->logFile) ? (string) file_get_contents($this->logFile) : '';
    }

    private function runADiscovery(): string
    {
        $trip = RestaurantFixtures::tripWithSelectedRoute($this->rahul);

        RestaurantFixtures::nearRoute(0.4, 800, 'Highway Spice Kitchen');
        RestaurantFixtures::nearRoute(0.6, 2_400, 'Rajasthan Highway Bites');

        $this->withHeader('Authorization', 'Bearer '.$this->token)
            ->getJson("/api/v1/customer/trips/{$trip->uuid}/restaurants")
            ->assertOk();

        return $this->log();
    }

    public function test_the_search_is_logged_by_counts_not_by_places(): void
    {
        $log = $this->runADiscovery();

        $this->assertStringContainsString('discovery.completed', $log);
        $this->assertStringContainsString('candidates', $log);
        $this->assertStringContainsString('detour_evaluated', $log);
    }

    public function test_no_restaurant_a_customer_was_shown_reaches_the_log(): void
    {
        $log = $this->runADiscovery();

        // Which restaurants somebody was offered is a statement about their
        // journey, not an operational fact about ours.
        $this->assertStringNotContainsString('Highway Spice Kitchen', $log);
        $this->assertStringNotContainsString('Rajasthan Highway Bites', $log);
    }

    public function test_no_coordinate_or_geometry_reaches_the_log(): void
    {
        $log = $this->runADiscovery();

        foreach (['28.5590', '77.2070', '26.8242', '75.8122'] as $coordinate) {
            $this->assertStringNotContainsString($coordinate, $log);
        }

        $this->assertStringNotContainsString('encoded_polyline', $log);
        $this->assertStringNotContainsString('_p~', $log);
    }

    public function test_the_line_carries_the_record_and_the_actor(): void
    {
        $log = $this->runADiscovery();

        $line = $this->firstLineContaining($log, 'discovery.completed');

        // Enough to answer "who searched what, and how long did it take" in an
        // incident, and nothing more.
        $this->assertStringContainsString('trip_uuid', $line);
        $this->assertStringContainsString('route_uuid', $line);
        $this->assertStringContainsString('duration_ms', $line);
        $this->assertStringNotContainsString('Highway', $line);
    }

    public function test_no_full_phone_number_reaches_the_log(): void
    {
        $log = $this->runADiscovery();

        // The restaurant owner's, as well as the customer's.
        $this->assertStringNotContainsString('+919999900101', $log);
        $this->assertStringNotContainsString('+919812345678', $log);
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
