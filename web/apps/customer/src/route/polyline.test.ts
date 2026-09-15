import { describe, expect, it } from 'vitest';
import { boundsOf, decodePolyline, thin } from './polyline.js';

/**
 * The decoder, against a fixture nobody here invented.
 *
 * `_p~iF~ps|U_ulLnnqC_mqNvxq`@` is the example string in Google's own encoded
 * polyline documentation, and it decodes to (38.5, -120.2), (40.7, -120.95),
 * (43.252, -126.453). Using their fixture rather than a round-trip of our own
 * encoder is the point: a round trip passes just as happily when the encoder and
 * the decoder are wrong in the same direction.
 */
const GOOGLE_FIXTURE = '_p~iF~ps|U_ulLnnqC_mqNvxq`@';

describe('decodePolyline', () => {
  it("decodes Google's own documented example", () => {
    const points = decodePolyline(GOOGLE_FIXTURE);

    expect(points).toHaveLength(3);
    expect(points[0]?.lat).toBeCloseTo(38.5, 5);
    expect(points[0]?.lng).toBeCloseTo(-120.2, 5);
    expect(points[1]?.lat).toBeCloseTo(40.7, 5);
    expect(points[1]?.lng).toBeCloseTo(-120.95, 5);
    expect(points[2]?.lat).toBeCloseTo(43.252, 5);
    expect(points[2]?.lng).toBeCloseTo(-126.453, 5);
  });

  it('keeps negative values negative', () => {
    // The sign is the low bit, not two's complement. Getting it wrong mirrors
    // every point across the equator — which on a short route reads as a wobble
    // rather than as a bug.
    const points = decodePolyline(GOOGLE_FIXTURE);
    expect(points.every((p) => p.lng < 0)).toBe(true);
  });

  it('accumulates deltas rather than reading absolute points', () => {
    // Each pair after the first is an offset. A decoder that treated them as
    // absolute would put every point after the first near the origin.
    const points = decodePolyline(GOOGLE_FIXTURE);
    expect(points[2]?.lat).toBeGreaterThan(points[0]?.lat ?? 0);
  });

  it('returns nothing for an empty string', () => {
    expect(decodePolyline('')).toEqual([]);
  });

  it('stops rather than spinning on a truncated string', () => {
    // A cut-off string leaves the continuation bit set with nothing after it.
    // Without the NaN guard this loops for ever and hangs the tab.
    const truncated = GOOGLE_FIXTURE.slice(0, 5);
    const points = decodePolyline(truncated);
    expect(Array.isArray(points)).toBe(true);
  });
});

describe('boundsOf', () => {
  it('boxes the points', () => {
    const bounds = boundsOf(decodePolyline(GOOGLE_FIXTURE));

    expect(bounds?.north).toBeCloseTo(43.252, 3);
    expect(bounds?.south).toBeCloseTo(38.5, 3);
    expect(bounds?.east).toBeCloseTo(-120.2, 3);
    expect(bounds?.west).toBeCloseTo(-126.453, 3);
  });

  it('is null for nothing', () => {
    expect(boundsOf([])).toBeNull();
  });
});

describe('thin', () => {
  const line = Array.from({ length: 5_000 }, (_, i) => ({ lat: 20 + i / 1_000, lng: 70 + i / 1_000 }));

  it('leaves a short line alone', () => {
    const short = line.slice(0, 10);
    expect(thin(short)).toBe(short);
  });

  it('brings a long line under the limit', () => {
    expect(thin(line, 1_000)).toHaveLength(1_000);
  });

  it('keeps the first and last point', () => {
    const thinned = thin(line, 100);
    expect(thinned[0]).toEqual(line[0]);
    expect(thinned[thinned.length - 1]).toEqual(line[line.length - 1]);
  });

  it('only ever drops points, never moves one', () => {
    // The property that makes this safe: every point drawn is a point the
    // provider actually returned, so the line is a subset of the real geometry
    // rather than an approximation of it.
    const thinned = thin(line, 50);
    for (const point of thinned) expect(line).toContainEqual(point);
  });
});
