<?php

declare(strict_types=1);

namespace App\Support\Phone;

use Stringable;

/**
 * A normalized mobile number.
 *
 * The canonical identity of a customer is **E.164** — `+919876543210`. Visual
 * formatting ("98765 43210", "+91 98765-43210", "09876543210") is presentation and
 * is never the identity: three customers typing the same number three ways must
 * resolve to one account, and a uniqueness constraint over a formatted string
 * would not stop them creating three.
 */
final readonly class PhoneNumber implements Stringable
{
    /**
     * @internal Construct through {@see PhoneNormalizer::normalize()} or
     *           {@see self::fromE164()}. Those validate; this does not.
     */
    public function __construct(
        public string $e164,
        public string $countryCode,
        public string $nationalNumber,
    ) {}

    public static function fromE164(string $e164): self
    {
        $parsed = PhoneNormalizer::normalize($e164);
        if ($parsed === null) {
            throw new \InvalidArgumentException('Not a valid E.164 number.');
        }

        return $parsed;
    }

    /**
     * A display form that reveals only the last four digits.
     *
     * Used on the OTP screen and anywhere the number is echoed back. Printing the
     * whole number to somebody who has only typed it once helps nobody and leaks
     * it into screenshots, support tickets and shoulder-surfing range.
     */
    public function masked(): string
    {
        $visible = 4;
        if (strlen($this->nationalNumber) <= $visible) {
            return '+'.$this->countryCode.' '.str_repeat('•', strlen($this->nationalNumber));
        }

        $hidden = str_repeat('•', strlen($this->nationalNumber) - $visible);

        return '+'.$this->countryCode.' '.$hidden.substr($this->nationalNumber, -$visible);
    }

    /** The form written to logs. Never the full number. */
    public function forLogging(): string
    {
        return $this->masked();
    }

    public function __toString(): string
    {
        return $this->e164;
    }
}
