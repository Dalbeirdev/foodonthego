/**
 * What is on screen while the app works out who you are.
 *
 * Deliberately not a spinner in the middle of nothing: it is the shape of the
 * screen that is about to appear, so the first paint and the second are the
 * same layout and nothing jumps.
 */
import { Skeleton } from '@fotg/ui';

export const AppLoading = () => (
  <div className="home" aria-busy="true" aria-live="polite">
    <span className="sr-only">Loading FoodOnTheGo</span>
    <div className="home__greeting">
      <Skeleton width="60%" height="2rem" />
      <Skeleton width="40%" height="1rem" />
    </div>
    <Skeleton height="9rem" />
    <Skeleton height="7rem" />
  </div>
);
