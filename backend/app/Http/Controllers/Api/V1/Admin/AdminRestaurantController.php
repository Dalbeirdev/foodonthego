<?php

declare(strict_types=1);

namespace App\Http\Controllers\Api\V1\Admin;

use App\Http\Responses\ApiResponse;
use App\Models\Restaurant;
use App\Models\User;
use App\Services\Tenancy\TenantAccessService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * What a platform account may reach across tenants.
 *
 * The route exists to prove one specific thing: **a super administrator with no
 * grant sees nothing.** That is the assertion that separates "breadth by RBAC"
 * from "breadth by role string", and it is the one that would quietly stop being
 * true the day somebody adds a `before()` hook to a policy.
 *
 * The same scope as the restaurant surface, deliberately. One implementation of
 * reachability, consulted by everybody.
 */
final class AdminRestaurantController
{
    public function __construct(
        private readonly TenantAccessService $access,
    ) {}

    public function index(Request $request): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();

        $restaurants = Restaurant::query()
            ->reachableBy($user)
            ->orderBy('name')
            ->get();

        return ApiResponse::ok([
            'scope' => $this->access->hasPlatformWideGrant($user) ? 'all' : 'granted',
            'restaurants' => $restaurants->map(fn (Restaurant $r): array => [
                'id' => $r->uuid,
                'name' => $r->name,
                'city' => $r->city,
                'capability' => $this->access->capabilityFor($user, $r)?->value,
            ])->all(),
        ]);
    }
}
