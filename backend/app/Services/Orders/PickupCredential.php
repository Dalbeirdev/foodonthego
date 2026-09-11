<?php

declare(strict_types=1);

namespace App\Services\Orders;

use SensitiveParameter;

/**
 * A pickup credential in the clear, on its way to exactly one customer.
 *
 * The redaction below is not decoration. `Log::info('...', ['credential' => $c])`,
 * `dd($order)`, an exception rendered with its stack arguments, or a Sentry
 * breadcrumb will all serialise an object graph without anybody deciding to log
 * a secret. The specification's rule — never log the plaintext code or token —
 * is enforced here, at the only place that can enforce it, rather than by
 * asking every future call site to remember.
 */
final readonly class PickupCredential
{
    public function __construct(
        #[SensitiveParameter]
        public string $code,
        #[SensitiveParameter]
        public string $token,
        public int $version,
    ) {}

    /**
     * What var_dump, dd, and most log serialisers actually print.
     */
    public function __debugInfo(): array
    {
        return [
            'code' => '[redacted]',
            'token' => '[redacted]',
            'version' => $this->version,
        ];
    }

    /**
     * Deliberately not the credential. If something string-interpolates this
     * object into a message, the message must not become the secret.
     */
    public function __toString(): string
    {
        return '[pickup-credential v'.$this->version.']';
    }
}
