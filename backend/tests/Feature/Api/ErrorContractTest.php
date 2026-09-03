<?php

declare(strict_types=1);

namespace Tests\Feature\Api;

use App\Enums\ApiErrorCode;
use App\Exceptions\ApiException;
use Illuminate\Support\Facades\Route;
use Illuminate\Validation\ValidationException;
use RuntimeException;
use Tests\TestCase;

/**
 * The error contract is the part of the API that every client branches on, so it is
 * pinned by tests rather than by documentation alone.
 */
final class ErrorContractTest extends TestCase
{
    public function test_unknown_endpoint_returns_the_documented_error_shape(): void
    {
        $response = $this->getJson('/api/v1/there-is-nothing-here');

        $response->assertNotFound()
            ->assertJsonStructure(['error' => ['code', 'message', 'request_id']])
            ->assertJsonPath('error.code', ApiErrorCode::NotFound->value);
    }

    public function test_wrong_method_is_reported_as_method_not_allowed(): void
    {
        $this->postJson('/api/v1/health/live')
            ->assertStatus(405)
            ->assertJsonPath('error.code', ApiErrorCode::MethodNotAllowed->value);
    }

    public function test_validation_failure_lists_every_offending_field(): void
    {
        Route::middleware('api')->post('/api/v1/_test/validate', function (): void {
            throw ValidationException::withMessages([
                'origin' => 'An origin is required.',
                'destination' => 'A destination is required.',
            ]);
        });

        $this->postJson('/api/v1/_test/validate')
            ->assertStatus(422)
            ->assertJsonPath('error.code', ApiErrorCode::ValidationFailed->value)
            ->assertJsonStructure(['error' => ['details' => ['fields' => ['origin', 'destination']]]]);
    }

    public function test_business_rule_violation_carries_its_details(): void
    {
        Route::middleware('api')->get('/api/v1/_test/business', function (): void {
            throw ApiException::businessRule('The restaurant is too far from the route.', ['detour_minutes' => 41]);
        });

        $this->getJson('/api/v1/_test/business')
            ->assertStatus(422)
            ->assertJsonPath('error.code', ApiErrorCode::BusinessRuleViolated->value)
            ->assertJsonPath('error.details.detour_minutes', 41);
    }

    public function test_an_unexpected_exception_is_never_described_to_the_client(): void
    {
        // The single most important assertion in this file: a bug must not tell the
        // caller what broke, where, or with which credentials.
        $this->app['config']->set('app.debug', false);

        Route::middleware('api')->get('/api/v1/_test/boom', function (): void {
            throw new RuntimeException('SQLSTATE[HY000] Access denied for user fotg@127.0.0.1 (password: hunter2)');
        });

        // Exception handling stays ON: the whole point is to assert what the
        // handler renders, not to let the exception escape into the test.
        $response = $this->getJson('/api/v1/_test/boom');

        $response->assertStatus(500)
            ->assertJsonPath('error.code', ApiErrorCode::ServerError->value);

        $body = (string) $response->getContent();
        $this->assertStringNotContainsString('hunter2', $body);
        $this->assertStringNotContainsString('SQLSTATE', $body);
        $this->assertStringNotContainsString('RuntimeException', $body);
    }

    public function test_every_error_code_maps_to_a_sensible_http_status(): void
    {
        foreach (ApiErrorCode::cases() as $code) {
            $this->assertGreaterThanOrEqual(400, $code->httpStatus(), "{$code->value} is not an error status");
            $this->assertLessThan(600, $code->httpStatus());
        }
    }
}
