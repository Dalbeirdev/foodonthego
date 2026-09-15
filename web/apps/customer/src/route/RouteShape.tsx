import { useMemo } from 'react';
import { boundsOf, type Bounds, type LatLng } from './polyline.js';

/**
 * The journey drawn from its own geometry, with no map tiles behind it.
 *
 * **This is not a picture of a map and does not pretend to be one.** There is no
 * basemap, no roads, no labels and no scale bar. What it draws is the route's
 * real polyline — the one the provider returned and the server stored — in Web
 * Mercator, with the origin and destination marked and the whole thing framed to
 * its own bounds.
 *
 * It exists because of MF-08: no Google Maps key exists for any platform, so
 * tiles cannot load. The alternative to this is the grey box the brief names as
 * a completion blocker. A customer looking at this can still see the shape of
 * where they are going and how the alternatives differ, which is most of what
 * the map was for, and the notice above it says plainly what is missing.
 *
 * When a Maps key is configured, {@see RouteMap} renders a real Google map
 * instead and this component is not used.
 */

export interface ShapeRoute {
  readonly id: string;
  readonly points: readonly LatLng[];
  readonly isSelected: boolean;
}

/**
 * Web Mercator, the projection every slippy map uses.
 *
 * Not plate carrée (plotting latitude directly), which is the shortcut that
 * looks fine on a short route and visibly squashes anything spanning a few
 * degrees. India sits far enough from the equator for the difference to show.
 */
const mercatorY = (lat: number): number => {
  const clamped = Math.max(-85.05112878, Math.min(85.05112878, lat));
  const radians = (clamped * Math.PI) / 180;
  return Math.log(Math.tan(Math.PI / 4 + radians / 2));
};

const VIEWBOX_WIDTH = 1000;
const PADDING = 44;

/**
 * The drawing is shaped like the journey, not like a fixed box.
 *
 * A fixed 3:4 panel gave a Delhi–Jaipur route — which is wide and shallow — a
 * tall frame it filled about a twelfth of, so the line sat in a field of empty
 * grey. Deriving the height from the route's own projected bounds means a wide
 * journey gets a wide box and a north–south one gets a tall box.
 *
 * Clamped at both ends: a perfectly straight east–west route would otherwise
 * ask for a one-pixel-high strip, and a due-north one for something taller than
 * any screen.
 */
const MIN_RATIO = 0.36; // widescreen-ish
const MAX_RATIO = 1.25; // taller than wide, but not a column

interface Projector {
  (point: LatLng): { readonly x: number; readonly y: number };
}

/** Height in viewBox units, from the shape of the bounds. */
const viewboxHeightFor = (bounds: Bounds): number => {
  const spanX = Math.max(bounds.east - bounds.west, 1e-6);
  const spanY = Math.max(mercatorY(bounds.north) - mercatorY(bounds.south), 1e-6);
  const ratio = Math.min(MAX_RATIO, Math.max(MIN_RATIO, spanY / spanX));

  return Math.round(VIEWBOX_WIDTH * ratio);
};

const projectorFor = (bounds: Bounds, height: number): Projector => {
  const left = bounds.west;
  const right = bounds.east;
  const top = mercatorY(bounds.north);
  const bottom = mercatorY(bounds.south);

  // A route that is a single point, or perfectly north–south, has zero extent on
  // one axis. Dividing by it produces NaN and an empty <path>; a floor keeps the
  // line on screen as a short stub, which is the truth about that geometry.
  const spanX = Math.max(right - left, 1e-6);
  const spanY = Math.max(top - bottom, 1e-6);

  const usableWidth = VIEWBOX_WIDTH - PADDING * 2;
  const usableHeight = height - PADDING * 2;

  // One scale for both axes, so the shape is not stretched to fill the box.
  const scale = Math.min(usableWidth / spanX, usableHeight / spanY);

  const offsetX = PADDING + (usableWidth - spanX * scale) / 2;
  const offsetY = PADDING + (usableHeight - spanY * scale) / 2;

  return (point) => ({
    x: offsetX + (point.lng - left) * scale,
    y: offsetY + (top - mercatorY(point.lat)) * scale,
  });
};

const pathFor = (points: readonly LatLng[], project: Projector): string =>
  points
    .map((point, index) => {
      const { x, y } = project(point);
      return `${index === 0 ? 'M' : 'L'}${x.toFixed(1)} ${y.toFixed(1)}`;
    })
    .join(' ');

export const RouteShape = ({
  routes,
  originLabel,
  destinationLabel,
  bounds,
}: {
  routes: readonly ShapeRoute[];
  originLabel: string;
  destinationLabel: string;
  /** The server's bounds where it sent them — the provider's, over the full geometry. */
  bounds: Bounds | null;
}) => {
  const frame = useMemo(() => {
    const all = routes.flatMap((r) => [...r.points]);
    return bounds ?? boundsOf(all);
  }, [routes, bounds]);

  if (frame === null || routes.length === 0) return null;

  const height = viewboxHeightFor(frame);
  const project = projectorFor(frame, height);
  const selected = routes.find((r) => r.isSelected) ?? routes[0];
  const ends = selected?.points ?? [];
  const start = ends[0];
  const finish = ends[ends.length - 1];

  return (
    <svg
      className="route-shape"
      viewBox={`0 0 ${VIEWBOX_WIDTH} ${height}`}
      preserveAspectRatio="xMidYMid meet"
      role="img"
      aria-label={`The shape of your journey from ${originLabel} to ${destinationLabel}. Map tiles are not available in this build.`}
    >
      {/* Alternatives first, so the selected route is drawn over them. */}
      {routes
        .filter((route) => !route.isSelected)
        .map((route) => (
          <path
            key={route.id}
            className="route-shape__line route-shape__line--alternate"
            d={pathFor(route.points, project)}
            fill="none"
          />
        ))}

      {selected !== undefined ? (
        <path
          className="route-shape__line route-shape__line--selected"
          d={pathFor(selected.points, project)}
          fill="none"
        />
      ) : null}

      {start !== undefined ? (
        <g className="route-shape__marker route-shape__marker--origin">
          <circle cx={project(start).x} cy={project(start).y} r={11} />
          <circle cx={project(start).x} cy={project(start).y} r={4.5} className="route-shape__pip" />
        </g>
      ) : null}

      {finish !== undefined ? (
        <g className="route-shape__marker route-shape__marker--destination">
          <circle cx={project(finish).x} cy={project(finish).y} r={11} />
          <circle
            cx={project(finish).x}
            cy={project(finish).y}
            r={4.5}
            className="route-shape__pip"
          />
        </g>
      ) : null}
    </svg>
  );
};
