<?php

declare(strict_types=1);

namespace App\Support;

use InvalidArgumentException;

/**
 * An amount of money.
 *
 * Integer minor units — paise for rupees, cents for dollars — and a currency,
 * always together. Two rules, and both of them are the reason this class exists
 * rather than a pair of loose variables.
 *
 * **Never a float.** A binary floating-point number cannot represent 0.10
 * exactly. A menu price that has been through one is a bill that does not add
 * up, and the error compounds the moment a later module starts summing a cart.
 *
 * **Never an amount without its currency.** "24900" is not a price. Storing the
 * two apart is how a rupee menu ends up rendered in dollars the first time this
 * platform crosses a border.
 *
 * Deliberately *not* a formatter. What a price looks like — the symbol, the
 * grouping, whether the paise are shown — is a locale decision, and the server
 * does not know the customer's. The API sends the amount and the currency; the
 * client renders them. See `25-customer-menu-browsing.md`.
 */
final readonly class Money
{
    /** Currencies this platform knows how to divide. */
    private const SUBUNITS = [
        'INR' => 100,
        'USD' => 100,
        'EUR' => 100,
        'GBP' => 100,
        // Zero-decimal currencies exist and are not a rounding edge case: 100
        // yen is 100, not 10 000. Listed so the day one is needed the answer is
        // here rather than assumed.
        'JPY' => 1,
    ];

    private function __construct(
        public int $minor,
        public string $currency,
    ) {}

    /**
     * @throws InvalidArgumentException
     */
    public static function fromMinor(int $minor, string $currency = 'INR'): self
    {
        $code = strtoupper(trim($currency));

        if (! isset(self::SUBUNITS[$code])) {
            throw new InvalidArgumentException("Unknown currency: {$currency}");
        }

        if ($minor < 0) {
            // A negative menu price is not a discount, it is a corrupt row. The
            // column is unsigned so one cannot be stored; this catches the case
            // where a value reaches here from somewhere that is not the column.
            throw new InvalidArgumentException('An amount cannot be negative.');
        }

        return new self($minor, $code);
    }

    /**
     * Reads a stored price, or null if the row cannot be trusted.
     *
     * Used on the customer path, where a single corrupt row must not take the
     * whole menu down. The caller omits the item rather than rendering a price
     * nobody can defend.
     */
    public static function tryFromMinor(mixed $minor, mixed $currency): ?self
    {
        if (! is_int($minor) && ! (is_string($minor) && ctype_digit($minor))) {
            return null;
        }

        if (! is_string($currency)) {
            return null;
        }

        try {
            return self::fromMinor((int) $minor, $currency);
        } catch (InvalidArgumentException) {
            return null;
        }
    }

    /** How many minor units make one major unit of this currency. */
    public function subunits(): int
    {
        return self::SUBUNITS[$this->currency];
    }

    /** True when the amount is a whole number of rupees, dollars, and so on. */
    public function isWhole(): bool
    {
        return $this->minor % $this->subunits() === 0;
    }

    public function isZero(): bool
    {
        return $this->minor === 0;
    }

    /**
     * @return array{amount_minor: int, currency: string}
     */
    public function toApiArray(): array
    {
        return [
            'amount_minor' => $this->minor,
            'currency' => $this->currency,
        ];
    }
}
