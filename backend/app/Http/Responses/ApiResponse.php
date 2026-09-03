<?php

declare(strict_types=1);

namespace App\Http\Responses;

use App\Enums\ApiErrorCode;
use App\Support\RequestContext;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Http\JsonResponse;

/**
 * The one place an API response is shaped. Every successful body is
 *
 *   { "data": ..., "meta": { "request_id": "...", ... } }
 *
 * and every failure is
 *
 *   { "error": { "code", "message", "details"?, "request_id" } }
 *
 * so a client can tell success from failure by key presence alone, without
 * consulting the status code, and can always quote a request_id to support.
 * See docs/05-api-standards.md.
 */
final class ApiResponse
{
    /**
     * @param  array<string, mixed>  $meta
     */
    public static function ok(mixed $data, array $meta = [], int $status = 200): JsonResponse
    {
        return response()->json([
            'data' => $data,
            'meta' => array_merge(['request_id' => RequestContext::id()], $meta),
        ], $status);
    }

    public static function created(mixed $data): JsonResponse
    {
        return self::ok($data, [], 201);
    }

    public static function noContent(): JsonResponse
    {
        return response()->json(null, 204);
    }

    /**
     * A page of results. `meta.pagination` is a fixed shape across every endpoint
     * that pages, so a client's list component is written once.
     *
     * @param  array<int, mixed>  $items
     */
    public static function paginated(array $items, LengthAwarePaginator $paginator): JsonResponse
    {
        return self::ok($items, [
            'pagination' => [
                'total' => $paginator->total(),
                'per_page' => $paginator->perPage(),
                'current_page' => $paginator->currentPage(),
                'last_page' => $paginator->lastPage(),
                'has_more' => $paginator->hasMorePages(),
            ],
        ]);
    }

    /**
     * @param  array<string, mixed>|null  $details
     */
    public static function error(
        ApiErrorCode $code,
        string $message,
        ?array $details = null,
        ?int $status = null,
    ): JsonResponse {
        $body = [
            'error' => [
                'code' => $code->value,
                'message' => $message,
                'request_id' => RequestContext::id(),
            ],
        ];

        if ($details !== null && $details !== []) {
            $body['error']['details'] = $details;
        }

        return response()->json($body, $status ?? $code->httpStatus());
    }
}
