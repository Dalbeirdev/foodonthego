/**
 * Google's encoded polyline algorithm, decode only.
 *
 * One implementation, here, used by the map and by nothing else. The format is
 * simple enough that every project reinvents it and subtly wrong often enough
 * that this file has a test with a known-good fixture: the sign handling and the
 * delta accumulation are the two things that go wrong, and both produce a line
 * that looks almost right.
 *
 * The server sends `encoded_polyline` exactly as the provider produced it, so
 * this is the provider's own format and not a FoodOnTheGo invention.
 */

export interface LatLng {
  readonly lat: number;
  readonly lng: number;
}

/** Google's fixed scale: five decimal places, as integers. */
const PRECISION = 1e5;

export const decodePolyline = (encoded: string): LatLng[] => {
  const points: LatLng[] = [];
  let index = 0;
  let lat = 0;
  let lng = 0;

  while (index < encoded.length) {
    for (const axis of ['lat', 'lng'] as const) {
      let result = 0;
      let shift = 0;
      let byte: number;

      do {
        const code = encoded.charCodeAt(index);
        index += 1;
        // A malformed or truncated string must not spin: charCodeAt past the
        // end is NaN, and NaN - 63 is NaN, which would never clear the
        // continuation bit.
        if (Number.isNaN(code)) return points;
        byte = code - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);

      // The low bit is the sign, and the rest is the magnitude — not two's
      // complement. Getting this wrong mirrors every other point across the
      // equator, which on a short route looks like a plausible wobble.
      const delta = result & 1 ? ~(result >> 1) : result >> 1;

      if (axis === 'lat') lat += delta;
      else lng += delta;
    }

    points.push({ lat: lat / PRECISION, lng: lng / PRECISION });
  }

  return points;
};

export interface Bounds {
  readonly north: number;
  readonly south: number;
  readonly east: number;
  readonly west: number;
}

/**
 * The box a set of points sits in.
 *
 * Used only when the server did not send bounds. The server's own are preferred
 * because they are the provider's, computed over the full geometry rather than
 * over whatever this client managed to decode.
 */
export const boundsOf = (points: readonly LatLng[]): Bounds | null => {
  if (points.length === 0) return null;

  let north = -90;
  let south = 90;
  let east = -180;
  let west = 180;

  for (const p of points) {
    if (p.lat > north) north = p.lat;
    if (p.lat < south) south = p.lat;
    if (p.lng > east) east = p.lng;
    if (p.lng < west) west = p.lng;
  }

  return { north, south, east, west };
};

/**
 * Thins a long line down to something a browser can draw smoothly.
 *
 * Keeps the first and last point always, so the route still starts and ends
 * where it should. A Delhi–Jaipur route is a few hundred points and needs none
 * of this; a coast road can be tens of thousands, and an SVG path with that many
 * commands janks on a phone.
 *
 * Deliberately not Douglas–Peucker: even sampling cannot move a point, only drop
 * one, so the line it draws is always a subset of the real geometry rather than
 * an approximation of it.
 */
export const thin = (points: readonly LatLng[], limit = 1_500): readonly LatLng[] => {
  if (points.length <= limit) return points;

  const step = (points.length - 1) / (limit - 1);
  const out: LatLng[] = [];

  for (let i = 0; i < limit - 1; i += 1) {
    const point = points[Math.round(i * step)];
    if (point !== undefined) out.push(point);
  }

  const last = points[points.length - 1];
  if (last !== undefined) out.push(last);

  return out;
};
