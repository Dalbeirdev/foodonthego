/**
 * Turning the server's numbers into words.
 *
 * The server keeps metres and seconds and sends nothing formatted, which is the
 * right way round: a formatted string in the database is a decision that cannot
 * be re-made for another locale, and a client that received "278 km" could not
 * compare two routes.
 *
 * Everything here is presentation. Nothing rounds a value that another
 * calculation then uses.
 */

/**
 * Distance, in the unit the launch market reads.
 *
 * Under a kilometre stays in metres, rounded to the nearest fifty — a journey
 * planner claiming "347 m" implies a precision no routing provider has. Over a
 * kilometre gets one decimal below 10 km and none above, because "278.4 km" is
 * false precision on a figure that changes with the roadworks.
 */
export const formatDistance = (metres: number | null | undefined): string => {
  if (metres === null || metres === undefined || !Number.isFinite(metres)) return '—';
  if (metres < 1_000) return `${Math.max(0, Math.round(metres / 50) * 50)} m`;

  const km = metres / 1_000;
  return km < 10 ? `${km.toFixed(1)} km` : `${Math.round(km)} km`;
};

/**
 * Duration, as somebody would say it.
 *
 * "4 hr 32 min", not "4:32" — which reads as a clock time — and not
 * "272 minutes", which nobody converts in their head while driving.
 *
 * Rounded to the minute, and never to "0 min": a route that takes forty seconds
 * is "less than a minute", because zero reads as a failure to calculate.
 */
export const formatDuration = (seconds: number | null | undefined): string => {
  if (seconds === null || seconds === undefined || !Number.isFinite(seconds)) return '—';
  if (seconds < 60) return 'Less than a minute';

  const totalMinutes = Math.round(seconds / 60);
  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;

  if (hours === 0) return `${minutes} min`;
  if (minutes === 0) return `${hours} hr`;
  return `${hours} hr ${minutes} min`;
};

/**
 * The line under the travel time, or nothing at all.
 *
 * **Returns null when the provider gave no traffic figure**, and that is the
 * point of this function existing rather than a ternary at the call site. A
 * route planner that says "with current traffic" over a number the provider
 * computed without traffic is lying about the one thing a customer is trusting
 * it for, and it is an easy lie to tell by accident: `traffic ?? duration`
 * reads as a sensible default and produces exactly it.
 */
export const formatTrafficLine = (
  durationSeconds: number | null | undefined,
  trafficSeconds: number | null | undefined,
): string | null => {
  if (trafficSeconds === null || trafficSeconds === undefined || !Number.isFinite(trafficSeconds)) {
    return null;
  }

  const delta =
    durationSeconds !== null && durationSeconds !== undefined && Number.isFinite(durationSeconds)
      ? trafficSeconds - durationSeconds
      : 0;

  // Under two minutes either way is not a traffic story worth telling.
  if (Math.abs(delta) < 120) return `About ${formatDuration(trafficSeconds)} with current traffic`;

  return delta > 0
    ? `About ${formatDuration(trafficSeconds)} with current traffic — ${formatDuration(delta)} slower than usual`
    : `About ${formatDuration(trafficSeconds)} with current traffic — ${formatDuration(-delta)} quicker than usual`;
};

/**
 * How old the figures are, in the customer's terms.
 *
 * Shown because traffic is time-sensitive: a duration computed forty minutes
 * ago is not "current traffic", and the screen should not imply it is.
 */
export const formatCalculatedAt = (iso: string | null | undefined, now: Date): string | null => {
  if (iso === null || iso === undefined || iso === '') return null;

  const at = new Date(iso);
  if (Number.isNaN(at.getTime())) return null;

  const seconds = Math.max(0, Math.round((now.getTime() - at.getTime()) / 1_000));

  if (seconds < 90) return 'Worked out just now';
  if (seconds < 3_600) return `Worked out ${Math.round(seconds / 60)} min ago`;
  if (seconds < 86_400) {
    const hours = Math.round(seconds / 3_600);
    return `Worked out ${hours} hr ago`;
  }
  return 'Worked out more than a day ago';
};

/**
 * The customer-facing name for one option.
 *
 * "Fastest" is only claimed when this route really is the quickest of the set,
 * compared on the same basis for every option — traffic-aware figures where
 * every route has one, base duration otherwise. Comparing a traffic-aware
 * duration against a base one would hand the label to whichever route happened
 * to lack traffic data.
 */
export interface Comparable {
  readonly duration_seconds: number | null;
  readonly traffic_duration_seconds: number | null;
}

export const optionLabel = (
  route: Comparable,
  all: readonly Comparable[],
  index: number,
): string => {
  if (all.length <= 1) return 'Your route';

  const everyHasTraffic = all.every(
    (r) => r.traffic_duration_seconds !== null && Number.isFinite(r.traffic_duration_seconds),
  );

  const basis = (r: Comparable): number =>
    (everyHasTraffic ? r.traffic_duration_seconds : r.duration_seconds) ?? Number.POSITIVE_INFINITY;

  const quickest = Math.min(...all.map(basis));
  const ties = all.filter((r) => basis(r) === quickest).length;

  // A tie means no route is *the* fastest, so none of them says so.
  return basis(route) === quickest && ties === 1 ? 'Fastest' : `Route ${index + 1}`;
};
