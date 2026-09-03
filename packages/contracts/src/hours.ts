/**
 * Opening hours, and the one question the storefront actually asks of them:
 * is this place open right now?
 *
 * Hours are stored as minutes from midnight in the restaurant's own local day.
 * A window whose closing minute is less than or equal to its opening minute runs
 * past midnight — 18:00 to 02:00 is `{ opensMinute: 1080, closesMinute: 120 }` —
 * which is the case a naive `opens <= now && now < closes` comparison gets wrong,
 * and it is exactly the case a late-night restaurant lives in.
 */
export interface OpeningWindow {
  /** 0 = Sunday, matching `Date.prototype.getDay`. */
  weekday: number;
  opensMinute: number;
  closesMinute: number;
}

export const MINUTES_PER_DAY = 24 * 60;

export const minuteOfDay = (date: Date): number => date.getHours() * 60 + date.getMinutes();

const previousWeekday = (weekday: number): number => (weekday + 6) % 7;

export const isOpenAt = (windows: readonly OpeningWindow[], at: Date): boolean => {
  const weekday = at.getDay();
  const minute = minuteOfDay(at);

  for (const window of windows) {
    const overnight = window.closesMinute <= window.opensMinute;

    if (!overnight) {
      if (window.weekday === weekday && minute >= window.opensMinute && minute < window.closesMinute) {
        return true;
      }
      continue;
    }

    // The evening half of an overnight window falls on its own weekday...
    if (window.weekday === weekday && minute >= window.opensMinute) {
      return true;
    }
    // ...and the small-hours half belongs to yesterday's window.
    if (window.weekday === previousWeekday(weekday) && minute < window.closesMinute) {
      return true;
    }
  }

  return false;
};

const WEEKDAY_NAMES = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'] as const;

const formatMinute = (minute: number): string => {
  const normalised = ((minute % MINUTES_PER_DAY) + MINUTES_PER_DAY) % MINUTES_PER_DAY;
  const hours = Math.floor(normalised / 60);
  const minutes = normalised % 60;
  return `${String(hours).padStart(2, '0')}:${String(minutes).padStart(2, '0')}`;
};

export const formatWindow = (window: OpeningWindow): string =>
  `${WEEKDAY_NAMES[window.weekday] ?? '???'} ${formatMinute(window.opensMinute)}–${formatMinute(window.closesMinute)}`;
