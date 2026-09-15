/**
 * Whether this build can draw a Google map, and with what.
 *
 * Mirrors `mobile/lib/core/config/maps_config.dart` deliberately: one place per
 * platform that knows whether a map is possible, so the answer is not scattered
 * across widgets.
 *
 * ## The key that is allowed to be here
 *
 * This is a **browser Maps key**, and it is the only Google key that may ever
 * appear in a client bundle. It is restricted by HTTP referrer to the domains
 * this app is served from and restricted to the Maps JavaScript API, so it
 * cannot calculate a route, cannot search a place, and is worth nothing to
 * anybody who reads it out of the bundle — which they can, and which is how the
 * Maps JS API is designed to work.
 *
 * The **routing** key and the **places** key are different keys and never leave
 * the server. Restart Module 05 proved the bundle carries neither, and a test
 * keeps it that way.
 */

export const mapsBrowserKey = (): string =>
  (import.meta.env.VITE_GOOGLE_MAPS_BROWSER_KEY as string | undefined)?.trim() ?? '';

/**
 * Whether to attempt a Google map at all.
 *
 * False in this repository as it stands, because no Maps key exists — MF-08,
 * blocked on the client supplying one. When false the route screen renders its
 * **map-unavailable** state, which is a designed state in its own right and not
 * a fallback bolted on: a customer whose tiles will not load must still see
 * where they are going, the shape of the journey, how far it is and how long it
 * takes, and all four come from route data rather than from tiles.
 */
export const canRenderGoogleMap = (): boolean => mapsBrowserKey() !== '';
