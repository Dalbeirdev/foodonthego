<?php

declare(strict_types=1);

namespace Tests\Feature\Api;

use App\Enums\ApiErrorCode;
use App\Http\Middleware\EnforceIdempotency;
use App\Http\Responses\ApiResponse;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\Route;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * The scenario this protects: a traveller on a patchy motorway connection taps
 * "place order", the response is lost, the app retries. Without idempotency they
 * are charged twice.
 */
final class IdempotencyTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();

        // A counter proves the handler ran once, not merely that two responses
        // happened to look alike.
        Route::middleware('api')->post('/api/v1/_test/create', function (): JsonResponse {
            $count = cache()->increment('_test_handler_calls') ?: 1;

            return ApiResponse::created(['handler_calls' => $count, 'nonce' => Str::random(8)]);
        });
    }

    public function test_a_retry_with_the_same_key_replays_the_first_response(): void
    {
        $headers = [EnforceIdempotency::HEADER => 'order-attempt-1'];
        $payload = ['restaurant' => 'Highway Spice Kitchen'];

        $first = $this->postJson('/api/v1/_test/create', $payload, $headers);
        $second = $this->postJson('/api/v1/_test/create', $payload, $headers);

        $first->assertCreated();
        $second->assertCreated();

        // Byte-identical body, and the handler ran only once.
        $this->assertSame($first->json('data.nonce'), $second->json('data.nonce'));
        $this->assertSame(1, $first->json('data.handler_calls'));
        $this->assertSame('true', $second->headers->get('Idempotency-Replayed'));
    }

    public function test_the_same_key_with_a_different_body_is_rejected_not_replayed(): void
    {
        $headers = [EnforceIdempotency::HEADER => 'order-attempt-2'];

        $this->postJson('/api/v1/_test/create', ['total' => 100], $headers)->assertCreated();

        // Serving the old response here would hide a client bug and could charge the
        // wrong amount; refusing makes the mistake visible.
        $this->postJson('/api/v1/_test/create', ['total' => 999], $headers)
            ->assertStatus(409)
            ->assertJsonPath('error.code', ApiErrorCode::IdempotencyKeyReused->value);
    }

    public function test_different_keys_are_independent_requests(): void
    {
        $payload = ['total' => 100];

        $first = $this->postJson('/api/v1/_test/create', $payload, [EnforceIdempotency::HEADER => 'key-a']);
        $second = $this->postJson('/api/v1/_test/create', $payload, [EnforceIdempotency::HEADER => 'key-b']);

        $this->assertNotSame($first->json('data.nonce'), $second->json('data.nonce'));
    }

    public function test_a_request_without_a_key_is_never_deduplicated(): void
    {
        $payload = ['total' => 100];

        $first = $this->postJson('/api/v1/_test/create', $payload);
        $second = $this->postJson('/api/v1/_test/create', $payload);

        $this->assertNotSame($first->json('data.nonce'), $second->json('data.nonce'));
    }

    public function test_a_safe_method_is_left_alone(): void
    {
        Route::middleware('api')->get('/api/v1/_test/read', fn () => ApiResponse::ok(['nonce' => Str::random(8)]));

        $headers = [EnforceIdempotency::HEADER => 'read-key'];
        $first = $this->getJson('/api/v1/_test/read', $headers);
        $second = $this->getJson('/api/v1/_test/read', $headers);

        $this->assertNotSame($first->json('data.nonce'), $second->json('data.nonce'));
    }

    public function test_an_oversized_key_is_rejected(): void
    {
        $this->postJson('/api/v1/_test/create', [], [EnforceIdempotency::HEADER => str_repeat('k', 300)])
            ->assertStatus(422)
            ->assertJsonPath('error.code', ApiErrorCode::ValidationFailed->value);
    }
}
