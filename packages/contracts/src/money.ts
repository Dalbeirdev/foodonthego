/**
 * Money is stored and transported as an integer number of minor units (cents).
 *
 * Floating point currency is the classic ordering bug: 0.1 + 0.2 !== 0.3, and a
 * cart of nineteen items ends up a cent off the sum the customer was shown. Every
 * price, fee, tax and total in FoodOnTheGo is an integer, and the only place a
 * decimal appears is in formatting for display.
 */
export type Cents = number;

export const isValidCents = (value: unknown): value is Cents =>
  typeof value === 'number' && Number.isSafeInteger(value) && value >= 0;

/** Percentage points expressed in basis points, so 8.25% tax is 825 and stays exact. */
export type BasisPoints = number;

/**
 * Applies a basis-point rate to an amount, rounding half away from zero.
 *
 * `Math.round` rounds half *up*, which biases every half-cent in the house's
 * favour; over a day of orders that is a real, if small, systematic overcharge.
 */
export const applyRate = (amount: Cents, rate: BasisPoints): Cents => {
  const scaled = amount * rate;
  const whole = Math.trunc(scaled / 10_000);
  const remainder = Math.abs(scaled % 10_000);
  if (remainder * 2 >= 10_000) {
    return whole + Math.sign(scaled || 1);
  }
  return whole;
};

export const sumCents = (values: readonly Cents[]): Cents =>
  values.reduce((total, value) => total + value, 0);

export const formatCents = (value: Cents, currency = 'USD', locale = 'en-US'): string =>
  new Intl.NumberFormat(locale, { style: 'currency', currency }).format(value / 100);
