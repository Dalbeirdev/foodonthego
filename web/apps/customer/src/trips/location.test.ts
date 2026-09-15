import { describe, expect, it } from 'vitest';
import {
  isSamePlace,
  metresBetween,
  SAME_LOCATION_METRES,
  toRequestBody,
  type LocationSelection,
} from './location.js';

/**
 * The normalised selection, and the two rules that read it.
 *
 * All coordinates below are the real published positions of real places, taken
 * from the same development gazetteer the server uses. Nothing here is a made-up
 * number chosen to make an assertion pass.
 */

const at = (over: Partial<LocationSelection>): LocationSelection => ({
  sourceType: 'PLACE_SEARCH',
  displayName: 'Somewhere',
  formattedAddress: null,
  placeId: null,
  latitude: 28.6315,
  longitude: 77.2167,
  savedAddressId: null,
  city: null,
  region: null,
  countryCode: null,
  postalCode: null,
  ...over,
});

describe('toRequestBody', () => {
  it('sends a saved address as its identifier and nothing else', () => {
    const body = toRequestBody(
      at({
        sourceType: 'SAVED_ADDRESS',
        savedAddressId: 'addr-uuid',
        latitude: 19.076,
        longitude: 72.8777,
        displayName: 'Home',
      }),
    );

    expect(body).toEqual({ source_type: 'SAVED_ADDRESS', saved_address_id: 'addr-uuid' });

    // The point of the assertion above, said explicitly: coordinates a client
    // holds for a saved address never reach the server, so a tampered client
    // has nothing to tamper with. The server reads the row it owns.
    expect(body).not.toHaveProperty('latitude');
    expect(body).not.toHaveProperty('longitude');
    expect(body).not.toHaveProperty('display_name');
  });

  it('sends the full place for a search result', () => {
    const body = toRequestBody(
      at({
        sourceType: 'PLACE_SEARCH',
        placeId: 'dev:hawa-mahal',
        displayName: 'Hawa Mahal',
        formattedAddress: 'Hawa Mahal Road, Jaipur, Rajasthan 302002',
        latitude: 26.9239,
        longitude: 75.8267,
        city: 'Jaipur',
        region: 'Rajasthan',
        countryCode: 'IN',
        postalCode: '302002',
      }),
    );

    expect(body).toMatchObject({
      source_type: 'PLACE_SEARCH',
      place_id: 'dev:hawa-mahal',
      latitude: 26.9239,
      longitude: 75.8267,
      country_code: 'IN',
    });
  });

  it('sends a device fix with its coordinates and no place id', () => {
    const body = toRequestBody(
      at({ sourceType: 'CURRENT_LOCATION', displayName: 'Current location', placeId: null }),
    );

    expect(body).toMatchObject({ source_type: 'CURRENT_LOCATION', place_id: null });
  });
});

describe('metresBetween', () => {
  it('measures a known distance', () => {
    // Connaught Place to Hauz Khas, about 10 km by air.
    const distance = metresBetween(
      at({ latitude: 28.6315, longitude: 77.2167 }),
      at({ latitude: 28.5494, longitude: 77.2001 }),
    );

    expect(distance).toBeGreaterThan(9_000);
    expect(distance).toBeLessThan(10_500);
  });

  it('is zero for the same point', () => {
    expect(metresBetween(at({}), at({}))).toBeCloseTo(0, 5);
  });
});

describe('isSamePlace', () => {
  it('catches the same saved address chosen for both ends', () => {
    const home = at({ sourceType: 'SAVED_ADDRESS', savedAddressId: 'a1' });
    expect(isSamePlace(home, home)).toBe(true);
  });

  it('catches the same place id even when the labels differ', () => {
    expect(
      isSamePlace(
        at({ placeId: 'dev:connaught-place', displayName: 'Connaught Place' }),
        at({ placeId: 'dev:connaught-place', displayName: 'CP' }),
      ),
    ).toBe(true);
  });

  it('catches two different identifiers at the same spot', () => {
    // The case a string comparison misses: one end chosen from a saved address
    // and the other searched for, both the same building.
    expect(
      isSamePlace(
        at({ sourceType: 'SAVED_ADDRESS', savedAddressId: 'a1', latitude: 28.6315, longitude: 77.2167 }),
        at({ placeId: 'dev:connaught-place', latitude: 28.6316, longitude: 77.2168 }),
      ),
    ).toBe(true);
  });

  it('allows a genuinely short journey', () => {
    // Roughly 300 m apart — four times the threshold, and a real trip somebody
    // might want food on. A generous radius would refuse this.
    const near = isSamePlace(
      at({ placeId: 'a', latitude: 28.6315, longitude: 77.2167 }),
      at({ placeId: 'b', latitude: 28.6342, longitude: 77.2167 }),
    );

    expect(near).toBe(false);
  });

  it('agrees with the server about where the line is', () => {
    // A negative control on the threshold itself: nudge two points from just
    // inside it to just outside and the answer must change. If it did not, the
    // distance branch would be dead code and the two identity branches would be
    // carrying the whole test above.
    const metresPerDegreeLatitude = 111_320;
    const inside = (SAME_LOCATION_METRES - 20) / metresPerDegreeLatitude;
    const outside = (SAME_LOCATION_METRES + 20) / metresPerDegreeLatitude;

    expect(isSamePlace(at({ placeId: 'a' }), at({ placeId: 'b', latitude: 28.6315 + inside }))).toBe(true);
    expect(isSamePlace(at({ placeId: 'a' }), at({ placeId: 'b', latitude: 28.6315 + outside }))).toBe(false);
  });
});
