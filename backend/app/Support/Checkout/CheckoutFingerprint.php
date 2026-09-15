<?php

declare(strict_types=1);

namespace App\Support\Checkout;

use App\Models\Cart;
use App\Support\Pickup\PlanningFingerprint;
use App\Support\Trip\EndpointFingerprint;

/**
 * A deterministic fingerprint of everything a price was quoted against.
 *
 * The third of these in the project, after
 * {@see EndpointFingerprint} and
 * {@see PlanningFingerprint}, and it follows the same rule:
 * a promise is only meaningful alongside the facts that produced it.
 *
 * A quote says "this basket, at this time, from this kitchen, costs this". Move
 * any of those and the sentence is no longer true, whatever the stored total
 * says.
 *
 * The commercial rule version is the part worth pointing at. Without it a
 * pricing change would be invisible here — the cart, the restaurant and the
 * pickup would all be untouched — and a customer could hold a quote across a
 * tax change and pay yesterday's figure.
 *
 * Compared, never parsed.
 */
final class CheckoutFingerprint
{
    public static function of(Cart $cart): string
    {
        $restaurant = $cart->restaurant;
        $route = $cart->trip?->selectedRoute;

        return self::fromParts(
            customerUuid: (string) $cart->customer?->uuid,
            cartUuid: (string) $cart->uuid,
            cartVersion: (int) $cart->version,
            tripUuid: (string) $cart->trip?->uuid,
            restaurantUuid: (string) $restaurant?->uuid,
            restaurantStatus: $restaurant?->status?->value,
            isAcceptingOrders: (bool) $restaurant?->is_accepting_orders,
            routeUuid: $route?->uuid,
            routeCalculatedAt: $route?->calculated_at?->toIso8601String(),
            // The pickup window AND the fingerprint Module 13 took over the
            // facts behind it. The window alone would survive a restaurant
            // editing its hours around it.
            pickupStartAt: $cart->requested_pickup_start_at?->toIso8601String(),
            pickupEndAt: $cart->requested_pickup_end_at?->toIso8601String(),
            pickupFingerprint: (string) ($cart->pickup_planning_fingerprint ?? ''),
            currency: (string) $cart->currency,
            commercialRuleVersion: (int) config('foodonthego.checkout.commercial_rule_version'),
        );
    }

    public static function fromParts(
        string $customerUuid,
        string $cartUuid,
        int $cartVersion,
        string $tripUuid,
        string $restaurantUuid,
        ?string $restaurantStatus,
        bool $isAcceptingOrders,
        ?string $routeUuid,
        ?string $routeCalculatedAt,
        ?string $pickupStartAt,
        ?string $pickupEndAt,
        string $pickupFingerprint,
        string $currency,
        int $commercialRuleVersion,
    ): string {
        return hash('sha256', implode('|', [
            'checkout-v1',
            $customerUuid,
            $cartUuid,
            (string) $cartVersion,
            $tripUuid,
            $restaurantUuid,
            $restaurantStatus ?? '',
            $isAcceptingOrders ? '1' : '0',
            $routeUuid ?? '',
            $routeCalculatedAt ?? '',
            $pickupStartAt ?? '',
            $pickupEndAt ?? '',
            $pickupFingerprint,
            $currency,
            'rules:'.$commercialRuleVersion,
        ]));
    }
}
