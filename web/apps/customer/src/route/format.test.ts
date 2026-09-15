import { describe, expect, it } from 'vitest';
import {
  formatCalculatedAt,
  formatDistance,
  formatDuration,
  formatTrafficLine,
  optionLabel,
} from './format.js';

/**
 * Formatting, and the two honesty rules inside it.
 *
 * Most of this is presentation. Two functions are not: `formatTrafficLine`
 * decides whether the app claims to know about traffic, and `optionLabel`
 * decides whether it claims a route is the fastest. Both are easy to get wrong
 * in the direction of claiming more than the provider said.
 */

describe('formatDistance', () => {
  it('uses kilometres for a journey', () => {
    expect(formatDistance(236_786)).toBe('237 km');
  });

  it('keeps one decimal under ten kilometres', () => {
    expect(formatDistance(4_300)).toBe('4.3 km');
  });

  it('drops the decimal above ten, where it is false precision', () => {
    expect(formatDistance(42_600)).toBe('43 km');
  });

  it('rounds short distances to fifty metres', () => {
    // "347 m" implies a precision no routing provider has.
    expect(formatDistance(347)).toBe('350 m');
    expect(formatDistance(120)).toBe('100 m');
  });

  it('shows a dash rather than a zero when there is no figure', () => {
    expect(formatDistance(null)).toBe('—');
    expect(formatDistance(undefined)).toBe('—');
    expect(formatDistance(Number.NaN)).toBe('—');
  });
});

describe('formatDuration', () => {
  it('says hours and minutes the way a person would', () => {
    expect(formatDuration(14_179)).toBe('3 hr 56 min');
  });

  it('omits the minutes when there are none', () => {
    expect(formatDuration(7_200)).toBe('2 hr');
  });

  it('omits the hours when there are none', () => {
    expect(formatDuration(1_500)).toBe('25 min');
  });

  it('never says zero minutes', () => {
    // Zero reads as a failure to calculate rather than as a short journey.
    expect(formatDuration(40)).toBe('Less than a minute');
  });

  it('shows a dash rather than a zero when there is no figure', () => {
    expect(formatDuration(null)).toBe('—');
  });
});

describe('formatTrafficLine', () => {
  it('says nothing at all when the provider returned no traffic figure', () => {
    // The rule this whole function exists for. `traffic ?? duration` reads as a
    // sensible default and produces a claim about traffic nobody made.
    expect(formatTrafficLine(14_179, null)).toBeNull();
    expect(formatTrafficLine(14_179, undefined)).toBeNull();
    expect(formatTrafficLine(14_179, Number.NaN)).toBeNull();
  });

  it('reports a real traffic figure', () => {
    expect(formatTrafficLine(14_179, 14_200)).toBe('About 3 hr 57 min with current traffic');
  });

  it('says how much slower when traffic adds time', () => {
    expect(formatTrafficLine(14_179, 16_000)).toContain('slower than usual');
  });

  it('says how much quicker when the roads are clear', () => {
    expect(formatTrafficLine(16_000, 14_179)).toContain('quicker than usual');
  });

  it('does not make a story out of a two-minute difference', () => {
    const line = formatTrafficLine(14_179, 14_230);
    expect(line).toBe('About 3 hr 57 min with current traffic');
    expect(line).not.toContain('slower');
  });
});

describe('formatCalculatedAt', () => {
  const now = new Date('2026-09-15T12:00:00Z');

  it('says just now for a fresh calculation', () => {
    expect(formatCalculatedAt('2026-09-15T11:59:30Z', now)).toBe('Worked out just now');
  });

  it('counts minutes, because traffic ages', () => {
    expect(formatCalculatedAt('2026-09-15T11:30:00Z', now)).toBe('Worked out 30 min ago');
  });

  it('counts hours', () => {
    expect(formatCalculatedAt('2026-09-15T09:00:00Z', now)).toBe('Worked out 3 hr ago');
  });

  it('says nothing for a missing or unreadable timestamp', () => {
    expect(formatCalculatedAt(null, now)).toBeNull();
    expect(formatCalculatedAt('not a date', now)).toBeNull();
  });
});

describe('optionLabel', () => {
  const route = (duration: number, traffic: number | null = null) => ({
    duration_seconds: duration,
    traffic_duration_seconds: traffic,
  });

  it('does not rank a single route', () => {
    const only = [route(14_179)];
    expect(optionLabel(only[0]!, only, 0)).toBe('Your route');
  });

  it('calls the quickest one fastest', () => {
    const all = [route(14_179), route(15_500)];
    expect(optionLabel(all[0]!, all, 0)).toBe('Fastest');
    expect(optionLabel(all[1]!, all, 1)).toBe('Route 2');
  });

  it('claims nothing when two routes tie', () => {
    // No route is *the* fastest, so none of them says it is.
    const all = [route(14_179), route(14_179)];
    expect(optionLabel(all[0]!, all, 0)).toBe('Route 1');
    expect(optionLabel(all[1]!, all, 1)).toBe('Route 2');
  });

  it('compares traffic figures when every route has one', () => {
    // Base durations say the first is quicker; traffic says the second is.
    const all = [route(14_000, 16_000), route(14_500, 15_000)];
    expect(optionLabel(all[0]!, all, 0)).toBe('Route 1');
    expect(optionLabel(all[1]!, all, 1)).toBe('Fastest');
  });

  it('falls back to base duration when only some routes have traffic', () => {
    // Comparing a traffic-aware duration against a base one would hand the
    // label to whichever route happened to lack traffic data.
    const all = [route(14_000, 18_000), route(14_500, null)];
    expect(optionLabel(all[0]!, all, 0)).toBe('Fastest');
  });
});
