<?php

declare(strict_types=1);

namespace App\Services\Pickup;

use App\Models\Cart;
use App\Models\CartItem;
use Illuminate\Support\Facades\Log;

/**
 * How long this cart takes to cook.
 *
 * Two decisions here shape every pickup window the platform offers, and both
 * are deliberate rather than convenient.
 *
 * **The cart's requirement is the MAXIMUM of its lines, not the sum.** A kitchen
 * cooks several dishes at once. Summing them would tell a customer their
 * two-dish order needs forty minutes when the pass has it ready in
 * twenty-five, and would push every recommendation later than it needs to be.
 *
 * **Quantity does not multiply anything.** Three portions of a fifteen-minute
 * dish is fifteen minutes. A tandoor holds more than one skewer, and V1 holds
 * no evidence about where any kitchen's batch size actually runs out. Inventing
 * a multiplier would be inventing a number, so quantity does not enter this
 * calculation at all — and this paragraph exists so that its absence reads as a
 * decision rather than an oversight. When real batching data exists, it belongs
 * here.
 *
 * Modifiers do not affect preparation either, for a simpler reason: there is no
 * preparation column on a modifier option. Guessing that extra cheese adds five
 * minutes would be fabrication.
 */
final class PreparationEstimateService
{
    /**
     * Precedence, first present wins:
     *
     *   1. the chosen variant's own preparation time
     *   2. the menu item's
     *   3. the restaurant's default
     *   4. the platform fallback
     *
     * **Never zero as a silent default.** A missing preparation time is missing
     * data, not a dish that cooks instantly, and treating it as nought would
     * quietly offer customers pickup windows no kitchen can meet.
     */
    public function forCart(Cart $cart): PreparationEstimate
    {
        $restaurantDefault = $cart->restaurant?->default_preparation_minutes;
        $platformFallback = (int) config('foodonthego.pickup.fallback_prep_minutes');

        $lines = [];
        $usedPlatformFallback = false;

        foreach ($cart->items as $item) {
            [$minutes, $source] = $this->forLine($item, $restaurantDefault, $platformFallback);

            if ($source === 'platform_fallback') {
                $usedPlatformFallback = true;
            }

            $lines[] = [
                'line' => (string) $item->uuid,
                'minutes' => $minutes,
                'source' => $source,
            ];
        }

        if ($lines === []) {
            return new PreparationEstimate(0, [], false);
        }

        if ($usedPlatformFallback) {
            // Logged every time, because a menu that reaches this is a menu
            // somebody has not finished setting up, and the symptom a customer
            // sees — a pickup time that feels wrong — points nowhere useful on
            // its own.
            Log::warning('pickup.preparation_platform_fallback', [
                'cart_uuid' => $cart->uuid,
                'restaurant_uuid' => $cart->restaurant?->uuid,
                'lines' => array_values(array_filter(
                    $lines,
                    static fn (array $l): bool => $l['source'] === 'platform_fallback',
                )),
            ]);
        }

        return new PreparationEstimate(
            minutes: max(array_column($lines, 'minutes')),
            lines: $lines,
            usedPlatformFallback: $usedPlatformFallback,
        );
    }

    /**
     * @return array{0: int, 1: string}
     */
    private function forLine(CartItem $item, ?int $restaurantDefault, int $platformFallback): array
    {
        // A variant may legitimately take longer than its dish — a family
        // portion is not a single portion in a bigger box — and where the
        // operator has said so, that is the authoritative figure.
        if ($this->usable($item->variant?->preparation_minutes)) {
            return [(int) $item->variant->preparation_minutes, 'variant'];
        }

        if ($this->usable($item->menuItem?->preparation_minutes)) {
            return [(int) $item->menuItem->preparation_minutes, 'item'];
        }

        if ($this->usable($restaurantDefault)) {
            return [(int) $restaurantDefault, 'restaurant_default'];
        }

        return [$platformFallback, 'platform_fallback'];
    }

    /**
     * Zero and null are both "not set".
     *
     * A legacy row carrying 0 is far more likely to mean nobody filled it in
     * than to mean a dish that materialises instantly, and reading it as the
     * latter would be the one mistake that silently under-promises to a real
     * kitchen.
     */
    private function usable(?int $minutes): bool
    {
        return $minutes !== null && $minutes > 0;
    }
}
