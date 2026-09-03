<?php

declare(strict_types=1);

namespace App\Exceptions;

use App\Enums\ApiErrorCode;
use App\Http\Responses\ApiResponse;
use Illuminate\Auth\Access\AuthorizationException;
use Illuminate\Auth\AuthenticationException;
use Illuminate\Database\Eloquent\ModelNotFoundException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Validation\ValidationException;
use Symfony\Component\HttpKernel\Exception\HttpExceptionInterface;
use Symfony\Component\HttpKernel\Exception\MethodNotAllowedHttpException;
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;
use Symfony\Component\HttpKernel\Exception\TooManyRequestsHttpException;
use Throwable;

/**
 * Turns every throwable into the single documented error contract.
 *
 * The rule that matters: a 5xx never describes itself. Message, class, file, line
 * and stack trace go to the log (with the correlation id the client was given); the
 * client gets a fixed sentence and that id. Leaking an exception message is how a
 * database DSN, a file path or a query ends up in a bug report — and, in debug
 * mode, it is deliberate; in any other environment it is a disclosure.
 */
final class ApiExceptionRenderer
{
    public function render(Throwable $e, Request $request): ?JsonResponse
    {
        // Web routes (none yet) keep Laravel's default HTML behaviour.
        if (! $request->is('api/*') && ! $request->expectsJson()) {
            return null;
        }

        return match (true) {
            $e instanceof ApiException => ApiResponse::error($e->errorCode, $e->getMessage(), $e->details),

            $e instanceof ValidationException => ApiResponse::error(
                ApiErrorCode::ValidationFailed,
                'The submitted data is not valid.',
                ['fields' => $e->errors()],
            ),

            $e instanceof AuthenticationException => ApiResponse::error(
                ApiErrorCode::Unauthenticated,
                'Authentication is required to access this resource.',
            ),

            $e instanceof AuthorizationException => ApiResponse::error(
                ApiErrorCode::Forbidden,
                'You are not allowed to perform this action.',
            ),

            // A missing model is reported the same way as a missing route, and
            // deliberately does not name the model class: "App\Models\Restaurant not
            // found" tells an unauthenticated caller what our schema looks like.
            $e instanceof ModelNotFoundException,
            $e instanceof NotFoundHttpException => ApiResponse::error(
                ApiErrorCode::NotFound,
                'The requested resource does not exist.',
            ),

            $e instanceof MethodNotAllowedHttpException => ApiResponse::error(
                ApiErrorCode::MethodNotAllowed,
                'That HTTP method is not supported for this endpoint.',
            ),

            $e instanceof TooManyRequestsHttpException => ApiResponse::error(
                ApiErrorCode::RateLimited,
                'Too many requests. Please slow down and try again shortly.',
            ),

            default => $this->renderUnexpected($e, $request),
        };
    }

    private function renderUnexpected(Throwable $e, Request $request): JsonResponse
    {
        if ($e instanceof HttpExceptionInterface && $e->getStatusCode() < 500) {
            return ApiResponse::error(
                ApiErrorCode::BusinessRuleViolated,
                $e->getMessage() !== '' ? $e->getMessage() : 'The request could not be processed.',
                null,
                $e->getStatusCode(),
            );
        }

        Log::error('api.unhandled_exception', [
            'exception' => $e::class,
            'exception_message' => $e->getMessage(),
            'file' => $e->getFile(),
            'line' => $e->getLine(),
            'route' => $request->route()?->uri() ?? $request->path(),
            'trace' => collect($e->getTrace())->take(15)->all(),
        ]);

        return ApiResponse::error(
            ApiErrorCode::ServerError,
            'Something went wrong on our side. Quote the request_id when contacting support.',
        );
    }
}
