import { useCallback, useEffect, useState } from 'react';
import { formatCents, type MenuCategoryWithItems, type RestaurantSummary } from '@fotg/contracts';
import { api, ApiRequestError } from '../api/client.js';
import { Banner, Empty, Spinner } from '../components/ui.js';

/**
 * The restaurant owner's menu view. Deliberately small: it does the one thing a
 * kitchen needs to do mid-service — take a dish off the menu when it runs out —
 * rather than pretending to be a full menu editor it is not yet.
 */
export const Manage = () => {
  const [restaurants, setRestaurants] = useState<RestaurantSummary[] | null>(null);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [menu, setMenu] = useState<MenuCategoryWithItems[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busyItemId, setBusyItemId] = useState<string | null>(null);

  useEffect(() => {
    api
      .ownedRestaurants()
      .then((list) => {
        setRestaurants(list);
        setSelectedId((current) => current ?? list[0]?.id ?? null);
      })
      .catch((caught: unknown) =>
        setError(caught instanceof ApiRequestError ? caught.message : 'Could not load your restaurants.'),
      );
  }, []);

  const loadMenu = useCallback(async (restaurantId: string) => {
    try {
      setMenu(await api.ownedMenu(restaurantId));
      setError(null);
    } catch (caught) {
      setError(caught instanceof ApiRequestError ? caught.message : 'Could not load that menu.');
    }
  }, []);

  useEffect(() => {
    if (selectedId) void loadMenu(selectedId);
  }, [selectedId, loadMenu]);

  const toggle = async (itemId: string, isAvailable: boolean) => {
    setBusyItemId(itemId);
    try {
      await api.setItemAvailability(itemId, isAvailable);
      if (selectedId) await loadMenu(selectedId);
    } catch (caught) {
      setError(caught instanceof ApiRequestError ? caught.message : 'Could not update that dish.');
    } finally {
      setBusyItemId(null);
    }
  };

  if (error && !restaurants) {
    return (
      <div className="page container">
        <h1>Your restaurants</h1>
        <Banner>{error}</Banner>
      </div>
    );
  }

  if (!restaurants) {
    return (
      <div className="page container">
        <h1>Your restaurants</h1>
        <Spinner label="Loading your restaurants" />
      </div>
    );
  }

  if (restaurants.length === 0) {
    return (
      <div className="page container">
        <h1>Your restaurants</h1>
        <Empty icon="🏪" title="You have no restaurants yet">
          Creating one is available through the API (<code>POST /api/manage/restaurants</code>); a form for it
          is not built yet.
        </Empty>
      </div>
    );
  }

  return (
    <div className="page container">
      <h1>Your restaurants</h1>
      {error ? <Banner>{error}</Banner> : null}

      {restaurants.length > 1 ? (
        <label style={{ maxWidth: 320 }}>
          Restaurant
          <select value={selectedId ?? ''} onChange={(event) => setSelectedId(event.target.value)}>
            {restaurants.map((restaurant) => (
              <option key={restaurant.id} value={restaurant.id}>
                {restaurant.name}
              </option>
            ))}
          </select>
        </label>
      ) : null}

      {!menu ? (
        <Spinner label="Loading the menu" />
      ) : (
        <div className="stack">
          {menu.map((category) => (
            <section key={category.id} className="card stack-sm">
              <h2>{category.name}</h2>
              <div className="table-scroll">
                <table>
                  <thead>
                    <tr>
                      <th scope="col">Dish</th>
                      <th scope="col">Price</th>
                      <th scope="col">On the menu</th>
                      <th scope="col">
                        <span className="visually-hidden">Actions</span>
                      </th>
                    </tr>
                  </thead>
                  <tbody>
                    {category.items.map((item) => (
                      <tr key={item.id}>
                        <td>{item.name}</td>
                        <td className="price">{formatCents(item.priceCents)}</td>
                        <td>
                          <span className={`badge ${item.isAvailable ? 'badge-open' : 'badge-closed'}`}>
                            {item.isAvailable ? 'Available' : 'Sold out'}
                          </span>
                        </td>
                        <td>
                          <button
                            type="button"
                            className="button-secondary"
                            disabled={busyItemId === item.id}
                            onClick={() => void toggle(item.id, !item.isAvailable)}
                          >
                            {item.isAvailable ? 'Mark sold out' : 'Put back on'}
                          </button>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </section>
          ))}
        </div>
      )}
    </div>
  );
};
