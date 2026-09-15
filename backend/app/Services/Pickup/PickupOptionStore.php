<?php

declare(strict_types=1);

namespace App\Services\Pickup;

use App\Models\Cart;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\Cache;

/**
 * The short-lived menu of pickup times a customer could choose.
 *
 * **The client never sends a time.** It sends an option id, and the server
 * looks up what that id meant. That is the whole security design of this
 * endpoint pair, and it is worth stating why it is not a signed timestamp: a
 * signed payload still has to be verified correctly on every path, and the day
 * one path forgets, a customer can name their own pickup time. An opaque id
 * that resolves to a server-written record has nothing in it to tamper with.
 *
 * So there is no base64 JSON timing payload here, nothing the customer can
 * edit, and no arithmetic performed on anything a request supplied.
 *
 * The cache store is the home for these because they are meant to lapse.
 * Redis in deployment, reached through the Cache facade so that tests run
 * against the array store without a second code path. MySQL stays
 * authoritative for what the customer actually chose; this holds only what
 * they *could* choose, for the next few minutes.
 */
final class PickupOptionStore
{
    /**
     * Keys are scoped to the customer, which is what makes one customer using
     * another's option id structurally impossible rather than merely checked.
     * Ananya's id, presented by Rahul, is looked for under Rahul's prefix and
     * is simply not there — no branch to get wrong, no comparison to forget.
     *
     * The record it resolves to still carries the customer, and
     * {@see PickupOptionSelectionService} still checks it. Two mechanisms for
     * one guarantee, because this is the one the spec names as mandatory.
     */
    private function key(string $customerUuid, string $token): string
    {
        return 'pickup:option:'.$customerUuid.':'.$token;
    }

    /**
     * Writes the plan's windows and hands back their ids, in the plan's order.
     *
     * @return list<string>
     */
    public function put(Cart $cart, PickupPlan $plan): array
    {
        $customerUuid = (string) $cart->customer?->uuid;
        $ttl = max(1, (int) config('foodonthego.pickup.option_ttl_seconds'));

        $ids = [];

        foreach ($plan->windows as $window) {
            // 256 bits from the CSPRNG. Not guessable, not enumerable, and
            // carrying no structure at all — no index, no cart id, nothing a
            // reader could learn from or a writer could shift.
            $token = bin2hex(random_bytes(32));

            Cache::put(
                $this->key($customerUuid, $token),
                [
                    'customer_uuid' => $customerUuid,
                    'cart_uuid' => (string) $cart->uuid,
                    'trip_uuid' => (string) $cart->trip?->uuid,
                    'restaurant_uuid' => (string) $cart->restaurant?->uuid,
                    'start_at' => $window->startAt->toIso8601String(),
                    'end_at' => $window->endAt->toIso8601String(),
                    'timezone' => $plan->timezone,
                    'fingerprint' => $plan->fingerprint,
                    'planning_version' => (int) config('foodonthego.pickup.planning_version'),
                    'issued_at' => $plan->serverNow->toIso8601String(),
                ],
                $ttl,
            );

            $ids[] = $token;
        }

        return $ids;
    }

    /**
     * What an id meant, or null.
     *
     * Null covers expired, never-existed, and belonging to somebody else, and
     * the caller must not tell those apart in a response. Distinguishing them
     * would answer "does this id exist" for anyone who asked, and the only
     * person who asks is somebody trying ids.
     */
    public function find(string $customerUuid, string $token): ?PickupOptionRecord
    {
        if (! $this->looksLikeToken($token)) {
            // **Hygiene, not the defence.** What actually refuses a bad id is
            // the lookup below missing — a cache key is a literal string to
            // both Redis and the array store, so a `*` or a `../` in it selects
            // nothing rather than everything.
            //
            // This is here to bound what reaches the driver at all: an id is 64
            // hex characters, and a client that sends a megabyte of anything
            // else should not have it turned into a cache key to find that out.
            return null;
        }

        $raw = Cache::get($this->key($customerUuid, $token));

        if (! is_array($raw)) {
            return null;
        }

        return new PickupOptionRecord(
            token: $token,
            customerUuid: (string) ($raw['customer_uuid'] ?? ''),
            cartUuid: (string) ($raw['cart_uuid'] ?? ''),
            tripUuid: (string) ($raw['trip_uuid'] ?? ''),
            restaurantUuid: (string) ($raw['restaurant_uuid'] ?? ''),
            startAt: CarbonImmutable::parse((string) $raw['start_at']),
            endAt: CarbonImmutable::parse((string) $raw['end_at']),
            timezone: (string) ($raw['timezone'] ?? ''),
            fingerprint: (string) ($raw['fingerprint'] ?? ''),
            planningVersion: (int) ($raw['planning_version'] ?? 0),
        );
    }

    /**
     * Retires an id once it has been used.
     *
     * A selection is not a purchase and re-selecting the same time is harmless,
     * so this is housekeeping rather than a defence. It exists so that an id
     * which has done its job does not sit in the store for another ten minutes
     * waiting to be replayed against a cart that has moved on since.
     */
    public function forget(string $customerUuid, string $token): void
    {
        if ($this->looksLikeToken($token)) {
            Cache::forget($this->key($customerUuid, $token));
        }
    }

    private function looksLikeToken(string $token): bool
    {
        return strlen($token) === 64 && ctype_xdigit($token);
    }
}
