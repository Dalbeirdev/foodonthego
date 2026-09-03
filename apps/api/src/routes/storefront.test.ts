import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { createHarness, registerActor, type TestHarness } from '../testing/harness.js';
import { seedRestaurant } from '../testing/fixtures.js';
import { openingHours, restaurants } from '../db/schema.js';
import { eq } from 'drizzle-orm';
import { newId } from '../lib/ids.js';

let harness: TestHarness;

beforeEach(async () => {
  harness = await createHarness();
});
afterEach(async () => {
  await harness.close();
});

describe('GET /api/restaurants', () => {
  it('lists active restaurants without needing a sign-in', async () => {
    await seedRestaurant(harness);

    const response = await harness.app.inject({ method: 'GET', url: '/api/restaurants' });
    expect(response.statusCode).toBe(200);
    expect(response.json().items).toHaveLength(1);
    expect(response.json().total).toBe(1);
  });

  it('hides a deactivated restaurant from customers', async () => {
    const seeded = await seedRestaurant(harness);
    await harness.ctx.db
      .update(restaurants)
      .set({ isActive: false })
      .where(eq(restaurants.id, seeded.restaurantId));

    const list = await harness.app.inject({ method: 'GET', url: '/api/restaurants' });
    expect(list.json().items).toEqual([]);

    const detail = await harness.app.inject({ method: 'GET', url: `/api/restaurants/${seeded.restaurantId}` });
    expect(detail.statusCode).toBe(404);
  });

  it('searches by name and by cuisine', async () => {
    await seedRestaurant(harness);

    const hit = await harness.app.inject({ method: 'GET', url: '/api/restaurants?q=Test%20Kitchen' });
    expect(hit.json().items).toHaveLength(1);

    const miss = await harness.app.inject({ method: 'GET', url: '/api/restaurants?q=nothing-matches-this' });
    expect(miss.json().items).toEqual([]);

    const byCuisine = await harness.app.inject({ method: 'GET', url: '/api/restaurants?cuisine=italian' });
    expect(byCuisine.json().items).toHaveLength(1);

    const wrongCuisine = await harness.app.inject({ method: 'GET', url: '/api/restaurants?cuisine=thai' });
    expect(wrongCuisine.json().items).toEqual([]);
  });

  it('treats a LIKE wildcard in the query as a literal character', async () => {
    await seedRestaurant(harness);
    // Unescaped, '%' would match everything; escaped, it matches nothing here.
    const response = await harness.app.inject({ method: 'GET', url: '/api/restaurants?q=%25' });
    expect(response.json().items).toEqual([]);
  });

  it('rejects a cuisine that is not on the list rather than ignoring it', async () => {
    const response = await harness.app.inject({ method: 'GET', url: '/api/restaurants?cuisine=not-a-cuisine' });
    expect(response.statusCode).toBe(400);
  });

  it('filters by delivery fee', async () => {
    await seedRestaurant(harness, { deliveryFeeCents: 199 });
    await seedRestaurant(harness, { deliveryFeeCents: 899 });

    const cheap = await harness.app.inject({ method: 'GET', url: '/api/restaurants?maxDeliveryFee=500' });
    expect(cheap.json().items).toHaveLength(1);
    expect(cheap.json().items[0].deliveryFeeCents).toBe(199);
  });

  it('sorts by delivery fee when asked', async () => {
    await seedRestaurant(harness, { deliveryFeeCents: 899 });
    await seedRestaurant(harness, { deliveryFeeCents: 199 });
    await seedRestaurant(harness, { deliveryFeeCents: 499 });

    const response = await harness.app.inject({ method: 'GET', url: '/api/restaurants?sort=delivery_fee' });
    const fees = response.json().items.map((item: { deliveryFeeCents: number }) => item.deliveryFeeCents);
    expect(fees).toEqual([199, 499, 899]);
  });

  it('pages', async () => {
    for (let index = 0; index < 3; index += 1) await seedRestaurant(harness);

    const firstPage = await harness.app.inject({ method: 'GET', url: '/api/restaurants?limit=2&offset=0' });
    expect(firstPage.json().items).toHaveLength(2);
    expect(firstPage.json().total).toBe(3);

    const secondPage = await harness.app.inject({ method: 'GET', url: '/api/restaurants?limit=2&offset=2' });
    expect(secondPage.json().items).toHaveLength(1);
  });
});

describe('open now', () => {
  const setHours = async (restaurantId: string, weekday: number, opens: number, closes: number) => {
    await harness.ctx.db.insert(openingHours).values({
      id: newId(),
      restaurantId,
      weekday,
      opensMinute: opens,
      closesMinute: closes,
    });
  };

  it('reports a restaurant as closed when nothing is scheduled', async () => {
    const seeded = await seedRestaurant(harness);
    const response = await harness.app.inject({ method: 'GET', url: '/api/restaurants' });
    expect(response.json().items[0].isOpenNow).toBe(false);
    expect(response.json().items[0].id).toBe(seeded.restaurantId);
  });

  it('reports open, and filters on it, against the injected clock', async () => {
    const seeded = await seedRestaurant(harness);
    // The harness clock is 2024-05-15T12:00:00Z — a Wednesday.
    const noon = new Date('2024-05-15T12:00:00.000Z');
    await setHours(seeded.restaurantId, noon.getDay(), noon.getHours() * 60 - 60, noon.getHours() * 60 + 60);

    const open = await harness.app.inject({ method: 'GET', url: '/api/restaurants?openNow=true' });
    expect(open.json().items).toHaveLength(1);
    expect(open.json().items[0].isOpenNow).toBe(true);

    // Move the clock past closing and the same restaurant drops out.
    harness.setNow(new Date(noon.getTime() + 4 * 60 * 60 * 1000));
    const closed = await harness.app.inject({ method: 'GET', url: '/api/restaurants?openNow=true' });
    expect(closed.json().items).toEqual([]);
  });
});

describe('GET /api/restaurants/:id', () => {
  it('returns the menu grouped into categories', async () => {
    const seeded = await seedRestaurant(harness);

    const response = await harness.app.inject({ method: 'GET', url: `/api/restaurants/${seeded.restaurantId}` });
    expect(response.statusCode).toBe(200);

    const body = response.json();
    expect(body.menu).toHaveLength(1);
    expect(body.menu[0].name).toBe('Mains');
    expect(body.menu[0].items).toHaveLength(2);
    expect(body.menu[0].items[0].priceCents).toBe(1250);
  });

  it('hides an unavailable dish from customers but shows it to the owner', async () => {
    const seeded = await seedRestaurant(harness);
    await harness.app.inject({
      method: 'PATCH',
      url: `/api/manage/items/${seeded.itemIds[0]}`,
      headers: seeded.owner.headers,
      payload: { isAvailable: false },
    });

    const publicView = await harness.app.inject({ method: 'GET', url: `/api/restaurants/${seeded.restaurantId}` });
    expect(publicView.json().menu[0].items).toHaveLength(1);

    const ownerView = await harness.app.inject({
      method: 'GET',
      url: `/api/manage/restaurants/${seeded.restaurantId}/menu`,
      headers: seeded.owner.headers,
    });
    expect(ownerView.json()[0].items).toHaveLength(2);
  });

  it('404s on an id that is not a restaurant, and 400s on one that is not an id', async () => {
    const missing = await harness.app.inject({
      method: 'GET',
      url: '/api/restaurants/11111111-1111-4111-8111-111111111111',
    });
    expect(missing.statusCode).toBe(404);

    const malformed = await harness.app.inject({ method: 'GET', url: '/api/restaurants/not-a-uuid' });
    expect(malformed.statusCode).toBe(400);
  });
});

describe('menu management', () => {
  it('will not let one owner edit another owner’s menu', async () => {
    const mine = await seedRestaurant(harness);
    const theirs = await seedRestaurant(harness);

    const patch = await harness.app.inject({
      method: 'PATCH',
      url: `/api/manage/items/${theirs.itemIds[0]}`,
      headers: mine.owner.headers,
      payload: { priceCents: 1 },
    });
    expect(patch.statusCode).toBe(404);

    const remove = await harness.app.inject({
      method: 'DELETE',
      url: `/api/manage/items/${theirs.itemIds[0]}`,
      headers: mine.owner.headers,
    });
    expect(remove.statusCode).toBe(404);
  });

  it('will not file a dish under another restaurant’s category', async () => {
    const mine = await seedRestaurant(harness);
    const theirs = await seedRestaurant(harness);

    const response = await harness.app.inject({
      method: 'POST',
      url: `/api/manage/restaurants/${mine.restaurantId}/items`,
      headers: mine.owner.headers,
      payload: { categoryId: theirs.categoryId, name: 'Smuggled', priceCents: 100 },
    });
    expect(response.statusCode).toBe(400);
  });

  it('refuses a customer trying to run a restaurant', async () => {
    const customer = await registerActor(harness, { role: 'customer' });

    const response = await harness.app.inject({
      method: 'POST',
      url: '/api/manage/restaurants',
      headers: customer.headers,
      payload: {
        name: 'Not Mine',
        cuisine: 'pizza',
        addressLine1: '1 St',
        city: 'Springfield',
        region: 'IL',
        postalCode: '62701',
      },
    });
    expect(response.statusCode).toBe(403);
  });

  it('shows an owner only their own restaurants', async () => {
    const mine = await seedRestaurant(harness);
    await seedRestaurant(harness);

    const response = await harness.app.inject({
      method: 'GET',
      url: '/api/manage/restaurants',
      headers: mine.owner.headers,
    });
    expect(response.json()).toHaveLength(1);
    expect(response.json()[0].id).toBe(mine.restaurantId);
  });
});

describe('health', () => {
  it('answers live and ready separately', async () => {
    expect((await harness.app.inject({ method: 'GET', url: '/health/live' })).statusCode).toBe(200);

    const ready = await harness.app.inject({ method: 'GET', url: '/health/ready' });
    expect(ready.statusCode).toBe(200);
    expect(ready.json().database).toBe('ok');
  });

  it('404s an unknown route with a usable message', async () => {
    const response = await harness.app.inject({ method: 'GET', url: '/api/nope' });
    expect(response.statusCode).toBe(404);
    expect(response.json().error.code).toBe('not_found');
  });
});
