import { describe, expect, it } from 'vitest';
import { computeTotals, lineTotal } from './pricing.js';

const policy = { taxBasisPoints: 825, serviceFeeBasisPoints: 500, serviceFeeCapCents: 599 };

describe('computeTotals', () => {
  it('adds up a simple order the way the receipt reads', () => {
    const totals = computeTotals([{ unitPriceCents: 1250, quantity: 2 }], 299, 500, policy);

    expect(totals.subtotalCents).toBe(2500);
    expect(totals.serviceFeeCents).toBe(125); // 5% of 2500
    expect(totals.deliveryFeeCents).toBe(299);
    // 8.25% of (2500 + 299 + 125) = 241.23, which rounds to 241.
    expect(totals.taxCents).toBe(241);
    expect(totals.totalCents).toBe(
      totals.subtotalCents + totals.deliveryFeeCents + totals.serviceFeeCents + totals.taxCents + totals.tipCents,
    );
  });

  it('caps the service fee rather than scaling it forever', () => {
    const small = computeTotals([{ unitPriceCents: 1000, quantity: 1 }], 0, 0, policy);
    expect(small.serviceFeeCents).toBe(50);

    const huge = computeTotals([{ unitPriceCents: 100_000, quantity: 1 }], 0, 0, policy);
    expect(huge.serviceFeeCents).toBe(599);
  });

  it('does not tax the tip', () => {
    const withoutTip = computeTotals([{ unitPriceCents: 2000, quantity: 1 }], 299, 0, policy);
    const withTip = computeTotals([{ unitPriceCents: 2000, quantity: 1 }], 299, 1000, policy);

    expect(withTip.taxCents).toBe(withoutTip.taxCents);
    expect(withTip.totalCents).toBe(withoutTip.totalCents + 1000);
  });

  it('produces a total that is exactly the sum of its parts, over many shapes', () => {
    for (let price = 1; price < 4000; price += 137) {
      for (let quantity = 1; quantity <= 4; quantity += 1) {
        const totals = computeTotals([{ unitPriceCents: price, quantity }], 299, 137, policy);
        expect(totals.totalCents).toBe(
          totals.subtotalCents +
            totals.deliveryFeeCents +
            totals.serviceFeeCents +
            totals.taxCents +
            totals.tipCents,
        );
        expect(Number.isInteger(totals.totalCents)).toBe(true);
      }
    }
  });

  it('is zero all the way down for an empty cart', () => {
    const totals = computeTotals([], 0, 0, policy);
    expect(totals).toEqual({
      subtotalCents: 0,
      deliveryFeeCents: 0,
      serviceFeeCents: 0,
      taxCents: 0,
      tipCents: 0,
      totalCents: 0,
    });
  });

  it('multiplies a line rather than repeating it', () => {
    expect(lineTotal({ unitPriceCents: 799, quantity: 3 })).toBe(2397);
  });
});
