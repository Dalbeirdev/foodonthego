<?php

declare(strict_types=1);

namespace Tests\Feature\Api;

use Tests\TestCase;

final class SecurityHeadersTest extends TestCase
{
    public function test_baseline_security_headers_are_present(): void
    {
        $response = $this->getJson('/api/v1/health/live');

        $expected = [
            'X-Content-Type-Options' => 'nosniff',
            'X-Frame-Options' => 'DENY',
            'Referrer-Policy' => 'no-referrer',
            'Cache-Control' => 'no-store, private',
        ];

        foreach ($expected as $header => $value) {
            $this->assertSame($value, $response->headers->get($header), "{$header} is wrong");
        }

        $this->assertStringContainsString("default-src 'none'", (string) $response->headers->get('Content-Security-Policy'));
    }

    public function test_hsts_is_not_asserted_over_plain_http(): void
    {
        // Sent in local development it would pin a developer's browser to
        // https://localhost for a year.
        $this->assertFalse(
            $this->getJson('/api/v1/health/live')->headers->has('Strict-Transport-Security'),
        );
    }

    public function test_cors_never_reflects_an_arbitrary_origin(): void
    {
        config(['cors.allowed_origins' => ['http://localhost:5173']]);

        $response = $this->getJson('/api/v1/health/live', ['Origin' => 'https://attacker.example']);

        $this->assertNotSame(
            'https://attacker.example',
            $response->headers->get('Access-Control-Allow-Origin'),
        );
    }

    public function test_an_allowed_origin_is_accepted(): void
    {
        config(['cors.allowed_origins' => ['http://localhost:5173']]);

        $this->getJson('/api/v1/health/live', ['Origin' => 'http://localhost:5173'])
            ->assertHeader('Access-Control-Allow-Origin', 'http://localhost:5173');
    }
}
