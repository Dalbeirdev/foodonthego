<?php

declare(strict_types=1);

namespace Tests\Feature\Api\Customer;

use App\Logging\StructuredLogger;
use App\Models\Trip;
use App\Models\User;
use App\Services\Places\PlaceProvider;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Log;
use Tests\Support\CustomerFactory;
use Tests\TestCase;

/**
 * Where somebody is travelling from and to is the most sensitive thing this
 * module holds, and a place search is close behind: what a person types into a
 * search box is a statement about where they are going.
 *
 * This reads what the application actually wrote to disk during a full round of
 * trip and place operations, rather than asserting on a redaction helper. The
 * risk is not a missed key — it is a call site that logged the whole payload
 * because it was convenient at the time.
 */
final class TripLoggingTest extends TestCase
{
    use RefreshDatabase;

    private const BASE = '/api/v1/customer/trips';

    private User $rahul;

    private User $ananya;

    private string $token;

    private string $logFile;

    protected function setUp(): void
    {
        parent::setUp();

        $this->rahul = CustomerFactory::rahul();
        $this->ananya = CustomerFactory::ananya();
        $this->token = CustomerFactory::tokenFor($this->rahul);

        $this->logFile = storage_path('logs/testing-trip-'.getmypid().'.log');
        @unlink($this->logFile);

        config([
            'logging.default' => 'testing-trip',
            'logging.channels.testing-trip' => [
                'driver' => 'single',
                'path' => $this->logFile,
                'level' => 'debug',
                'tap' => [StructuredLogger::class],
            ],
        ]);

        Log::forgetChannel('testing-trip');
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

    /** Searches, creates, discards, and attempts one trip belonging to Ananya. */
    private function runAFullRound(): string
    {
        $this->asRahul()->getJson('/api/v1/customer/places/search?q=Jaipur+International+Airport')
            ->assertOk();

        $id = $this->asRahul()->postJson(self::BASE, [
            'origin' => [
                'source_type' => 'CURRENT_LOCATION',
                'display_name' => 'Current location',
                'formatted_address' => 'Green Park, New Delhi, Delhi 110016',
                'latitude' => 28.5590,
                'longitude' => 77.2070,
                'city' => 'New Delhi',
            ],
            'destination' => [
                'source_type' => 'PLACE_SEARCH',
                'place_id' => 'dev:jaipur-airport',
                'display_name' => 'Jaipur International Airport',
                'formatted_address' => 'Airport Road, Sanganer, Jaipur, Rajasthan 302029',
                'latitude' => 26.8242,
                'longitude' => 75.8122,
                'city' => 'Jaipur',
            ],
        ])->assertCreated()->json('data.id');

        $this->asRahul()->postJson(self::BASE.'/'.$id.'/discard')->assertOk();

        $hers = Trip::factory()->ownedBy($this->ananya)->create([
            'origin_city' => 'Gurugram',
            'destination_city' => 'Chandigarh',
        ]);

        $this->asRahul()->getJson(self::BASE.'/'.$hers->uuid)->assertNotFound();

        return $this->log();
    }

    public function test_no_place_a_customer_chose_reaches_the_log(): void
    {
        $log = $this->runAFullRound();

        foreach ([
            'Green Park',
            'Jaipur International Airport',
            'Airport Road',
            'Sanganer',
            'Gurugram',
            'Chandigarh',
        ] as $place) {
            $this->assertStringNotContainsString($place, $log);
        }
    }

    public function test_no_coordinate_reaches_the_log(): void
    {
        $log = $this->runAFullRound();

        // Where somebody set off from is as sensitive as where they live, and a
        // coordinate is more precise than an address.
        foreach (['28.5590', '77.2070', '26.8242', '75.8122'] as $coordinate) {
            $this->assertStringNotContainsString($coordinate, $log);
        }
    }

    public function test_no_search_query_reaches_the_log(): void
    {
        $this->runAFullRound();

        // What a person types into a search box is a statement about where they
        // are going, whether or not they ever create the trip.
        $this->assertStringNotContainsString('q=Jaipur', $this->log());
    }

    public function test_the_lifecycle_is_logged_by_record_and_actor(): void
    {
        $log = $this->runAFullRound();

        foreach (['trip.created', 'trip.discarded', 'trip.access_denied'] as $event) {
            $this->assertStringContainsString($event, $log);
        }

        $this->assertStringContainsString($this->rahul->uuid, $log);
        $this->assertStringContainsString('trip_uuid', $log);
    }

    public function test_a_creation_records_the_source_of_each_end_but_not_the_place(): void
    {
        $log = $this->runAFullRound();

        $line = $this->firstLineContaining($log, 'trip.created');

        // Useful operationally — which of the three ways of choosing a place
        // people actually use — and it says nothing about where.
        $this->assertStringContainsString('CURRENT_LOCATION', $line);
        $this->assertStringContainsString('PLACE_SEARCH', $line);
        $this->assertStringContainsString('NOT_CALCULATED', $line);
        $this->assertStringNotContainsString('Jaipur', $line);
    }

    public function test_a_denied_access_records_the_attempt_without_the_target(): void
    {
        $log = $this->runAFullRound();

        $line = $this->firstLineContaining($log, 'trip.access_denied');

        $this->assertStringContainsString($this->rahul->uuid, $line);
        $this->assertStringNotContainsString('Gurugram', $line);
    }

    public function test_a_provider_failure_is_logged_without_the_query_or_the_key(): void
    {
        $this->app->instance(PlaceProvider::class, new FailingPlaceProvider);

        $this->asRahul()->getJson('/api/v1/customer/places/search?q=Jaipur')->assertStatus(503);

        $log = $this->log();

        $this->assertStringContainsString('places.lookup_failed', $log);
        $this->assertStringNotContainsString('Jaipur', $log);
        $this->assertStringNotContainsString('AIza', $log);
    }

    public function test_no_full_phone_number_reaches_the_log(): void
    {
        $log = $this->runAFullRound();

        $this->assertStringNotContainsString('+919999900101', $log);
        $this->assertStringNotContainsString('+919999900102', $log);
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
