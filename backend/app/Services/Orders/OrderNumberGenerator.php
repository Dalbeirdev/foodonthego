<?php

declare(strict_types=1);

namespace App\Services\Orders;

use App\Exceptions\Orders\OrderNumberGenerationFailed;
use App\Models\Order;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\Date;

/**
 * The number a customer reads out at a counter.
 *
 * NOT A CREDENTIAL. Knowing an order number must never be enough to collect
 * food; that is what the pickup code and token are for. This is allowed to be
 * short, memorable and quotable over a bad phone line precisely because it
 * authorises nothing.
 *
 * NOT THE DATABASE ID EITHER. A sequential public number tells anyone holding
 * one roughly how many orders the platform has ever taken, and lets them guess
 * their neighbours' — which matters more than it sounds, because a guessable
 * identifier turns every ownership check into the only thing standing between
 * a stranger and somebody's dinner.
 */
final class OrderNumberGenerator
{
    /**
     * Base-32 without I, L, O or U.
     *
     * I/1, O/0 and L/1 are the pairs people mishear and mistype; U is dropped
     * so no random draw can spell something a customer has to say out loud in
     * a restaurant.
     */
    private const ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

    private const SUFFIX_LENGTH = 10;

    /**
     * Five candidates before giving up.
     *
     * With 32^10 (≈ 2^50) suffixes inside a single day's prefix, a collision is
     * not something that happens; the retry exists so that if it ever does, the
     * result is one more draw rather than a failed order for a customer whose
     * money has already been taken.
     */
    private const MAX_ATTEMPTS = 5;

    /** @var callable(int): int */
    private $randomInt;

    /**
     * @param  (callable(int): int)|null  $randomInt  Injectable so a test can force
     *                                                the collision that will otherwise
     *                                                never occur. Production always
     *                                                uses random_int, which is CSPRNG-
     *                                                backed; mt_rand and uniqid are not
     *                                                and must never appear here.
     */
    public function __construct(?callable $randomInt = null)
    {
        $this->randomInt = $randomInt ?? static fn (int $max): int => random_int(0, $max);
    }

    /**
     * A number no order currently holds.
     *
     * The existence check is an optimisation, not the guarantee — two workers
     * can both find a candidate free and then both try to write it. The unique
     * index on orders.order_number is what actually guarantees uniqueness, and
     * the creation path retries when it fires. Anything that reads this method
     * as "now safe to insert without handling a duplicate" has misread it.
     */
    public function mint(?CarbonImmutable $now = null): string
    {
        $now ??= Date::now()->toImmutable();

        for ($attempt = 1; $attempt <= self::MAX_ATTEMPTS; $attempt++) {
            $candidate = $this->candidate($now);

            if (! Order::query()->where('order_number', $candidate)->exists()) {
                return $candidate;
            }
        }

        throw new OrderNumberGenerationFailed(self::MAX_ATTEMPTS);
    }

    /**
     * FOTG-YYMMDD-XXXXXXXXXX.
     *
     * The date is there for humans reading a support ticket, not for
     * uniqueness — it narrows nothing an attacker did not already know, since
     * they are holding an order placed that day.
     */
    public function candidate(CarbonImmutable $now): string
    {
        $suffix = '';
        $last = strlen(self::ALPHABET) - 1;

        for ($i = 0; $i < self::SUFFIX_LENGTH; $i++) {
            $suffix .= self::ALPHABET[($this->randomInt)($last)];
        }

        return sprintf('FOTG-%s-%s', $now->format('ymd'), $suffix);
    }
}
