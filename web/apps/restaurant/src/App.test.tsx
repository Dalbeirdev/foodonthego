import { describe, expect, it } from 'vitest';
import { restaurantNavigation } from './navigation.js';

describe('restaurant navigation architecture', () => {
  it('covers every area the module specification requires', () => {
    const labels = restaurantNavigation.flatMap((s) => s.items).map((i) => i.label);

    for (const required of [
      'Overview', 'Orders', 'Menu', 'Availability', 'Restaurant',
      'Staff', 'Earnings', 'Reports', 'Reviews', 'Support', 'Settings',
    ]) {
      expect(labels).toContain(required);
    }
  });

  it('gives every route a unique path', () => {
    const paths = restaurantNavigation.flatMap((s) => s.items).map((i) => i.path);
    expect(new Set(paths).size).toBe(paths.length);
  });

  it('claims nothing is implemented, because Module 01 builds no restaurant feature', () => {
    const implemented = restaurantNavigation.flatMap((s) => s.items).filter((i) => i.implemented);
    expect(implemented).toEqual([]);
  });

  it('names the delivering module for every route', () => {
    for (const item of restaurantNavigation.flatMap((s) => s.items)) {
      expect(item.module, `${item.label} has no module`).toMatch(/Module \d+/);
    }
  });
});
