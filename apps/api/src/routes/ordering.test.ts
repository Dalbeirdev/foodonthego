import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { createHarness, makeAdmin, registerActor, type ActorSession, type TestHarness } from '../testing/harness.js';
import { addToCart, placeOrder, seedRestaurant, setStatus, type SeededRestaurant } from '../testing/fixtures.js';

let harness: TestHarness;
let restaurant: SeededRestaurant;
let customer: ActorSession;

beforeEach(async () => {
  harness = await createHarness();
  restaurant = await seedRestaurant(harness);
  customer = await registerActor(harness, { role: 'customer' });
});
afterEach(async () => {
  await harness.close();
});

describe('cart', () => {
  it('starts empty and totals zero', async () => {
    const response = await harness.app.inject({ method: 'GET', url: '/api/cart', headers: customer.headers });
    expect(response.statusCode).toBe(200);
    expect(response.json().lines).toEqual([]);
    expect(response.json().totals.totalCents).toBe(0);
  });

  it('prices a line and charges delivery once, not per item', async () => {
    await addToCart(harness, customer, restaurant.itemIds[0]!, 2);
    const cart = (await harness.app.inject({ method: 'GET', url: '/api/cart', headers: customer.headers })).json();

    expect(cart.totals.subtotalCents).toBe(2500);
    expect(cart.totals.deliveryFeeCents).toBe(299);
    expect(cart.lines).toHaveLength(1);
    expect(cart.lines[0].quantity).toBe(2);
  });

  it('merges a repeat of the same dish into one line', async () => {
    await addToCart(harness, customer, restaurant.itemIds[0]!, 1);
    await addToCart(harness, customer, restaurant.itemIds[0]!, 2);

    const cart = (await harness.app.inject({ method: 'GET', url: '/api/cart', headers: customer.headers })).json();
    expect(cart.lines).toHaveLength(1);
    expect(cart.lines[0].quantity).toBe(3);
  });

  it('refuses to mix two restaurants instead of silently emptying the cart', async () => {
    const other = await seedRestaurant(harness);
    await addToCart(harness, customer, restaurant.itemIds[0]!, 1);

    const response = await addToCart(harness, customer, other.itemIds[0]!, 1);
    expect(response.statusCode).toBe(409);

    // And the original cart survives, which is the point.
    const cart = (await harness.app.inject({ method: 'GET', url: '/api/cart', headers: customer.headers })).json();
    expect(cart.lines).toHaveLength(1);
    expect(cart.restaurantId).toBe(restaurant.restaurantId);
  });

  it('forgets the restaurant once the last line is removed, so another can be chosen', async () => {
    await addToCart(harness, customer, restaurant.itemIds[0]!, 1);
    const cart = (await harness.app.inject({ method: 'GET', url: '/api/cart', headers: customer.headers })).json();

    await harness.app.inject({
      method: 'DELETE',
      url: `/api/cart/items/${cart.lines[0].id}`,
      headers: customer.headers,
    });

    const emptied = (await harness.app.inject({ method: 'GET', url: '/api/cart', headers: customer.headers })).json();
    expect(emptied.restaurantId).toBeNull();

    const other = await seedRestaurant(harness);
    expect((await addToCart(harness, customer, other.itemIds[0]!, 1)).statusCode).toBe(201);
  });

  it('treats a quantity of zero as removal', async () => {
    await addToCart(harness, customer, restaurant.itemIds[0]!, 3);
    const cart = (await harness.app.inject({ method: 'GET', url: '/api/cart', headers: customer.headers })).json();

    const response = await harness.app.inject({
      method: 'PATCH',
      url: `/api/cart/items/${cart.lines[0].id}`,
      headers: customer.headers,
      payload: { quantity: 0 },
    });
    expect(response.statusCode).toBe(200);
    expect(response.json().lines).toEqual([]);
  });

  it('will not let one customer touch another customer’s cart line', async () => {
    await addToCart(harness, customer, restaurant.itemIds[0]!, 1);
    const cart = (await harness.app.inject({ method: 'GET', url: '/api/cart', headers: customer.headers })).json();

    const intruder = await registerActor(harness, { role: 'customer' });
    const response = await harness.app.inject({
      method: 'PATCH',
      url: `/api/cart/items/${cart.lines[0].id}`,
      headers: intruder.headers,
      // A quantity the schema accepts, so the request actually reaches the
      // ownership check rather than being turned away as malformed.
      payload: { quantity: 2 },
    });
    expect(response.statusCode).toBe(404);
  });

  it('refuses an unavailable dish', async () => {
    await harness.app.inject({
      method: 'PATCH',
      url: `/api/manage/items/${restaurant.itemIds[0]}`,
      headers: restaurant.owner.headers,
      payload: { isAvailable: false },
    });

    const response = await addToCart(harness, customer, restaurant.itemIds[0]!, 1);
    expect(response.statusCode).toBe(409);
  });
});

describe('placing an order', () => {
  it('turns the cart into an order and empties it', async () => {
    await addToCart(harness, customer, restaurant.itemIds[0]!, 2);

    const response = await placeOrder(harness, customer, { tipCents: 500 });
    expect(response.statusCode).toBe(201);

    const order = response.json();
    expect(order.status).toBe('pending');
    expect(order.reference).toMatch(/^[23456789A-HJ-NP-Z]{8}$/);
    expect(order.totals.subtotalCents).toBe(2500);
    expect(order.totals.tipCents).toBe(500);
    expect(order.lines).toHaveLength(1);
    expect(order.events).toHaveLength(1);

    const cart = (await harness.app.inject({ method: 'GET', url: '/api/cart', headers: customer.headers })).json();
    expect(cart.lines).toEqual([]);
    expect(cart.restaurantId).toBeNull();
  });

  it('refuses an empty cart', async () => {
    const response = await placeOrder(harness, customer);
    expect(response.statusCode).toBe(422);
  });

  it('refuses when the total moved under the customer’s feet', async () => {
    await addToCart(harness, customer, restaurant.itemIds[0]!, 1);

    const response = await placeOrder(harness, customer, { expectedTotalCents: 1 });
    expect(response.statusCode).toBe(409);
    expect(response.json().error.details.actualTotalCents).toBeGreaterThan(1);
  });

  it('accepts when the expected total is right', async () => {
    await addToCart(harness, customer, restaurant.itemIds[0]!, 1);
    const cart = (await harness.app.inject({ method: 'GET', url: '/api/cart', headers: customer.headers })).json();

    const response = await placeOrder(harness, customer, { expectedTotalCents: cart.totals.totalCents });
    expect(response.statusCode).toBe(201);
  });

  it('enforces the restaurant minimum', async () => {
    const pricey = await seedRestaurant(harness, { minimumOrderCents: 5000, prices: [1000] });
    const hungry = await registerActor(harness, { role: 'customer' });
    await addToCart(harness, hungry, pricey.itemIds[0]!, 1);

    const response = await placeOrder(harness, hungry);
    expect(response.statusCode).toBe(422);
    expect(response.json().error.details.minimumOrderCents).toBe(5000);
  });

  it('snapshots the price, so a later menu change does not rewrite the receipt', async () => {
    await addToCart(harness, customer, restaurant.itemIds[0]!, 1);
    const order = (await placeOrder(harness, customer)).json();

    await harness.app.inject({
      method: 'PATCH',
      url: `/api/manage/items/${restaurant.itemIds[0]}`,
      headers: restaurant.owner.headers,
      payload: { priceCents: 9999, name: 'Renamed Dish' },
    });

    const reread = (
      await harness.app.inject({ method: 'GET', url: `/api/orders/${order.id}`, headers: customer.headers })
    ).json();
    expect(reread.lines[0].unitPriceCents).toBe(1250);
    expect(reread.lines[0].name).toBe('Dish 1');
    expect(reread.totals.totalCents).toBe(order.totals.totalCents);
  });

  it('leaves no order behind when the cart contains something unavailable', async () => {
    await addToCart(harness, customer, restaurant.itemIds[0]!, 1);
    await harness.app.inject({
      method: 'PATCH',
      url: `/api/manage/items/${restaurant.itemIds[0]}`,
      headers: restaurant.owner.headers,
      payload: { isAvailable: false },
    });

    expect((await placeOrder(harness, customer)).statusCode).toBe(409);

    const orders = (await harness.app.inject({ method: 'GET', url: '/api/orders', headers: customer.headers })).json();
    expect(orders.items).toEqual([]);
    // The cart is untouched too, so the customer can fix it rather than rebuild it.
    const cart = (await harness.app.inject({ method: 'GET', url: '/api/cart', headers: customer.headers })).json();
    expect(cart.lines).toHaveLength(1);
  });
});

describe('order lifecycle', () => {
  const placeOne = async () => {
    await addToCart(harness, customer, restaurant.itemIds[0]!, 1);
    return (await placeOrder(harness, customer)).json();
  };

  it('runs the happy path from pending to delivered', async () => {
    const order = await placeOne();
    const courier = await registerActor(harness, { role: 'courier' });

    expect((await setStatus(harness, restaurant.owner, order.id, 'confirmed')).statusCode).toBe(200);
    expect((await setStatus(harness, restaurant.owner, order.id, 'preparing')).statusCode).toBe(200);
    expect((await setStatus(harness, restaurant.owner, order.id, 'ready_for_pickup')).statusCode).toBe(200);
    expect((await setStatus(harness, courier, order.id, 'out_for_delivery')).statusCode).toBe(200);

    const delivered = await setStatus(harness, courier, order.id, 'delivered');
    expect(delivered.statusCode).toBe(200);
    expect(delivered.json().status).toBe('delivered');
    expect(delivered.json().courierId).toBe(courier.userId);
    // One event per transition, plus the placement itself.
    expect(delivered.json().events).toHaveLength(6);
    expect(delivered.json().allowedNextStatuses).toEqual([]);
  });

  it('will not let a customer confirm their own order', async () => {
    const order = await placeOne();
    const response = await setStatus(harness, customer, order.id, 'confirmed');
    expect(response.statusCode).toBe(409);
  });

  it('lets a customer cancel while pending but not once it is being cooked', async () => {
    const first = await placeOne();
    expect((await setStatus(harness, customer, first.id, 'cancelled')).statusCode).toBe(200);

    const second = await placeOne();
    await setStatus(harness, restaurant.owner, second.id, 'confirmed');
    await setStatus(harness, restaurant.owner, second.id, 'preparing');

    const tooLate = await setStatus(harness, customer, second.id, 'cancelled');
    expect(tooLate.statusCode).toBe(409);
    expect(tooLate.json().error.details.actor).toBe('customer');
  });

  it('refuses to skip a step', async () => {
    const order = await placeOne();
    const response = await setStatus(harness, restaurant.owner, order.id, 'delivered');
    expect(response.statusCode).toBe(409);
    expect(response.json().error.details.from).toBe('pending');
  });

  it('refuses to move an order that has already finished', async () => {
    const order = await placeOne();
    await setStatus(harness, customer, order.id, 'cancelled');

    for (const status of ['confirmed', 'preparing', 'delivered']) {
      expect((await setStatus(harness, restaurant.owner, order.id, status)).statusCode).toBe(409);
    }
  });

  it('hides an order from a restaurant that has nothing to do with it', async () => {
    const order = await placeOne();
    const stranger = await seedRestaurant(harness);

    const read = await harness.app.inject({
      method: 'GET',
      url: `/api/orders/${order.id}`,
      headers: stranger.owner.headers,
    });
    expect(read.statusCode).toBe(404);
    expect((await setStatus(harness, stranger.owner, order.id, 'confirmed')).statusCode).toBe(404);
  });

  it('hides an order from an unrelated customer', async () => {
    const order = await placeOne();
    const nosy = await registerActor(harness, { role: 'customer' });

    const response = await harness.app.inject({
      method: 'GET',
      url: `/api/orders/${order.id}`,
      headers: nosy.headers,
    });
    expect(response.statusCode).toBe(404);
  });

  it('tells each party only what they may do next', async () => {
    const order = await placeOne();

    const asCustomer = (
      await harness.app.inject({ method: 'GET', url: `/api/orders/${order.id}`, headers: customer.headers })
    ).json();
    expect(asCustomer.allowedNextStatuses).toEqual(['cancelled']);

    const asOwner = (
      await harness.app.inject({
        method: 'GET',
        url: `/api/orders/${order.id}`,
        headers: restaurant.owner.headers,
      })
    ).json();
    expect(asOwner.allowedNextStatuses).toEqual(expect.arrayContaining(['confirmed', 'rejected']));
    expect(asOwner.allowedNextStatuses).not.toContain('cancelled');
  });

  it('records who did what, with the reason', async () => {
    const order = await placeOne();
    await setStatus(harness, restaurant.owner, order.id, 'rejected', 'Kitchen closed early');

    const reread = (
      await harness.app.inject({ method: 'GET', url: `/api/orders/${order.id}`, headers: customer.headers })
    ).json();
    const rejection = reread.events.at(-1);
    expect(rejection.status).toBe('rejected');
    expect(rejection.actor).toBe('restaurant');
    expect(rejection.reason).toBe('Kitchen closed early');
  });

  it('lets an admin move an order any way the table allows', async () => {
    const order = await placeOne();
    const adminUser = await registerActor(harness, { role: 'customer' });
    const admin = await makeAdmin(harness, adminUser.userId);

    expect((await setStatus(harness, admin, order.id, 'confirmed')).statusCode).toBe(200);
    expect((await setStatus(harness, admin, order.id, 'cancelled')).statusCode).toBe(200);
  });
});

describe('order lists', () => {
  it('shows a customer only their own orders', async () => {
    await addToCart(harness, customer, restaurant.itemIds[0]!, 1);
    await placeOrder(harness, customer);

    const other = await registerActor(harness, { role: 'customer' });
    await addToCart(harness, other, restaurant.itemIds[1]!, 1);
    await placeOrder(harness, other);

    const mine = (await harness.app.inject({ method: 'GET', url: '/api/orders', headers: customer.headers })).json();
    expect(mine.items).toHaveLength(1);
    expect(mine.total).toBe(1);
    expect(mine.items[0].customerId).toBe(customer.userId);
  });

  it('shows a restaurant every order placed with it', async () => {
    await addToCart(harness, customer, restaurant.itemIds[0]!, 1);
    await placeOrder(harness, customer);

    const other = await registerActor(harness, { role: 'customer' });
    await addToCart(harness, other, restaurant.itemIds[1]!, 1);
    await placeOrder(harness, other);

    const queue = (
      await harness.app.inject({ method: 'GET', url: '/api/orders', headers: restaurant.owner.headers })
    ).json();
    expect(queue.items).toHaveLength(2);
  });

  it('shows a courier the unclaimed queue', async () => {
    await addToCart(harness, customer, restaurant.itemIds[0]!, 1);
    const order = (await placeOrder(harness, customer)).json();
    const courier = await registerActor(harness, { role: 'courier' });

    const beforeReady = (
      await harness.app.inject({ method: 'GET', url: '/api/orders', headers: courier.headers })
    ).json();
    expect(beforeReady.items).toHaveLength(0);

    await setStatus(harness, restaurant.owner, order.id, 'confirmed');
    await setStatus(harness, restaurant.owner, order.id, 'preparing');
    await setStatus(harness, restaurant.owner, order.id, 'ready_for_pickup');

    const afterReady = (
      await harness.app.inject({ method: 'GET', url: '/api/orders', headers: courier.headers })
    ).json();
    expect(afterReady.items).toHaveLength(1);
    expect(afterReady.items[0].id).toBe(order.id);
  });
});
