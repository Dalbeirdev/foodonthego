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
    private function format(array $context): string
    {
        return (new StructuredFormatter)->format(new LogRecord(
            new \DateTimeImmutable,
            'testing',
            Level::Info,
            'api.request',
            $context,
        ));
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
