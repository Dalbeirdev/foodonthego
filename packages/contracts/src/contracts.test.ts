import { describe, expect, it } from 'vitest';
import { applyRate, formatCents, sumCents } from './money.js';
import { isOpenAt, type OpeningWindow } from './hours.js';
import { allowedTransitions, canTransition, isTerminalStatus, ORDER_STATUSES } from './orders.js';
import { placeOrderSchema, registerSchema, restaurantSearchSchema } from './schemas.js';

describe('money', () => {
  it('applies a basis-point rate exactly', () => {
    expect(applyRate(10_000, 825)).toBe(825);
    expect(applyRate(1_999, 825)).toBe(165); // 164.9175 -> 165
    expect(applyRate(0, 825)).toBe(0);
  });

  it('rounds half away from zero rather than always up', () => {
    // 100 * 50bp = 0.5 cents exactly.
    expect(applyRate(100, 50)).toBe(1);
    expect(applyRate(-100, 50)).toBe(-1);
  });

  it('sums without floating point drift', () => {
    expect(sumCents([1099, 250, 1099, 799])).toBe(3247);
    expect(sumCents([])).toBe(0);
  });

  it('formats for display only at the edge', () => {
    expect(formatCents(3247)).toBe('$32.47');
    expect(formatCents(0)).toBe('$0.00');
  });
});

describe('opening hours', () => {
  const lunch: OpeningWindow = { weekday: 3, opensMinute: 11 * 60, closesMinute: 15 * 60 };
  // Friday 18:00 through Saturday 02:00.
  const lateNight: OpeningWindow = { weekday: 5, opensMinute: 18 * 60, closesMinute: 2 * 60 };

  const at = (weekday: number, hour: number, minute = 0) => {
    // 2024-01-07 was a Sunday, so adding `weekday` days lands on the weekday we want.
    const date = new Date(2024, 0, 7 + weekday, hour, minute);
    expect(date.getDay()).toBe(weekday);
    return date;
  };

  it('is open inside a same-day window and closed outside it', () => {
    expect(isOpenAt([lunch], at(3, 12))).toBe(true);
    expect(isOpenAt([lunch], at(3, 10, 59))).toBe(false);
    expect(isOpenAt([lunch], at(3, 15))).toBe(false); // closing minute is exclusive
    expect(isOpenAt([lunch], at(4, 12))).toBe(false); // right time, wrong day
  });

  it('handles a window that runs past midnight', () => {
    expect(isOpenAt([lateNight], at(5, 20))).toBe(true); // Friday evening
    expect(isOpenAt([lateNight], at(6, 1))).toBe(true); // Saturday 01:00, still Friday's window
    expect(isOpenAt([lateNight], at(6, 3))).toBe(false); // after it closes
    expect(isOpenAt([lateNight], at(5, 3))).toBe(false); // Friday 03:00 is not Thursday's window
  });

  it('is closed when there are no windows at all', () => {
    expect(isOpenAt([], at(3, 12))).toBe(false);
  });
});

describe('order transitions', () => {
  it('lets the restaurant accept but not the customer', () => {
    expect(canTransition('pending', 'confirmed', 'restaurant')).toBe(true);
    expect(canTransition('pending', 'confirmed', 'customer')).toBe(false);
  });

  it('lets the customer cancel only until the food is being made', () => {
    expect(canTransition('pending', 'cancelled', 'customer')).toBe(true);
    expect(canTransition('confirmed', 'cancelled', 'customer')).toBe(true);
    expect(canTransition('preparing', 'cancelled', 'customer')).toBe(false);
    expect(canTransition('preparing', 'cancelled', 'restaurant')).toBe(true);
  });

  it('refuses to move out of a terminal status', () => {
    for (const status of ['delivered', 'cancelled', 'rejected'] as const) {
      expect(isTerminalStatus(status)).toBe(true);
      expect(allowedTransitions(status)).toEqual([]);
      for (const target of ORDER_STATUSES) {
        expect(canTransition(status, target, 'admin')).toBe(false);
      }
    }
  });

  it('gives admin a path wherever anyone else has one', () => {
    for (const from of ORDER_STATUSES) {
      for (const to of allowedTransitions(from)) {
        expect(canTransition(from, to, 'admin')).toBe(true);
      }
    }
  });

  it('never lets a courier touch the kitchen states', () => {
    expect(canTransition('pending', 'confirmed', 'courier')).toBe(false);
    expect(canTransition('confirmed', 'preparing', 'courier')).toBe(false);
    expect(canTransition('ready_for_pickup', 'out_for_delivery', 'courier')).toBe(true);
    expect(canTransition('out_for_delivery', 'delivered', 'courier')).toBe(true);
  });
});

describe('schemas', () => {
  it('normalises an email and defaults the role', () => {
    const parsed = registerSchema.parse({
      email: '  Ada@Example.COM ',
      password: 'a-long-enough-password',
      fullName: '  Ada Lovelace  ',
    });
    expect(parsed.email).toBe('ada@example.com');
    expect(parsed.fullName).toBe('Ada Lovelace');
    expect(parsed.role).toBe('customer');
  });

  it('rejects a short password', () => {
    const result = registerSchema.safeParse({
      email: 'ada@example.com',
      password: 'short',
      fullName: 'Ada',
    });
    expect(result.success).toBe(false);
  });

  it('will not let a customer register themselves as an admin', () => {
    const result = registerSchema.safeParse({
      email: 'ada@example.com',
      password: 'a-long-enough-password',
      fullName: 'Ada',
      role: 'admin',
    });
    expect(result.success).toBe(false);
  });

  it('coerces query-string search params', () => {
    const parsed = restaurantSearchSchema.parse({ limit: '10', offset: '20', openNow: 'true' });
    expect(parsed).toMatchObject({ limit: 10, offset: 20, openNow: true, sort: 'relevance' });
  });

  it('defaults a tip to nothing rather than guessing', () => {
    const parsed = placeOrderSchema.parse({
      address: { line1: '1 Main St', city: 'Springfield', region: 'IL', postalCode: '62701' },
    });
    expect(parsed.tipCents).toBe(0);
    expect(parsed.address.label).toBe('Home');
  });
});
