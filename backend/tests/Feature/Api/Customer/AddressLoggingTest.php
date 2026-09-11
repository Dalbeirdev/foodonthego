<?php

declare(strict_types=1);

namespace Tests\Feature\Api\Customer;

use App\Logging\StructuredLogger;
use App\Models\CustomerAddress;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Log;
use Tests\Support\CustomerFactory;
use Tests\TestCase;

/**
 * Addresses are personal location data. This reads what the application actually
 * wrote to disk during a full round of profile and address operations.
 *
 * Asserting on a redaction helper is not enough here, because the risk is not a
 * missed key — it is a call site that logs a whole payload because it was
 * convenient.
 */
final class AddressLoggingTest extends TestCase
{
    use RefreshDatabase;

    private const BASE = '/api/v1/customer/addresses';

    private User $rahul;

    private string $token;

    private string $logFile;

    protected function setUp(): void
    {
        parent::setUp();

        $this->rahul = CustomerFactory::rahul();
        $this->token = CustomerFactory::tokenFor($this->rahul);

        $this->logFile = storage_path('logs/testing-address-'.getmypid().'.log');
        @unlink($this->logFile);

        config([
            'logging.default' => 'testing-address',
            'logging.channels.testing-address' => [
                'driver' => 'single',
                'path' => $this->logFile,
                'level' => 'debug',
                'tap' => [StructuredLogger::class],
            ],
        ]);

        Log::forgetChannel('testing-address');
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

    private function runAFullRound(): string
    {
        $id = $this->asRahul()->postJson(self::BASE, [
            'type' => 'HOME',
            'address_line_1' => '12 Green Park Road',
            'address_line_2' => 'Green Park',
            'landmark' => 'Near Green Park Metro',
            'city' => 'New Delhi',
            'state' => 'Delhi',
            'postal_code' => '110016',
            'country_code' => 'IN',
        ])->assertCreated()->json('data.id');

        $this->asRahul()->patchJson(self::BASE.'/'.$id, ['landmark' => 'Opposite the park'])->assertOk();

        // A second address so the default can actually move. Re-defaulting the
        // one that is already default is a deliberate no-op and writes nothing,
        // so a round built on it would not exercise the audit line at all.
        $workId = $this->asRahul()->postJson(self::BASE, [
            'type' => 'WORK',
            'address_line_1' => 'Connaught Place',
            'city' => 'New Delhi',
            'state' => 'Delhi',
            'postal_code' => '110001',
            'country_code' => 'IN',
        ])->assertCreated()->json('data.id');

        $this->asRahul()->postJson(self::BASE.'/'.$workId.'/default')->assertOk();
        $this->asRahul()->postJson(self::BASE.'/'.$id.'/default')->assertOk();
        $this->asRahul()->patchJson('/api/v1/customer/profile', [
            'first_name' => 'Rahul',
            'email' => 'rahul.updated@foodonthego.example',
        ])->assertOk();
        $this->asRahul()->deleteJson(self::BASE.'/'.$id)->assertNoContent();

        return $id;
    }

    public function test_a_full_round_of_operations_writes_no_address_and_no_email(): void
    {
        $this->runAFullRound();
        $log = $this->log();

        $this->assertNotSame('', $log, 'Nothing was logged, so this would pass vacuously.');

        foreach ([
            '12 Green Park Road',
            'Green Park Metro',
            '110016',
            'Connaught Place',
            'rahul.updated@foodonthego.example',
            '+919999900101',
        ] as $personal) {
            $this->assertStringNotContainsString(
                $personal,
                $log,
                "Personal data reached the log: {$personal}",
            );
        }
    }

    public function test_the_operations_themselves_are_recorded(): void
    {
        $this->runAFullRound();
        $log = $this->log();

        // Operationally useful without being a copy of somebody's life: what
        // happened, to which record, by which actor.
        foreach ([
            'address.created',
            'address.updated',
            'address.default_changed',
            'address.deleted',
            'profile.updated',
        ] as $event) {
            $this->assertStringContainsString($event, $log, "Missing audit event: {$event}");
        }
    }

    public function test_records_are_identified_by_uuid_and_actor_not_by_content(): void
    {
        $id = $this->runAFullRound();

        $this->assertStringContainsString($id, $this->log());
        $this->assertStringContainsString($this->rahul->uuid, $this->log());
    }

    public function test_a_profile_update_logs_field_names_and_not_values(): void
    {
        $this->asRahul()->patchJson('/api/v1/customer/profile', [
            'first_name' => 'Rahulunique',
            'email' => 'very.unique.address@foodonthego.example',
        ])->assertOk();

        $log = $this->log();

        $this->assertStringContainsString('"fields"', $log);
        $this->assertStringNotContainsString('Rahulunique', $log);
        $this->assertStringNotContainsString('very.unique.address', $log);
    }

    public function test_a_denied_access_attempt_is_recorded(): void
    {
        $ananya = CustomerFactory::ananya();
        $hers = CustomerAddress::factory()->create([
            'customer_id' => $ananya->getKey(),
        ]);

        $this->asRahul()->getJson(self::BASE.'/'.$hers->uuid)->assertStatus(404);

        // An attempt to reach somebody else's record is exactly the thing an
        // investigation needs to see.
        $this->assertStringContainsString('address.access_denied', $this->log());
    }

    public function test_every_line_is_parseable_json_with_a_correlation_id(): void
    {
        $this->runAFullRound();

        foreach (array_filter(explode("\n", $this->log())) as $line) {
            $decoded = json_decode($line, true);

            $this->assertIsArray($decoded, "Not JSON: {$line}");
            $this->assertArrayHasKey('request_id', $decoded);
        }
    }
}
