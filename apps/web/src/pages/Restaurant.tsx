import { useEffect, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { formatCents, formatWindow, type MenuItemDto, type RestaurantDetail } from '@fotg/contracts';
import { api, ApiRequestError } from '../api/client.js';
import { useAuth } from '../state/auth.js';
import { useCart } from '../state/cart.js';
import { Banner, Empty, Money, Spinner } from '../components/ui.js';

export const Restaurant = () => {
  const { id = '' } = useParams();
  const navigate = useNavigate();
  const { user } = useAuth();
  const { add, cart, isLoading: cartBusy } = useCart();

  const [restaurant, setRestaurant] = useState<RestaurantDetail | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [conflict, setConflict] = useState(false);

  useEffect(() => {
    api
      .restaurant(id)
      .then(setRestaurant)
      .catch((caught: unknown) =>
        setError(caught instanceof ApiRequestError ? caught.message : 'Could not load this restaurant.'),
      );
  }, [id]);

  const addItem = async (item: MenuItemDto) => {
    if (!user) {
      navigate(`/login?next=${encodeURIComponent(`/restaurants/${id}`)}`);
      return;
    }
    setConflict(false);
    setNotice(null);
    try {
      await add(item.id);
      setNotice(`${item.name} added to your order.`);
    } catch (caught) {
      // The one error worth handling specially: a cart already holding another
      // restaurant's food. The customer is offered the choice rather than having it
      // made for them.
      if (caught instanceof ApiRequestError && caught.code === 'conflict') {
        setConflict(true);
        return;
      }
      setError(caught instanceof ApiRequestError ? caught.message : 'Could not add that item.');
    }
  };

  if (error && !restaurant) {
    return (
      <div className="page container">
        <Empty icon="🚪" title="We could not find that restaurant">
          {error} <Link to="/">Back to all restaurants</Link>
        </Empty>
      </div>
    );
  }

  if (!restaurant) {
    return (
      <div className="page container">
        <Spinner label="Loading the menu" />
      </div>
    );
  }

  return (
    <div className="page container">
      <div className="stack-sm">
        <Link to="/" className="faint" style={{ textDecoration: 'none' }}>
          ← All restaurants
        </Link>
        <div className="spread">
          <h1>{restaurant.name}</h1>
          <span className={`badge ${restaurant.isOpenNow ? 'badge-open' : 'badge-closed'}`}>
            {restaurant.isOpenNow ? 'Open now' : 'Closed'}
          </span>
        </div>
        {restaurant.description ? <p className="muted">{restaurant.description}</p> : null}
        <div className="row faint">
          <span style={{ textTransform: 'capitalize' }}>{restaurant.cuisine}</span>
          <span aria-hidden="true">·</span>
          <span>
            {restaurant.ratingAverage === null
              ? 'No ratings yet'
              : `★ ${restaurant.ratingAverage.toFixed(1)} (${restaurant.ratingCount} reviews)`}
          </span>
          <span aria-hidden="true">·</span>
          <span>~{restaurant.prepTimeMinutes} min</span>
          <span aria-hidden="true">·</span>
          <span>{formatCents(restaurant.deliveryFeeCents)} delivery</span>
          {restaurant.minimumOrderCents > 0 ? (
            <>
              <span aria-hidden="true">·</span>
              <span>{formatCents(restaurant.minimumOrderCents)} minimum</span>
            </>
          ) : null}
        </div>
      </div>

      {conflict ? (
        <Banner tone="info">
          Your cart already has food from {cart?.restaurantName ?? 'another restaurant'}. One order comes from
          one kitchen — <Link to="/cart">review your cart</Link> to empty it first.
        </Banner>
      ) : null}
      {notice ? <Banner tone="success">{notice}</Banner> : null}
      {error ? <Banner>{error}</Banner> : null}
      {!restaurant.isOpenNow ? (
        <Banner tone="info">
          This kitchen is closed right now. You can still look at the menu — ordering opens when they do.
        </Banner>
      ) : null}

      <div className="layout-split">
        <div className="stack">
          {restaurant.menu.length === 0 ? (
            <Empty icon="📋" title="This menu is empty">
              The restaurant has not published any dishes yet.
            </Empty>
          ) : (
            restaurant.menu.map((category) => (
              <section key={category.id} className="card stack-sm">
                <h2>{category.name}</h2>
                {category.description ? <p className="faint">{category.description}</p> : null}
                <div>
                  {category.items.map((item) => (
                    <article
                      key={item.id}
                      className={`menu-item${item.isAvailable ? '' : ' menu-item-unavailable'}`}
                    >
                      <div className="stack-sm">
                        <h3>{item.name}</h3>
                        {item.description ? <p className="muted">{item.description}</p> : null}
                        {item.dietaryTags.length > 0 ? (
                          <div className="row" style={{ gap: '0.35rem' }}>
                            {item.dietaryTags.map((tag) => (
                              <span key={tag} className="badge">
                                {tag.replace(/_/g, ' ')}
                              </span>
                            ))}
                          </div>
                        ) : null}
                      </div>
                      <div className="stack-sm" style={{ justifyItems: 'end' }}>
                        <Money cents={item.priceCents} />
                        <button
                          type="button"
                          className="button-secondary"
                          disabled={!item.isAvailable || !restaurant.isOpenNow || cartBusy}
                          onClick={() => void addItem(item)}
                        >
                          {item.isAvailable ? 'Add' : 'Sold out'}
                        </button>
                      </div>
                    </article>
                  ))}
                </div>
              </section>
            ))
          )}
        </div>

        <aside className="sticky-aside">
          <div className="card stack-sm">
            <h3>Opening hours</h3>
            {restaurant.openingHours.length === 0 ? (
              <p className="faint">No hours published.</p>
            ) : (
              <ul className="stack-sm" style={{ listStyle: 'none', padding: 0, margin: 0 }}>
                {restaurant.openingHours.map((window, index) => (
                  <li key={`${window.weekday}-${window.opensMinute}-${index}`} className="faint">
                    {formatWindow(window)}
                  </li>
                ))}
              </ul>
            )}
          </div>
          <div className="card stack-sm">
            <h3>Where they are</h3>
            <p className="faint">
              {restaurant.addressLine1}
              <br />
              {restaurant.city}, {restaurant.region} {restaurant.postalCode}
            </p>
            {restaurant.phone ? <p className="faint">{restaurant.phone}</p> : null}
          </div>
        </aside>
      </div>
    </div>
  );
};
