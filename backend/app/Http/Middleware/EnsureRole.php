<?php

declare(strict_types=1);

namespace App\Http\Middleware;

use App\Enums\ApiErrorCode;
use App\Exceptions\ApiException;
use App\Models\User;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Restricts a route to a fixed set of roles.
 *
 * Authentication answers "who is this"; this answers "does that kind of account
 * belong here at all". The two are separate on purpose: a valid customer token is
 * a perfectly good credential and still has no business reaching a restaurant's
 * order queue or the admin panel. Without this, every future controller would have
 * to remember to check the role itself, and one that forgets is a privilege
 * escalation rather than a bug.
 *
 * Token abilities (Sanctum's `abilities` middleware) are the second half of the
 * pair and answer a different question — what this *particular* token may do. A
 * route that matters uses both: the role gates the account, the ability gates the
 * credential.
 *
 * Usage: ->middleware('role:restaurant_owner,restaurant_manager')
 */
final class EnsureRole
{
    public function handle(Request $request, Closure $next, string ...$roles): Response
    {
        $user = $request->user();

        // Should be unreachable — 'role' is only ever chained after 'auth:sanctum'.
        // Reporting 401 rather than 403 keeps the contract honest if it is not.
        if (! $user instanceof User) {
            throw new ApiException(
                ApiErrorCode::Unauthenticated,
                'Authentication is required to access this resource.',
            );
        }

        if (! in_array($user->role->value, $roles, true)) {
            throw new ApiException(
                ApiErrorCode::Forbidden,
                'This account does not have access to that area of FoodOnTheGo.',
            );
        }

        return $next($request);
    }
}
