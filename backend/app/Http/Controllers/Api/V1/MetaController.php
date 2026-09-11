<?php

declare(strict_types=1);

namespace App\Http\Controllers\Api\V1;

use App\Enums\ApiErrorCode;
use App\Enums\Role;
use App\Http\Responses\ApiResponse;
use Illuminate\Http\JsonResponse;

/**
 * Machine-readable description of the API's own conventions.
 *
 * It exists so the roles and error codes a client branches on come from the server
 * rather than from a constant copied into three codebases and left to drift. The
 * React shells and the Flutter app all read this.
 */
final class MetaController
{
    public function __invoke(): JsonResponse
    {
        return ApiResponse::ok([
            'service' => 'foodonthego-api',
            'api_version' => config('foodonthego.api.current_version'),
            'supported_versions' => config('foodonthego.api.supported_versions'),
            'roles' => array_map(
                static fn (Role $role): array => [
                    'value' => $role->value,
                    'label' => $role->label(),
                    'surface' => $role->surface(),
                ],
                Role::cases(),
            ),
            'error_codes' => array_map(
                static fn (ApiErrorCode $code): array => [
                    'code' => $code->value,
                    'http_status' => $code->httpStatus(),
                ],
                ApiErrorCode::cases(),
            ),
        ]);
    }
}
