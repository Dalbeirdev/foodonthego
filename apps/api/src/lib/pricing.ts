import { applyRate, sumCents, type Cents, type OrderTotals } from '@fotg/contracts';

export interface PricingPolicy {
  taxBasisPoints: number;
  serviceFeeBasisPoints: number;
  serviceFeeCapCents: Cents;
}

export interface PriceableLine {
  unitPriceCents: Cents;
  quantity: number;
}

export const lineTotal = (line: PriceableLine): Cents => line.unitPriceCents * line.quantity;

/**
 * The single place any total is computed, for both the cart preview and the order
 * that is finally written. The checkout screen and the receipt cannot disagree
 * because there is only one implementation for them to disagree about.
 *
 * Order of operations is a decision, not an accident:
 *   subtotal -> service fee (capped) -> tax on subtotal + delivery + service -> tip
 *
 * The tip is added last and is not taxed, because it is a gratuity rather than part
 * of the sale. Tax is charged on the fees as well as the food, which is the common
 * treatment for a delivery charge that is part of the taxable sale price.
 */
export const computeTotals = (
  lines: readonly PriceableLine[],
  deliveryFeeCents: Cents,
  tipCents: Cents,
  policy: PricingPolicy,
): OrderTotals => {
  const subtotalCents = sumCents(lines.map(lineTotal));

  const serviceFeeCents = Math.min(
    applyRate(subtotalCents, policy.serviceFeeBasisPoints),
    policy.serviceFeeCapCents,
  );

  const taxableCents = subtotalCents + deliveryFeeCents + serviceFeeCents;
  const taxCents = applyRate(taxableCents, policy.taxBasisPoints);

  return {
    subtotalCents,
    deliveryFeeCents,
    serviceFeeCents,
    taxCents,
    tipCents,
    totalCents: taxableCents + taxCents + tipCents,
  };
};
