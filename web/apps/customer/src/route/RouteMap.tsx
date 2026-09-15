import { useEffect, useMemo, useRef, useState } from 'react';
import { MapPinned } from 'lucide-react';
import { decodePolyline, thin, type Bounds, type LatLng } from './polyline.js';
import { RouteShape, type ShapeRoute } from './RouteShape.js';
import { canRenderGoogleMap, mapsBrowserKey } from './mapsConfig.js';

/**
 * The map, or an honest statement that there is not one.
 *
 * Two states of equal standing, the same design the Flutter app already uses. A
 * map that cannot draw is not a broken screen: the customer still needs to see
 * the journey, and everything except the tiles comes from route data.
 *
 * ## What has actually been verified
 *
 * The **no-tiles** path is what this repository renders today and what the
 * screenshots show, because no Maps key exists — MF-08. The Google path below is
 * written against the Maps JavaScript API and **has never been run**: there is no
 * key to run it with, and this sandbox cannot reach Google. It is not claimed as
 * working anywhere in this module's report.
 */

export interface MapRoute {
  readonly id: string;
  readonly encodedPolyline: string | null;
  readonly isSelected: boolean;
}

/** Minimal shapes for the bits of the Maps JS API this file touches. */
interface GoogleMapsApi {
  readonly Map: new (el: HTMLElement, options: Record<string, unknown>) => GoogleMapInstance;
  readonly Polyline: new (options: Record<string, unknown>) => { setMap: (m: unknown) => void };
  readonly Marker: new (options: Record<string, unknown>) => { setMap: (m: unknown) => void };
  readonly LatLngBounds: new () => { extend: (p: LatLng) => void };
}

interface GoogleMapInstance {
  fitBounds: (bounds: unknown, padding?: number) => void;
}

const MAPS_SCRIPT_ID = 'fotg-google-maps';

/**
 * Loads the Maps JS API once per page.
 *
 * Resolves false rather than throwing when it cannot load — a blocked CDN, a
 * rejected key, no network. The caller then renders the no-tiles state, which
 * is exactly what a customer on a restricted network should get instead of a
 * grey rectangle.
 */
const loadGoogleMaps = (key: string): Promise<GoogleMapsApi | null> =>
  new Promise((resolve) => {
    const existing = (window as { google?: { maps?: GoogleMapsApi } }).google?.maps;
    if (existing !== undefined) {
      resolve(existing);
      return;
    }

    if (document.getElementById(MAPS_SCRIPT_ID) !== null) {
      // Another instance is already loading it; wait for that one.
      const started = Date.now();
      const poll = setInterval(() => {
        const maps = (window as { google?: { maps?: GoogleMapsApi } }).google?.maps;
        if (maps !== undefined) {
          clearInterval(poll);
          resolve(maps);
        } else if (Date.now() - started > 10_000) {
          clearInterval(poll);
          resolve(null);
        }
      }, 100);
      return;
    }

    const script = document.createElement('script');
    script.id = MAPS_SCRIPT_ID;
    script.async = true;
    script.src = `https://maps.googleapis.com/maps/api/js?key=${encodeURIComponent(key)}&libraries=geometry`;
    script.onload = () => resolve((window as { google?: { maps?: GoogleMapsApi } }).google?.maps ?? null);
    script.onerror = () => resolve(null);
    document.head.appendChild(script);
  });

interface Props {
  readonly routes: readonly MapRoute[];
  readonly bounds: Bounds | null;
  readonly originLabel: string;
  readonly destinationLabel: string;
  readonly onRouteClick?: (routeId: string) => void;
}

export const RouteMap = ({ routes, bounds, originLabel, destinationLabel }: Props) => {
  const container = useRef<HTMLDivElement>(null);
  const [tiles, setTiles] = useState<'idle' | 'loading' | 'ready' | 'unavailable'>(
    canRenderGoogleMap() ? 'loading' : 'unavailable',
  );

  /** Decoded once per route set, and reused by both renderers. */
  const decoded = useMemo<ShapeRoute[]>(
    () =>
      routes
        .map((route) => ({
          id: route.id,
          isSelected: route.isSelected,
          points: thin(decodePolyline(route.encodedPolyline ?? '')),
        }))
        .filter((route) => route.points.length > 1),
    [routes],
  );

  useEffect(() => {
    if (!canRenderGoogleMap() || container.current === null || decoded.length === 0) return;

    let cancelled = false;

    void (async () => {
      const maps = await loadGoogleMaps(mapsBrowserKey());
      if (cancelled) return;

      if (maps === null || container.current === null) {
        setTiles('unavailable');
        return;
      }

      const map = new maps.Map(container.current, {
        mapTypeControl: false,
        streetViewControl: false,
        fullscreenControl: false,
      });

      const box = new maps.LatLngBounds();

      for (const route of decoded) {
        new maps.Polyline({
          path: [...route.points],
          map,
          strokeOpacity: route.isSelected ? 0.95 : 0.4,
          strokeWeight: route.isSelected ? 6 : 4,
          zIndex: route.isSelected ? 2 : 1,
        });
        for (const point of route.points) box.extend(point);
      }

      const selected = decoded.find((r) => r.isSelected) ?? decoded[0];
      const start = selected?.points[0];
      const finish = selected?.points[selected.points.length - 1];
      if (start !== undefined) new maps.Marker({ position: start, map, title: originLabel });
      if (finish !== undefined) new maps.Marker({ position: finish, map, title: destinationLabel });

      map.fitBounds(box, 48);
      setTiles('ready');
    })();

    return () => {
      cancelled = true;
    };
  }, [decoded, originLabel, destinationLabel]);

  if (decoded.length === 0) return null;

  if (tiles === 'ready' || tiles === 'loading') {
    return (
      <div className="route-map">
        <div className="route-map__canvas" ref={container} aria-label="Map of your journey" />
        {tiles === 'loading' ? <p className="route-map__note">Loading the map…</p> : null}
      </div>
    );
  }

  return (
    <div className="route-map">
      <RouteShape
        routes={decoded}
        bounds={bounds}
        originLabel={originLabel}
        destinationLabel={destinationLabel}
      />
      {/*
        Said plainly and permanently, not as a transient error. A grey box with
        no explanation is the failure this module is meant to prevent; so is a
        drawing a reviewer might mistake for a map.
      */}
      <p className="route-map__note" role="note">
        <MapPinned size={15} aria-hidden="true" />
        <span>
          This is the real shape of your journey, drawn from its coordinates.{' '}
          <strong>Map tiles are not available in this build</strong> — they need a Google Maps key.
        </span>
      </p>
    </div>
  );
};
