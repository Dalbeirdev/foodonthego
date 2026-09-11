<?php

declare(strict_types=1);

namespace Tests\Feature\Api;

use Tests\TestCase;

final class HealthTest extends TestCase
{
    public function test_liveness_reports_alive_without_touching_dependencies(): void
    {
        $response = $this->getJson('/api/v1/health/live');

        $response->assertOk()
            ->assertJsonPath('data.status', 'alive')
            ->assertJsonPath('data.service', 'foodonthego-api')
            ->assertJsonPath('data.version', 'v1');
    }

    public function test_readiness_checks_mysql_and_redis(): void
    {
        $response = $this->getJson('/api/v1/health/ready');

        $response->assertOk()
            ->assertJsonPath('data.status', 'ready')
            ->assertJsonPath('data.checks.database.healthy', true)
            ->assertJsonPath('data.checks.redis.healthy', true);
    }

    public function test_liveness_is_not_rate_limited(): void
    {
        // An orchestrator polls this far more often than the public limit allows;
        // throttling it would turn a healthy instance into a restart loop.
        $response = $this->getJson('/api/v1/health/live');

        $this->assertFalse($response->headers->has('X-RateLimit-Limit'));
    }

    public function test_health_never_leaks_connection_details(): void
    {
        $body = $this->getJson('/api/v1/health/ready')->getContent();

        foreach (['password', config('database.connections.mysql.username'), '3306'] as $secret) {
            $this->assertStringNotContainsString((string) $secret, (string) $body);
        }
    }
}
