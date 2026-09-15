<?php

declare(strict_types=1);

namespace Tests\Feature\Api;

use App\Http\Middleware\AssignRequestId;
use PHPUnit\Framework\Attributes\DataProvider;
use Tests\TestCase;

final class RequestIdTest extends TestCase
{
    public function test_a_request_id_is_generated_and_echoed(): void
    {
        $response = $this->getJson('/api/v1/health/live');

        $header = $response->headers->get(AssignRequestId::HEADER);
        $this->assertNotNull($header);
        // The id in the body and the id in the header must be the same value, or a
        // user quoting one cannot be found by the other.
        $response->assertJsonPath('meta.request_id', $header);
    }

    public function test_a_valid_inbound_request_id_is_honoured_so_traces_survive(): void
    {
        $incoming = '3f2504e0-4f89-41d3-9a0c-0305e82c3301';

        $this->getJson('/api/v1/health/live', [AssignRequestId::HEADER => $incoming])
            ->assertJsonPath('meta.request_id', $incoming);
    }

    #[DataProvider('hostileRequestIds')]
    public function test_a_forged_request_id_is_replaced_rather_than_trusted(string $hostile): void
    {
        $response = $this->getJson('/api/v1/health/live', [AssignRequestId::HEADER => $hostile]);

        $issued = (string) $response->headers->get(AssignRequestId::HEADER);
        $this->assertNotSame($hostile, $issued);
        $this->assertMatchesRegularExpression(
            '/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i',
            $issued,
        );
    }

    /** @return array<string, array{string}> */
    public static function hostileRequestIds(): array
    {
        return [
            'log injection' => ["abc\n{\"level\":\"ERROR\",\"message\":\"forged\"}"],
            'not a uuid' => ['../../etc/passwd'],
            'empty' => [''],
            'oversized' => [str_repeat('a', 5000)],
        ];
    }

    public function test_an_error_response_also_carries_the_request_id(): void
    {
        $response = $this->getJson('/api/v1/nope');

        $this->assertSame(
            $response->headers->get(AssignRequestId::HEADER),
            $response->json('error.request_id'),
        );
    }
}
