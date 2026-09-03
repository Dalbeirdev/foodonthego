<?php

declare(strict_types=1);

namespace Tests\Feature\Api;

use App\Enums\ApiErrorCode;
use Illuminate\Support\Facades\RateLimiter;
use Tests\TestCase;

final class RateLimitTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        RateLimiter::clear('ip:127.0.0.1');
    }

    public function test_the_public_limit_is_advertised_on_every_throttled_response(): void
    {
        $response = $this->getJson('/api/v1/meta');

        $response->assertOk()
            ->assertHeader('X-RateLimit-Limit', (string) config('foodonthego.rate_limits.public'));
    }

    public function test_exceeding_the_limit_returns_the_documented_error_contract(): void
    {
        config(['foodonthego.rate_limits.public' => 3]);

        for ($i = 0; $i < 3; $i++) {
            $this->getJson('/api/v1/meta')->assertOk();
        }

        $this->getJson('/api/v1/meta')
            ->assertStatus(429)
            ->assertJsonPath('error.code', ApiErrorCode::RateLimited->value)
            ->assertJsonStructure(['error' => ['code', 'message', 'request_id']]);
    }

    public function test_health_checks_are_exempt_from_throttling(): void
    {
        config(['foodonthego.rate_limits.public' => 2]);

        // Well past the limit; liveness must keep answering or an orchestrator will
        // kill instances that are perfectly healthy.
        for ($i = 0; $i < 12; $i++) {
            $this->getJson('/api/v1/health/live')->assertOk();
        }
    }
}
