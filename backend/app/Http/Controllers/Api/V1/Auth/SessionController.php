<?php

declare(strict_types=1);

namespace App\Http\Controllers\Api\V1\Auth;

use App\Http\Responses\ApiResponse;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Laravel\Sanctum\PersonalAccessToken;

final class SessionController
{
    /** The signed-in customer's own profile. */
    public function me(Request $request): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();

        return ApiResponse::ok($user->toCustomerProfile());
    }

    /**
     * Signs out by revoking the token that made this request.
     *
     * Only the current token — signing out on a phone must not sign the customer
     * out of a tablet they left at home. Multi-device session management is a
     * later module; the shape is already here because each token is a row.
     */
    public function logout(Request $request): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();

        $token = $user->currentAccessToken();
        if ($token instanceof PersonalAccessToken) {
            $token->delete();

            Log::info('auth.logout', [
                'user_uuid' => $user->uuid,
                'token_id' => $token->getKey(),
            ]);
        }

        return ApiResponse::noContent();
    }
}
