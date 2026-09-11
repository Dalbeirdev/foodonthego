<?php

declare(strict_types=1);

namespace App\Http\Controllers\Api\V1;

use App\Enums\ApiErrorCode;
use App\Http\Responses\ApiResponse;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Redis;
use Throwable;

/**
 * Two endpoints answering two different questions.
 *
 * `live` says the PHP process is up. It touches nothing else on purpose: if it
 * checked the database, a slow database would make the orchestrator kill and
 * restart healthy application containers, turning a degraded dependency into an
 * outage.
 *
 * `ready` says this instance can actually serve traffic, which means MySQL and
 * Redis both answer. A failure here takes the instance out of the load balancer
 * without restarting it.
 */
final class HealthController
{
    public function live(): JsonResponse
    {
        return ApiResponse::ok([
            'status' => 'alive',
            'service' => 'foodonthego-api',
            'version' => config('foodonthego.api.current_version'),
        ]);
    }

    public function ready(): JsonResponse
    {
        $checks = [
            'database' => $this->checkDatabase(),
            'redis' => $this->checkRedis(),
        ];

        $healthy = ! in_array(false, array_column($checks, 'healthy'), true);

        if (! $healthy) {
            return ApiResponse::error(
                ApiErrorCode::DependencyUnavailable,
                'One or more dependencies are unavailable.',
                ['checks' => $checks],
            );
        }

        return ApiResponse::ok([
            'status' => 'ready',
            'environment' => app()->environment(),
            'checks' => $checks,
        ]);
    }

    /** @return array{healthy: bool, latency_ms?: float, error?: string} */
    private function checkDatabase(): array
    {
        $startedAt = microtime(true);

        try {
            DB::connection()->select('SELECT 1');

            return ['healthy' => true, 'latency_ms' => $this->elapsed($startedAt)];
        } catch (Throwable $e) {
            // The class name, not the message: a connection exception message
            // contains the host, port and username.
            return ['healthy' => false, 'error' => class_basename($e)];
        }
    }

    /** @return array{healthy: bool, latency_ms?: float, error?: string} */
    private function checkRedis(): array
    {
        $startedAt = microtime(true);

        try {
            Redis::connection()->ping();

            return ['healthy' => true, 'latency_ms' => $this->elapsed($startedAt)];
        } catch (Throwable $e) {
            return ['healthy' => false, 'error' => class_basename($e)];
        }
    }

    private function elapsed(float $startedAt): float
    {
        return round((microtime(true) - $startedAt) * 1000, 2);
    }
}
