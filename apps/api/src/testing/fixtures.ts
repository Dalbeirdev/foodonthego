import type { TestHarness, ActorSession } from './harness.js';
import { registerActor } from './harness.js';

export interface SeededRestaurant {
  owner: ActorSession;
  restaurantId: string;
  categoryId: string;
  itemIds: string[];
}

/**
 * Builds a restaurant with a menu through the real management API rather than by
 * writing rows, so the fixtures exercise the same validation a real owner would hit.
 */
export const seedRestaurant = async (
  harness: TestHarness,
  overrides: { deliveryFeeCents?: number; minimumOrderCents?: number; prices?: number[] } = {},
): Promise<SeededRestaurant> => {
  const owner = await registerActor(harness, { role: 'restaurant_owner' });

  const restaurantResponse = await harness.app.inject({
    method: 'POST',
    url: '/api/manage/restaurants',
    headers: owner.headers,
    payload: {
      name: 'The Test Kitchen',
      description: 'A restaurant that exists for assertions.',
      cuisine: 'italian',
      addressLine1: '1 Test Street',
      city: 'Springfield',
      region: 'IL',
      postalCode: '62701',
      deliveryFeeCents: overrides.deliveryFeeCents ?? 299,
      minimumOrderCents: overrides.minimumOrderCents ?? 0,
      prepTimeMinutes: 25,
    },
  });
  if (restaurantResponse.statusCode !== 201) {
    throw new Error(`seedRestaurant failed: ${restaurantResponse.statusCode} ${restaurantResponse.body}`);
  }
  const restaurantId = (restaurantResponse.json() as { id: string }).id;

  const categoryResponse = await harness.app.inject({
    method: 'POST',
    url: `/api/manage/restaurants/${restaurantId}/categories`,
    headers: owner.headers,
    payload: { name: 'Mains', sortOrder: 0 },
  });
  const categoryId = (categoryResponse.json() as { id: string }).id;

  const prices = overrides.prices ?? [1250, 899];
  const itemIds: string[] = [];

  for (const [index, priceCents] of prices.entries()) {
    const itemResponse = await harness.app.inject({
      method: 'POST',
      url: `/api/manage/restaurants/${restaurantId}/items`,
      headers: owner.headers,
      payload: {
        categoryId,
        name: `Dish ${index + 1}`,
        description: 'Edible.',
        priceCents,
        sortOrder: index,
      },
    });
    if (itemResponse.statusCode !== 201) {
      throw new Error(`seed item failed: ${itemResponse.statusCode} ${itemResponse.body}`);
    }
    itemIds.push((itemResponse.json() as { id: string }).id);
  }

  return { owner, restaurantId, categoryId, itemIds };
};

export const addToCart = (harness: TestHarness, actor: ActorSession, menuItemId: string, quantity = 1) =>
  harness.app.inject({
    method: 'POST',
    url: '/api/cart/items',
    headers: actor.headers,
    payload: { menuItemId, quantity },
  });

export const placeOrder = (
  harness: TestHarness,
  actor: ActorSession,
  payload: Record<string, unknown> = {},
) =>
  harness.app.inject({
    method: 'POST',
    url: '/api/orders',
    headers: actor.headers,
    payload: {
      address: { line1: '9 Customer Way', city: 'Springfield', region: 'IL', postalCode: '62704' },
      ...payload,
    },
  });

export const setStatus = (
  harness: TestHarness,
  actor: ActorSession,
  orderId: string,
  status: string,
  reason?: string,
) =>
  harness.app.inject({
    method: 'POST',
    url: `/api/orders/${orderId}/status`,
    headers: actor.headers,
    payload: { status, ...(reason ? { reason } : {}) },
  });
