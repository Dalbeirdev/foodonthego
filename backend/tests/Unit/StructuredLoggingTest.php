<?php

declare(strict_types=1);

namespace Tests\Unit;

use App\Logging\StructuredFormatter;
use App\Support\RequestContext;
use Monolog\Level;
use Monolog\LogRecord;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\TestCase;

/**
 * Redaction is the security control here, so it is tested as one: the assertion is
 * not "the key is masked" but "this secret value appears nowhere in the line".
 */
final class StructuredLoggingTest extends TestCase
{
    protected function tearDown(): void
    {
        RequestContext::reset();
        parent::tearDown();
    }

    /** @param array<string, mixed> $context */
    private function format(array $context, string $message = 'api.request'): string
    {
        return (new StructuredFormatter)->format(new LogRecord(
            new \DateTimeImmutable,
            'testing',
            Level::Info,
            $message,
            $context,
        ));
    }

    public function test_a_duplicate_key_error_never_names_the_duplicated_value(): void
    {
        // Found by grepping a real application log during Module 07's privacy
        // sweep. A unique-constraint violation puts the offending value into the
        // driver's message, and for `users_phone_e164_unique` that value is a
        // customer's phone number — written to disk, twice, by two different
        // reporting paths.
        $line = $this->format([], 'SQLSTATE[23000]: Integrity constraint violation: 1062 '
            ."Duplicate entry '+919999900101' for key 'users.users_phone_e164_unique'");

        $this->assertStringNotContainsString('+919999900101', $line);

        // The constraint name survives: it is the operationally useful half, and
        // it says nothing about anybody.
        $this->assertStringContainsString('users_phone_e164_unique', $line);
    }

    public function test_the_bound_values_laravel_appends_never_reach_the_line(): void
    {
        // The broader half of the same defect, and the one that made the first
        // fix insufficient: Laravel appends the whole statement to *every*
        // QueryException message with the bindings **inlined and unquoted**, so
        // there is nothing narrower to match than the tail itself.
        $line = $this->format([], 'SQLSTATE[HY000]: General error: 1364 '
            ."Field 'uuid' doesn't have a default value "
            .'(Connection: mysql, Host: 127.0.0.1, Database: fotg, '
            .'SQL: insert into `users` (`phone_e164`, `name`) '
            .'values (+919999900101, Rahul Sharma))');

        $this->assertStringNotContainsString('+919999900101', $line);
        $this->assertStringNotContainsString('Rahul Sharma', $line);

        // What is left is the part an engineer can act on.
        $this->assertStringContainsString('1364', $line);
        $this->assertStringContainsString('uuid', $line);
    }

    public function test_a_throwable_in_context_is_reduced_to_three_facts(): void
    {
        // `json_encode` serialises a throwable through its **public**
        // properties, and `PDOException::$errorInfo` is public and carries the
        // offending value. The exception object never reaches the encoder now.
        $line = $this->format([
            'exception' => new \RuntimeException('a message that may carry a value'),
        ]);

        $this->assertStringContainsString('RuntimeException', $line);
        $this->assertStringContainsString('"line"', $line);
        $this->assertStringNotContainsString('a message that may carry a value', $line);
    }

    public function test_a_driver_value_inside_a_context_string_is_scrubbed_too(): void
    {
        $line = $this->format([
            'exception_message' => "Duplicate entry 'rahul@example.test' for key 'users.users_email_unique'",
        ]);

        $this->assertStringNotContainsString('rahul@example.test', $line);
    }

    public function test_an_ordinary_message_is_left_alone(): void
    {
        $line = $this->format(['note' => 'Green Park to Jaipur'], 'trip.created');

        $this->assertStringContainsString('trip.created', $line);
        $this->assertStringContainsString('Green Park to Jaipur', $line);
    }

    public function test_a_line_is_valid_json_with_the_expected_envelope(): void
    {
        RequestContext::set('11111111-1111-4111-8111-111111111111');

        $decoded = json_decode($this->format(['status' => 200]), true, 512, JSON_THROW_ON_ERROR);

        $this->assertSame('api.request', $decoded['message']);
        $this->assertSame('INFO', $decoded['level']);
        $this->assertSame('11111111-1111-4111-8111-111111111111', $decoded['request_id']);
        $this->assertSame(200, $decoded['context']['status']);
    }

    #[DataProvider('sensitiveKeys')]
    public function test_a_sensitive_value_never_reaches_the_line(string $key): void
    {
        $line = $this->format([$key => 'super-secret-value-9000']);

        $this->assertStringNotContainsString('super-secret-value-9000', $line);
        $this->assertStringContainsString('[REDACTED]', $line);
    }

    /** @return array<string, array{string}> */
    public static function sensitiveKeys(): array
    {
        return [
            'password' => ['password'],
            'mixed case' => ['Password'],
            'authorization header' => ['authorization'],
            'bearer token' => ['access_token'],
            'otp' => ['otp_code'],
            'card number' => ['card_number'],
            'cvv' => ['cvv'],
            'api key' => ['api_key'],
            'private key' => ['private_key'],
            'session id' => ['session_id'],
            'webhook signature' => ['signature'],
        ];
    }

    public function test_redaction_reaches_nested_values(): void
    {
        $line = $this->format([
            'payment' => ['method' => 'card', 'card_number' => '4111111111111111'],
        ]);

        $this->assertStringNotContainsString('4111111111111111', $line);
    }

    public function test_a_non_sensitive_value_is_kept_so_logs_stay_useful(): void
    {
        $line = $this->format(['route' => 'api/v1/orders/{order}', 'duration_ms' => 12.5]);

        $this->assertStringContainsString('api/v1/orders/{order}', $line);
        $this->assertStringContainsString('12.5', $line);
    }

    public function test_deep_nesting_is_truncated_rather_than_overflowing_the_stack(): void
    {
        $deep = ['leaf' => 'value'];
        for ($i = 0; $i < 40; $i++) {
            $deep = ['nested' => $deep];
        }

        $line = $this->format($deep);
        $this->assertStringContainsString('[TRUNCATED]', $line);
        $this->assertJson(trim($line));
    }
}
