<?php

declare(strict_types=1);

namespace Tests\Feature\Api\Customer;

use App\Logging\StructuredLogger;
use App\Models\Trip;
use App\Models\User;
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Log;
use Tests\Support\CustomerFactory;
use Tests\TestCase;

/**
 * Where somebody is travelling from, to, and when is the most sensitive thing
 * this module holds — more so than a saved address, because it is a *movement*
 * and it is in the future.
 *
 * This reads what the application actually wrote to disk during a full round of
 * journey operations, rather than asserting on a redaction helper: the risk is
 * not a missed key, it is a call site that logged the whole payload because it
 * was convenient at the time.
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

    /** Plans, edits and cancels a journey, and attempts one against Ananya's. */
    private function runAFullRound(): string
    {
        $id = $this->asRahul()->postJson(self::BASE, [
            'origin' => [
                'label' => 'Home',
                'address_line' => '12 Green Park Road',
                'city' => 'New Delhi',
                'state' => 'Delhi',
                'country_code' => 'IN',
            ],
            'destination' => [
                'label' => "Parents' House",
                'address_line' => '8 Civil Lines',
                'city' => 'Jaipur',
                'state' => 'Rajasthan',
                'country_code' => 'IN',
            ],
            'departure_at' => CarbonImmutable::now()->addDay()->toIso8601String(),
            'note' => 'Collecting medicines on the way',
        ])->assertCreated()->json('data.id');

        $this->asRahul()->patchJson(self::BASE.'/'.$id, [
            'destination' => [
                'label' => 'Udaipur',
                'address_line' => '4 Lake Road',
                'city' => 'Udaipur',
                'state' => 'Rajasthan',
                'country_code' => 'IN',
            ],
            'traveller_count' => 2,
        ])->assertOk();

        $this->asRahul()->postJson(self::BASE.'/'.$id.'/cancel', [
            'reason' => 'Train booked instead',
        ])->assertOk();

        $ananyasTrip = Trip::factory()->ownedBy($this->ananya)->create([
            'origin_city' => 'Gurugram',
            'destination_city' => 'Chandigarh',
        ]);

        $this->asRahul()->getJson(self::BASE.'/'.$ananyasTrip->uuid)->assertNotFound();

        return $this->log();
    }

    public function test_no_journey_address_reaches_the_log(): void
    {
        $log = $this->runAFullRound();

        foreach ([
            '12 Green Park Road',
            '8 Civil Lines',
            '4 Lake Road',
            'Jaipur',
            'Udaipur',
            'Gurugram',
            'Chandigarh',
        ] as $location) {
            $this->assertStringNotContainsString($location, $log);
        }
    }

    public function test_no_free_text_the_customer_wrote_reaches_the_log(): void
    {
        $log = $this->runAFullRound();

        // A note and a cancellation reason are whatever somebody typed. "Visiting
        // the hospital on Tuesday" is a health disclosure, and an operational log
        // is not where it belongs.
        $this->assertStringNotContainsString('Collecting medicines on the way', $log);
        $this->assertStringNotContainsString('Train booked instead', $log);
    }

    public function test_no_departure_or_arrival_time_reaches_the_log(): void
    {
        $log = $this->runAFullRound();

        $departure = Trip::query()->where('customer_id', $this->rahul->getKey())->firstOrFail()->departure_at;
        $this->assertNotNull($departure);

        // When somebody's home is empty is exactly as sensitive as where it is.
        $this->assertStringNotContainsString($departure->toIso8601String(), $log);
        $this->assertStringNotContainsString($departure->format('Y-m-d H:i:s'), $log);
    }

    public function test_the_lifecycle_is_logged_by_record_and_actor(): void
    {
        $log = $this->runAFullRound();

        foreach (['trip.created', 'trip.updated', 'trip.cancelled', 'trip.access_denied'] as $event) {
            $this->assertStringContainsString($event, $log);
        }

        // Identified by uuid and actor uuid — enough to answer "who changed what"
        // in an incident, and nothing more.
        $this->assertStringContainsString($this->rahul->uuid, $log);
        $this->assertStringContainsString('trip_uuid', $log);
    }

    public function test_an_update_logs_field_names_not_values(): void
    {
        $log = $this->runAFullRound();

        $updateLines = array_values(array_filter(
            explode("\n", $log),
            static fn (string $line): bool => str_contains($line, 'trip.updated'),
        ));

        $this->assertNotEmpty($updateLines);

        $line = $updateLines[0];

        // The eight destination_* columns collapse to one name, so the log says
        // "the destination changed" without saying to where.
        $this->assertStringContainsString('"destination"', $line);
        $this->assertStringContainsString('traveller_count', $line);
        $this->assertStringNotContainsString('destination_city', $line);
        $this->assertStringNotContainsString('Udaipur', $line);
    }

    public function test_a_denied_access_records_the_attempt_without_the_target(): void
    {
        $log = $this->runAFullRound();

        $deniedLines = array_values(array_filter(
            explode("\n", $log),
            static fn (string $line): bool => str_contains($line, 'trip.access_denied'),
        ));

        $this->assertCount(1, $deniedLines);

        // Who tried and which id — not what the journey was, which the attacker
        // is not entitled to and which the log would then hold forever.
        $this->assertStringContainsString($this->rahul->uuid, $deniedLines[0]);
        $this->assertStringNotContainsString('Gurugram', $deniedLines[0]);
    }

    public function test_no_full_phone_number_reaches_the_log(): void
    {
        $log = $this->runAFullRound();

        $this->assertStringNotContainsString('+919999900101', $log);
        $this->assertStringNotContainsString('+919999900102', $log);
    }
}
