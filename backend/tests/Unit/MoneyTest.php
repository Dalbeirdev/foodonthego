<?php

declare(strict_types=1);

namespace Tests\Unit;

use App\Support\Money;
use InvalidArgumentException;
use PHPUnit\Framework\TestCase;

/**
 * Money.
 *
 * Small, and worth every one of these tests: a price that has been through a
 * float is a bill that does not add up, and the error compounds the moment a
 * later module starts summing a cart.
 */
final class MoneyTest extends TestCase
{
    public function test_an_amount_is_minor_units_and_a_currency(): void
    {
        $price = Money::fromMinor(24_900, 'INR');

        $this->assertSame(24_900, $price->minor);
        $this->assertSame('INR', $price->currency);
        $this->assertSame(
            ['amount_minor' => 24_900, 'currency' => 'INR'],
            $price->toApiArray(),
        );
    }

    public function test_zero_is_a_price(): void
    {
        // A free item is legitimate — table water, a complimentary papad — and
        // a formatter that treats zero as "no price" prints nothing at all.
        $free = Money::fromMinor(0);

        $this->assertTrue($free->isZero());
        $this->assertSame(0, $free->minor);
    }

    public function test_a_negative_amount_is_refused(): void
    {
        // Not a discount. A corrupt row, and one the column will not hold
        // either — this catches a value that reached here from somewhere that
        // is not the column.
        $this->expectException(InvalidArgumentException::class);

        Money::fromMinor(-1);
    }

    public function test_an_unknown_currency_is_refused(): void
    {
        $this->expectException(InvalidArgumentException::class);

        Money::fromMinor(100, 'XYZ');
    }

    public function test_a_currency_is_normalised(): void
    {
        $this->assertSame('INR', Money::fromMinor(100, 'inr')->currency);
        $this->assertSame('INR', Money::fromMinor(100, ' Inr ')->currency);
    }

    public function test_a_zero_decimal_currency_knows_it_is_one(): void
    {
        // 100 yen is 100, not 10 000. Not a rounding edge case — a different
        // number of subunits, and one this platform will meet the day it
        // crosses a border.
        $this->assertSame(1, Money::fromMinor(100, 'JPY')->subunits());
        $this->assertSame(100, Money::fromMinor(100, 'INR')->subunits());
    }

    public function test_it_knows_a_whole_amount_from_a_fractional_one(): void
    {
        $this->assertTrue(Money::fromMinor(24_900)->isWhole());
        $this->assertFalse(Money::fromMinor(24_950)->isWhole());
    }

    public function test_a_corrupt_row_reads_as_null_rather_than_throwing(): void
    {
        // On the customer path a single bad record must not take a whole menu
        // down. The caller omits the item; it never becomes "₹0".
        $this->assertNull(Money::tryFromMinor(-500, 'INR'));
        $this->assertNull(Money::tryFromMinor(100, 'XYZ'));
        $this->assertNull(Money::tryFromMinor(null, 'INR'));
        $this->assertNull(Money::tryFromMinor(24.99, 'INR'));
        $this->assertNull(Money::tryFromMinor('12.50', 'INR'));
        $this->assertNull(Money::tryFromMinor(100, null));
    }

    public function test_a_digit_string_from_the_driver_is_accepted(): void
    {
        // Some drivers hand back integers as strings. That is not corruption.
        $price = Money::tryFromMinor('24900', 'INR');

        $this->assertNotNull($price);
        $this->assertSame(24_900, $price->minor);
    }

    public function test_a_large_amount_survives(): void
    {
        // ₹12,999. Five figures is where a naive formatter's grouping breaks.
        $price = Money::fromMinor(1_299_900);

        $this->assertSame(1_299_900, $price->minor);
        $this->assertTrue($price->isWhole());
    }
}
