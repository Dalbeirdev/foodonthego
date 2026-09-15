<?php

declare(strict_types=1);

namespace App\Services\Orders;

use App\Exceptions\Orders\PickupCredentialUnavailable;
use App\Exceptions\Orders\PickupCredentialVersionMissing;
use App\Models\Order;

/**
 * The two things that authorise collecting food.
 *
 * A pickup credential is authentication material, not a reference number. The
 * threats it has to survive are guessing, brute force at the counter, leakage
 * through logs and screenshots, replay against a different order, replay at a
 * different restaurant, and a stolen database.
 *
 * -------------------------------------------------------------------------
 * THE STORAGE DESIGN, CHOSEN DELIBERATELY
 * -------------------------------------------------------------------------
 *
 * The specification requires a customer to be able to see their pickup code
 * again after the confirmation screen — on a new device, after a reinstall,
 * three hours later at the counter. That rules out storing only a one-way
 * digest, because nothing could ever render the code again. The three ways out
 * are encryption at rest, deterministic re-derivation, or handing the customer
 * the only copy. This code takes the second.
 *
 *   Both credentials are DERIVED, not stored:
 *
 *       code  = base32( HMAC-SHA256(pepper, "pickup-code:v{n}:{uuid}:{rid}") )
 *       token = base64url( HMAC-SHA256(pepper, "pickup-token:v{n}:{uuid}:{rid}") )
 *
 * Nothing secret is written to the database. A stolen dump yields no codes at
 * all, which is strictly better than encrypted-at-rest — there is no ciphertext
 * to attack later when the algorithm ages. Re-derivation is free, so a customer
 * can be shown their code as many times as they ask.
 *
 * What IS stored is an HMAC of each derived value, for two jobs neither of
 * which requires the plaintext: Module 21 verifies a presented credential by
 * indexed lookup rather than by scanning the table, and the unique index on
 * pickup_token_hash makes a collision a write error instead of two orders that
 * open the same door.
 *
 * THE TRADE, STATED. The pepper is now the single secret. Compromise it and
 * every credential in the system is derivable — the same exposure an
 * encryption key carries, moved to a value that never touches the database
 * server and can be rotated one order at a time by bumping
 * pickup_credential_version.
 *
 * -------------------------------------------------------------------------
 * WHY THE ORDER AND RESTAURANT ARE IN THE INPUT
 * -------------------------------------------------------------------------
 *
 * Binding is not decoration. A credential derived without the order uuid would
 * be the same string for every order sharing a version, and a credential
 * derived without the restaurant id could be presented at a different branch of
 * the same chain. Both identifiers are inside the HMAC, so a token is
 * arithmetically incapable of validating anywhere but the order and tenant it
 * was minted for — a property Module 21 gets for free rather than having to
 * remember to check.
 */
final class PickupCredentialService
{
    /**
     * Base-32 without I, L, O or U — the same alphabet as the order number, and
     * for the same reason: this gets read aloud in a noisy restaurant.
     */
    private const ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

    /**
     * Eight characters, 32^8 ≈ 2^40 possibilities.
     *
     * That is NOT enough on its own and is not claimed to be. A short code that
     * a human can say is inherently guessable given unlimited attempts, so the
     * security argument depends on Module 21 rate-limiting verification per
     * order, per restaurant and per device, and on the code being bound to one
     * order. Documented in docs/07-security.md so nobody later mistakes 2^40
     * for a sufficient secret.
     */
    private const CODE_LENGTH = 8;

    /**
     * 256 bits, well past the 128 the specification asks for.
     *
     * The QR token carries no such usability constraint — nobody reads it out —
     * so there is no reason to spend any entropy at all on being short.
     */
    private const TOKEN_BYTES = 32;

    public function __construct(private readonly string $pepper) {}

    /**
     * The plaintext credentials for an order, derived fresh every time.
     *
     * Deterministic: the same order at the same credential version always
     * yields the same pair, which is what lets a customer see their code again
     * without anything sensitive being stored.
     */
    public function derive(Order $order): PickupCredential
    {
        if ($this->pepper === '') {
            throw new PickupCredentialUnavailable;
        }

        return new PickupCredential(
            code: $this->code($order),
            token: $this->token($order),
            version: $this->version($order),
        );
    }

    /**
     * The credential version, or a loud failure.
     *
     * THIS GUARD EXISTS BECAUSE THE SILENT VERSION OF IT SHIPPED A REAL BUG.
     *
     * `pickup_credential_version` has a database default of 1, so a model that
     * has been round-tripped reads 1. A model that has only been save()d — never
     * reloaded — holds NULL for it, because Eloquent does not fetch defaults
     * back after an insert. `(int) null` is 0, and 0 is a perfectly usable HMAC
     * input, so the old code cheerfully derived a *different* credential for the
     * same order depending on whether anybody had reloaded it.
     *
     * The customer-visible form of that is the worst kind: the confirmation
     * screen shows one code, the stored digest is of another, and the code fails
     * at the counter with no error anywhere to explain why.
     *
     * This is the second time this exact shape has appeared in this project —
     * Module 14T's accountUsable() read `is_active === true` against a model
     * holding NULL and silently denied every account. A column default that the
     * model has not seen is not a rare edge; it is what every freshly created
     * record looks like.
     */
    private function version(Order $order): int
    {
        $version = $order->pickup_credential_version;

        if (! is_numeric($version) || (int) $version < 1) {
            throw new PickupCredentialVersionMissing($order->getKey());
        }

        return (int) $version;
    }

    /**
     * What goes in the database: an HMAC of each derived value.
     *
     * Separately keyed from the derivation itself. If the stored digest were
     * simply the derivation output, the column would BE the credential and a
     * database dump would open every order.
     */
    public function digests(Order $order): PickupCredentialDigests
    {
        $credential = $this->derive($order);

        return new PickupCredentialDigests(
            codeHash: $this->digest('digest-code', $credential->code),
            tokenHash: $this->digest('digest-token', $credential->token),
        );
    }

    /**
     * Constant-time comparison of a presented credential against an order.
     *
     * Module 21 owns verification; this exists so that when it is written there
     * is one implementation to call rather than a second, subtly different
     * comparison written under deadline. hash_equals, never ===: a timing
     * oracle on an eight-character code is a real attack, not a theoretical
     * one.
     */
    public function matchesCode(Order $order, string $presented): bool
    {
        if ($presented === '' || $order->pickup_code_hash === null) {
            return false;
        }

        return hash_equals(
            (string) $order->pickup_code_hash,
            $this->digest('digest-code', strtoupper(trim($presented))),
        );
    }

    public function matchesToken(Order $order, string $presented): bool
    {
        if ($presented === '' || $order->pickup_token_hash === null) {
            return false;
        }

        return hash_equals(
            (string) $order->pickup_token_hash,
            $this->digest('digest-token', $presented),
        );
    }

    private function code(Order $order): string
    {
        $raw = hash_hmac('sha256', $this->context('pickup-code', $order), $this->pepper, true);

        $code = '';
        $last = strlen(self::ALPHABET) - 1;

        // One byte per character, reduced into the alphabet. The modulo bias
        // across 256 -> 32 is exactly zero because 32 divides 256.
        for ($i = 0; $i < self::CODE_LENGTH; $i++) {
            $code .= self::ALPHABET[ord($raw[$i]) % ($last + 1)];
        }

        return $code;
    }

    private function token(Order $order): string
    {
        $raw = hash_hmac('sha256', $this->context('pickup-token', $order), $this->pepper, true);

        return rtrim(strtr(base64_encode(substr($raw, 0, self::TOKEN_BYTES)), '+/', '-_'), '=');
    }

    /**
     * Everything a credential is bound to, in one unambiguous string.
     *
     * Colon-separated with a purpose prefix so that no two different contexts
     * can ever produce the same input by concatenation — the classic way an
     * HMAC scheme is broken without touching the hash itself.
     */
    private function context(string $purpose, Order $order): string
    {
        return implode(':', [
            $purpose,
            'v'.$this->version($order),
            (string) $order->uuid,
            (string) $order->restaurant_id,
        ]);
    }

    private function digest(string $purpose, string $value): string
    {
        return hash_hmac('sha256', $purpose.':'.$value, $this->pepper);
    }
}
