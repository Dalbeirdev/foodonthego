import { useEffect, useMemo, useState } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { CUISINES, formatCents, type Paginated, type RestaurantSummary } from '@fotg/contracts';
import { api, ApiRequestError } from '../api/client.js';
import { Banner, CuisineTile, Empty, Spinner } from '../components/ui.js';

const RestaurantCard = ({ restaurant }: { restaurant: RestaurantSummary }) => (
  // Deliberately not `aria-disabled` when closed: the link works, and the menu of a
  // closed kitchen is worth reading. Saying otherwise would tell a screen-reader
  // user the link is broken when it is not. The badge carries the meaning instead.
  <Link to={`/restaurants/${restaurant.id}`} className="restaurant-card" data-closed={!restaurant.isOpenNow}>
    <div className="restaurant-card-head">
      <CuisineTile cuisine={restaurant.cuisine} />
      <h3>{restaurant.name}</h3>
      <span className={`badge ${restaurant.isOpenNow ? 'badge-open' : 'badge-closed'}`}>
        {restaurant.isOpenNow ? 'Open' : 'Closed'}
      </span>
    </div>
    {restaurant.description ? <p className="muted">{restaurant.description}</p> : null}
    {/*
      Rendered as one list with CSS-drawn separators rather than as separator
      elements between spans: a wrapped flex row leaves a stray "·" hanging at the
      end of a line, and `:last-child` cannot know where a line broke.
    */}
    <ul className="meta faint">
      <li style={{ textTransform: 'capitalize' }}>{restaurant.cuisine}</li>
      <li>{restaurant.ratingAverage === null ? 'New' : `★ ${restaurant.ratingAverage.toFixed(1)}`}</li>
      <li>{restaurant.prepTimeMinutes} min</li>
      <li>{restaurant.deliveryFeeCents === 0 ? 'Free delivery' : formatCents(restaurant.deliveryFeeCents)}</li>
    </ul>
  </Link>
);

export const Browse = () => {
  const [params, setParams] = useSearchParams();
  const [result, setResult] = useState<Paginated<RestaurantSummary> | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const query = params.get('q') ?? '';
  const cuisine = params.get('cuisine') ?? '';
  const sort = params.get('sort') ?? 'relevance';
  const openNow = params.get('openNow') === 'true';

  // A debounced copy of the text field, so typing does not fire a request per keystroke.
  const [draftQuery, setDraftQuery] = useState(query);
  useEffect(() => {
    const timer = window.setTimeout(() => {
      setParams(
        (previous) => {
          const next = new URLSearchParams(previous);
          if (draftQuery) next.set('q', draftQuery);
          else next.delete('q');
          return next;
        },
        { replace: true },
      );
    }, 250);
    return () => window.clearTimeout(timer);
  }, [draftQuery, setParams]);

  const requestParams = useMemo(() => {
    const next = new URLSearchParams();
    if (query) next.set('q', query);
    if (cuisine) next.set('cuisine', cuisine);
    if (sort) next.set('sort', sort);
    if (openNow) next.set('openNow', 'true');
    next.set('limit', '24');
    return next;
  }, [query, cuisine, sort, openNow]);

  useEffect(() => {
    // Aborted on change so a slow earlier request cannot land after a faster later
    // one and repaint the list with stale results.
    const controller = new AbortController();
    setIsLoading(true);

    api
      .restaurants(requestParams, controller.signal)
      .then((response) => {
        setResult(response);
        setError(null);
      })
      .catch((caught: unknown) => {
        if ((caught as Error).name === 'AbortError') return;
        setError(caught instanceof ApiRequestError ? caught.message : 'Could not load restaurants.');
      })
      .finally(() => {
        if (!controller.signal.aborted) setIsLoading(false);
      });

    return () => controller.abort();
  }, [requestParams]);

  const update = (key: string, value: string) => {
    setParams((previous) => {
      const next = new URLSearchParams(previous);
      if (value) next.set(key, value);
      else next.delete(key);
      return next;
    });
  };

  return (
    <div className="page container">
      <div className="stack-sm">
        <h1>Order food near you</h1>
        <p className="muted">Four kitchens, cooking now. Delivery is quoted before you pay.</p>
      </div>

      <div className="filters">
        <label className="search">
          Search
          <input
            type="search"
            value={draftQuery}
            onChange={(event) => setDraftQuery(event.target.value)}
            placeholder="Pizza, pho, a restaurant name…"
          />
        </label>
        <label>
          Cuisine
          <select value={cuisine} onChange={(event) => update('cuisine', event.target.value)}>
            <option value="">Any</option>
            {CUISINES.map((option) => (
              <option key={option} value={option}>
                {option.replace(/_/g, ' ')}
              </option>
            ))}
          </select>
        </label>
        <label>
          Sort by
          <select value={sort} onChange={(event) => update('sort', event.target.value)}>
            <option value="relevance">Most reviewed</option>
            <option value="rating">Highest rated</option>
            <option value="delivery_fee">Cheapest delivery</option>
            <option value="prep_time">Fastest</option>
          </select>
        </label>
        <button
          type="button"
          className={openNow ? 'button-primary' : 'button-secondary'}
          aria-pressed={openNow}
          onClick={() => update('openNow', openNow ? '' : 'true')}
        >
          Open now
        </button>
      </div>

      {error ? <Banner>{error}</Banner> : null}

      {isLoading && !result ? (
        <Spinner label="Loading restaurants" />
      ) : result && result.items.length > 0 ? (
        <>
          <p className="faint" role="status">
            {result.items.length} {result.items.length === 1 ? 'restaurant' : 'restaurants'}
            {openNow ? ' open now' : ''}
          </p>
          <div className="grid-restaurants">
            {result.items.map((restaurant) => (
              <RestaurantCard key={restaurant.id} restaurant={restaurant} />
            ))}
          </div>
        </>
      ) : (
        <Empty icon="🍜" title="Nothing matches that">
          Try a different search, or clear the filters.
        </Empty>
      )}
    </div>
  );
};
