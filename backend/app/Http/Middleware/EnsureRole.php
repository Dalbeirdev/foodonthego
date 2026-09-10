<?php

declare(strict_types=1);

namespace App\Http\Middleware;

use App\Enums\ApiErrorCode;
use App\Exceptions\ApiException;
use App\Models\User;
use App\Services\Auth\CustomerAuthService;
use App\Services\Tenancy\TenantAccessService;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Is this the kind of account that belongs on this surface, and is it usable?
 *
 * TWO QUESTIONS, ONE GATE, AND DELIBERATELY SO. Every authenticated route group
 * in routes/api.php carries `role:` — customer, restaurant, admin — which makes
 * this the one place every authenticated request already passes through. A
 * separate `active` middleware would be a second thing to remember on the next
 * route group somebody adds, and the one they forget is the one that matters.
 *
 * WHY THE STANDING CHECK IS HERE RATHER THAN AT SIGN-IN ALONE.
 * {@see CustomerAuthService::issueSession()} refuses to mint a
 * token for an account that cannot authenticate, which stops a suspended person
 * signing in. It does nothing about the account suspended *after* signing in —
 * and that is the case suspension exists for. A Sanctum token is a bearer
 * credential sitting on a handset; nothing can reach into the handset and take
 * it back, so the refusal has to happen when the token is presented. Until it
 * did, a suspended customer kept full access for the token's remaining lifetime,
 * up to 30 days (`foodonthego.auth.token_ttl_seconds`), and by Module 16 that
 * access included placing orders and paying for them.
 *
 * FREE, WHICH IS WHY IT NEED NOT BE TRADED OFF. The stated reason for leaving
 * this open was the cost of a per-request status check. There is no cost:
 * `auth:sanctum` has already loaded the user row to resolve the token, so the
 * columns are in memory and this adds no query. Measured, not assumed — see the
 * known-issues entry.
 *
 * It does not replace revoking tokens on suspension. That belongs with the admin
 * module and is the thing that makes the credential stop existing rather than
 * merely stop being served.
 */
final class EnsureRole
{
    public function handle(Request $request, Closure $next, string ...$roles): Response
    {
        $user = $request->user();

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

        $this->refuseUnlessUsable($user);

        return $next($request);
    }

    /**
     * Both columns, because they mean different things and are reached for by
     * different people. `status` is the account's standing; `is_active` is the
     * switch. An operator who flips either one expects the account to stop
     * working and does not know which this codebase considers authoritative.
     *
     * The same rule as {@see TenantAccessService} applies
     * it, spelled the same way on purpose — one rule about whether an account is
     * usable, not two that can drift. `is_active` is compared against false
     * rather than true so that only an explicit false denies.
     *
     * 403 and not 401: the caller proved who they are. They are not allowed.
     * The message is the one the sign-in path already gives, so a customer who
     * is suspended mid-session reads the same sentence as one suspended between
     * sessions.
     *
     * @throws ApiException
     */
    private function refuseUnlessUsable(User $user): void
    {
        if ($user->status->canAuthenticate() && $user->is_active !== false) {
            return;
        }

        $code = $user->status->canAuthenticate()
            // Standing is fine; the switch is off. Reported as disabled, which
            // is what it is.
            ? ApiErrorCode::AccountDisabled
            : $user->status->blockedErrorCode();

        throw new ApiException(
            $code,
            $code === ApiErrorCode::AccountSuspended
                ? 'Your account is currently unavailable. Please contact support.'
                : 'This account is no longer active. Please contact support.',
        );
    }
}
