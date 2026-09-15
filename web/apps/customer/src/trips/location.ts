/**
 * One chosen end of a journey, in the app's own shape.
 *
 * Three very different things produce one of these — a device fix, a saved
 * address, a place the customer searched for — and the rest of the planner is
 * written against this type rather than against any of the three. That is the
 * point: the CTA's enabled/disabled rule, the summary, the validation and the
 * request body all read the same fields whichever source filled them.
 *
 * `sourceType` is carried explicitly and never inferred from which fields
 * happen to be populated. A saved address that has a place id is still a saved
 * address, and the server records the difference because Module 06 will care:
 * a corridor drawn from a GPS fix and one drawn from a geocoded postal address
 * do not have the same error bars.
 */
export type LocationSourceType = 'CURRENT_LOCATION' | 'SAVED_ADDRESS' | 'PLACE_SEARCH';

export interface LocationSelection {
  readonly sourceType: LocationSourceType;
  /** What the customer sees. Never empty — see the three constructors below. */
  readonly displayName: string;
  readonly formattedAddress: string | null;
  readonly placeId: string | null;
  readonly latitude: number;
  readonly longitude: number;
  /** Set only for SAVED_ADDRESS, and the only field the server trusts for one. */
  readonly savedAddressId: string | null;
  readonly city: string | null;
  readonly region: string | null;
  readonly countryCode: string | null;
  readonly postalCode: string | null;
}

/**
 * The request body for one end of a trip.
 *
 * A saved address sends its identifier and *nothing else* — no coordinates, no
 * address text. Not an optimisation: the server resolves the row through Module
 * 04's ownership-scoped lookup and reads the position from it, so a client that
 * sent coordinates would be sending values that are ignored. Sending them
 * anyway would create the appearance of a trust boundary that is not there, and
 * the next person to read this would have to go and check.
 */
export const toRequestBody = (selection: LocationSelection): Record<string, unknown> => {
  if (selection.sourceType === 'SAVED_ADDRESS') {
    return { source_type: 'SAVED_ADDRESS', saved_address_id: selection.savedAddressId };
  }

  return {
    source_type: selection.sourceType,
    place_id: selection.placeId,
    display_name: selection.displayName,
    formatted_address: selection.formattedAddress,
    latitude: selection.latitude,
    longitude: selection.longitude,
    city: selection.city,
    region: selection.region,
    country_code: selection.countryCode,
    postal_code: selection.postalCode,
  };
};

const EARTH_RADIUS_METRES = 6_371_000;

/** Great-circle distance, for the same-place check only. */
export const metresBetween = (a: LocationSelection, b: LocationSelection): number => {
  const toRadians = (deg: number): number => (deg * Math.PI) / 180;
  const dLat = toRadians(b.latitude - a.latitude);
  const dLng = toRadians(b.longitude - a.longitude);
  const lat1 = toRadians(a.latitude);
  const lat2 = toRadians(b.latitude);

  const h =
    Math.sin(dLat / 2) ** 2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2;

  return 2 * EARTH_RADIUS_METRES * Math.asin(Math.min(1, Math.sqrt(h)));
};

/**
 * The same threshold the server uses (TRIP_SAME_LOCATION_METRES, 75 m).
 *
 * Duplicated here on purpose and *only* to grey out the CTA before a doomed
 * request is sent. The server decides — this client cannot be trusted to, and
 * a disagreement between the two shows up as a validation error the planner
 * already renders rather than as a trip that should not exist.
 */
export const SAME_LOCATION_METRES = 75;

/**
 * Whether these two ends are the same place.
 *
 * More than a string comparison, because "Connaught Place" chosen from a saved
 * address and chosen from a search have different labels and the same position.
 * Identity first (same saved address, same place id), then distance.
 */
export const isSamePlace = (a: LocationSelection, b: LocationSelection): boolean => {
  if (a.savedAddressId !== null && a.savedAddressId === b.savedAddressId) return true;
  if (a.placeId !== null && a.placeId === b.placeId) return true;
  return metresBetween(a, b) <= SAME_LOCATION_METRES;
};
