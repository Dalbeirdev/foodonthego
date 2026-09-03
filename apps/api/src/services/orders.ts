import { and, desc, eq, inArray, isNull, or, sql, type SQL } from 'drizzle-orm';
import {
  allowedTransitions,
  canTransition,
  type OrderActor,
  type OrderDto,
  type OrderStatus,
  type Paginated,
  type PlaceOrderInput,
  type UpdateOrderStatusInput,
} from '@fotg/contracts';
import type { AuthenticatedUser } from '../auth.js';
import type { AppContext } from '../context.js';
import {
  cartItems,
  carts,
  menuItems,
  orderEvents,
  orderItems,
  orders,
  restaurants,
  users,
} from '../db/schema.js';
import { ApiError } from '../lib/errors.js';
import { newId, newOrderReference } from '../lib/ids.js';
import { computeTotals } from '../lib/pricing.js';

type OrderRow = typeof orders.$inferSelect;

/**
 * Turns a signed-in user into their role *on a specific order*, which is not the
 * same as their role on the platform: a restaurant owner is `restaurant` on their
 * own orders and nothing at all on anybody else's.
 */
export const actorFor = (order: OrderRow, user: AuthenticatedUser, ownsRestaurant: boolean): OrderActor | null => {
  if (user.role === 'admin') return 'admin';
  if (order.customerId === user.id) return 'customer';
  if (ownsRestaurant) return 'restaurant';
  if (user.role === 'courier' && (order.courierId === null || order.courierId === user.id)) {
    return 'courier';
  }
  return null;
};

export const placeOrder = async (
  ctx: AppContext,
  user: AuthenticatedUser,
  input: PlaceOrderInput,
): Promise<OrderDto> => {
  const [cart] = await ctx.db.select().from(carts).where(eq(carts.userId, user.id));
  if (!cart || !cart.restaurantId) throw ApiError.unprocessable('Your cart is empty.');

  const [restaurant] = await ctx.db
    .select()
    .from(restaurants)
    .where(eq(restaurants.id, cart.restaurantId));
  if (!restaurant || !restaurant.isActive) {
    throw ApiError.conflict('That restaurant is no longer taking orders.');
  }

  const rows = await ctx.db
    .select({ item: cartItems, menuItem: menuItems })
    .from(cartItems)
    .innerJoin(menuItems, eq(cartItems.menuItemId, menuItems.id))
    .where(eq(cartItems.cartId, cart.id));

  if (rows.length === 0) throw ApiError.unprocessable('Your cart is empty.');

  const unavailable = rows.filter(({ menuItem }) => !menuItem.isAvailable);
  if (unavailable.length > 0) {
    throw ApiError.conflict('Some items are no longer available. Review your cart and try again.', {
      unavailableItems: unavailable.map(({ menuItem }) => ({ id: menuItem.id, name: menuItem.name })),
    });
  }

  const lines = rows.map(({ item, menuItem }) => ({
    menuItemId: menuItem.id,
    name: menuItem.name,
    unitPriceCents: menuItem.priceCents,
    quantity: item.quantity,
    notes: item.notes,
    lineTotalCents: menuItem.priceCents * item.quantity,
  }));

  const totals = computeTotals(lines, restaurant.deliveryFeeCents, input.tipCents, ctx.config);

  if (totals.subtotalCents < restaurant.minimumOrderCents) {
    throw ApiError.unprocessable(
      `This restaurant has a minimum order of ${(restaurant.minimumOrderCents / 100).toFixed(2)}.`,
      { minimumOrderCents: restaurant.minimumOrderCents, subtotalCents: totals.subtotalCents },
    );
  }

  /**
   * The client tells us what it last showed the customer. If a price moved while
   * the cart was open, the order is refused rather than placed at the new figure —
   * the customer gets an error and sees the new total, instead of a charge they
   * never agreed to. It is optional so a scripted client can opt out knowingly.
   */
  if (input.expectedTotalCents !== undefined && input.expectedTotalCents !== totals.totalCents) {
    throw ApiError.conflict('Prices changed while you were ordering. Please review your order.', {
      expectedTotalCents: input.expectedTotalCents,
      actualTotalCents: totals.totalCents,
    });
  }

  const placedAt = ctx.now();
  const estimatedReadyAt = new Date(placedAt.getTime() + restaurant.prepTimeMinutes * 60_000);
  const orderId = newId();

  insertOrderTransactionally(ctx, {
    orderId,
    reference: newOrderReference(),
    cartId: cart.id,
    user,
    restaurant,
    lines,
    totals,
    input,
    placedAt,
    estimatedReadyAt,
  });

  return getOrder(ctx, orderId, user);
};

interface InsertOrderArgs {
  orderId: string;
  reference: string;
  cartId: string;
  user: AuthenticatedUser;
  restaurant: typeof restaurants.$inferSelect;
  lines: Array<{
    menuItemId: string;
    name: string;
    unitPriceCents: number;
    quantity: number;
    notes: string | null;
    lineTotalCents: number;
  }>;
  totals: ReturnType<typeof computeTotals>;
  input: PlaceOrderInput;
  placedAt: Date;
  estimatedReadyAt: Date;
}

/**
 * Writes the order, its lines, its first event and the emptying of the cart as one
 * unit. Without the transaction, a failure halfway leaves a customer with an order
 * they cannot see and a cart they have already paid for — the classic double-charge
 * shape. `better-sqlite3` is synchronous, so this is a real transaction rather than
 * an interleaved one.
 */
const insertOrderTransactionally = (ctx: AppContext, args: InsertOrderArgs): void => {
  const { orderId, reference, cartId, user, restaurant, lines, totals, input, placedAt, estimatedReadyAt } = args;
  const timestamp = placedAt.toISOString();

  // The callback is synchronous on purpose. `better-sqlite3` is a synchronous
  // driver, and it rejects a transaction function that returns a promise — an
  // `async` callback here would throw at runtime, and worse, any statement after
  // the first `await` would run outside the transaction it looked like it was in.
  // Every statement below therefore ends in `.run()` rather than being awaited.
  ctx.db.transaction((tx) => {
    tx.insert(orders).values({
      id: orderId,
      reference,
      customerId: user.id,
      restaurantId: restaurant.id,
      courierId: null,
      status: 'pending',
      subtotalCents: totals.subtotalCents,
      deliveryFeeCents: totals.deliveryFeeCents,
      serviceFeeCents: totals.serviceFeeCents,
      taxCents: totals.taxCents,
      tipCents: totals.tipCents,
      totalCents: totals.totalCents,
      addressLabel: input.address.label,
      addressLine1: input.address.line1,
      addressLine2: input.address.line2 ?? null,
      addressCity: input.address.city,
      addressRegion: input.address.region,
      addressPostalCode: input.address.postalCode,
      addressLatitude: input.address.latitude ?? null,
      addressLongitude: input.address.longitude ?? null,
      deliveryNotes: input.address.deliveryNotes ?? null,
      customerNotes: input.customerNotes ?? null,
      estimatedReadyAt: estimatedReadyAt.toISOString(),
      placedAt: timestamp,
      updatedAt: timestamp,
    }).run();

    for (const line of lines) {
      tx.insert(orderItems).values({
        id: newId(),
        orderId,
        menuItemId: line.menuItemId,
        name: line.name,
        unitPriceCents: line.unitPriceCents,
        quantity: line.quantity,
        notes: line.notes,
        lineTotalCents: line.lineTotalCents,
      }).run();
    }

    tx.insert(orderEvents).values({
      id: newId(),
      orderId,
      status: 'pending',
      actor: 'customer',
      actorUserId: user.id,
      reason: null,
      createdAt: timestamp,
    }).run();

    tx.delete(cartItems).where(eq(cartItems.cartId, cartId)).run();
    tx.update(carts).set({ restaurantId: null, updatedAt: timestamp }).where(eq(carts.id, cartId)).run();
  });
};

const ownsRestaurantFor = async (ctx: AppContext, order: OrderRow, user: AuthenticatedUser): Promise<boolean> => {
  if (user.role !== 'restaurant_owner') return false;
  const [restaurant] = await ctx.db
    .select({ ownerId: restaurants.ownerId })
    .from(restaurants)
    .where(eq(restaurants.id, order.restaurantId));
  return restaurant?.ownerId === user.id;
};

export const getOrder = async (
  ctx: AppContext,
  orderId: string,
  user: AuthenticatedUser,
): Promise<OrderDto> => {
  const [order] = await ctx.db.select().from(orders).where(eq(orders.id, orderId));
  if (!order) throw ApiError.notFound('Order');

  const ownsRestaurant = await ownsRestaurantFor(ctx, order, user);
  const actor = actorFor(order, user, ownsRestaurant);
  // A courier who has not taken this order can still read it — that is how they
  // decide whether to — but nobody else outside the three parties can.
  if (!actor) throw ApiError.notFound('Order');

  return hydrateOrder(ctx, order, actor);
};

const hydrateOrder = async (ctx: AppContext, order: OrderRow, actor: OrderActor): Promise<OrderDto> => {
  const [lines, events, [restaurant], [customer]] = await Promise.all([
    ctx.db.select().from(orderItems).where(eq(orderItems.orderId, order.id)),
    ctx.db.select().from(orderEvents).where(eq(orderEvents.orderId, order.id)).orderBy(orderEvents.createdAt),
    ctx.db.select({ name: restaurants.name }).from(restaurants).where(eq(restaurants.id, order.restaurantId)),
    ctx.db.select({ name: users.fullName }).from(users).where(eq(users.id, order.customerId)),
  ]);

  const status = order.status as OrderStatus;

  return {
    id: order.id,
    reference: order.reference,
    status,
    restaurantId: order.restaurantId,
    restaurantName: restaurant?.name ?? 'Unknown restaurant',
    customerId: order.customerId,
    customerName: customer?.name ?? 'Unknown customer',
    courierId: order.courierId,
    lines: lines.map((line) => ({
      id: line.id,
      menuItemId: line.menuItemId,
      name: line.name,
      unitPriceCents: line.unitPriceCents,
      quantity: line.quantity,
      notes: line.notes,
      lineTotalCents: line.lineTotalCents,
    })),
    totals: {
      subtotalCents: order.subtotalCents,
      deliveryFeeCents: order.deliveryFeeCents,
      serviceFeeCents: order.serviceFeeCents,
      taxCents: order.taxCents,
      tipCents: order.tipCents,
      totalCents: order.totalCents,
    },
    deliveryAddress: {
      label: order.addressLabel,
      line1: order.addressLine1,
      line2: order.addressLine2,
      city: order.addressCity,
      region: order.addressRegion,
      postalCode: order.addressPostalCode,
      deliveryNotes: order.deliveryNotes,
    },
    customerNotes: order.customerNotes,
    estimatedReadyAt: order.estimatedReadyAt,
    placedAt: order.placedAt,
    updatedAt: order.updatedAt,
    events: events.map((event) => ({
      id: event.id,
      status: event.status as OrderStatus,
      actor: event.actor,
      reason: event.reason,
      createdAt: event.createdAt,
    })),
    // What *this* caller can do next, so the UI shows a button only when pressing it
    // would work. The server checks again on the way in regardless.
    allowedNextStatuses: allowedTransitions(status).filter((next) =>
      canTransition(status, next, actor),
    ),
  };
};

export const updateOrderStatus = async (
  ctx: AppContext,
  orderId: string,
  user: AuthenticatedUser,
  input: UpdateOrderStatusInput,
): Promise<OrderDto> => {
  const [order] = await ctx.db.select().from(orders).where(eq(orders.id, orderId));
  if (!order) throw ApiError.notFound('Order');

  const ownsRestaurant = await ownsRestaurantFor(ctx, order, user);
  const actor = actorFor(order, user, ownsRestaurant);
  if (!actor) throw ApiError.notFound('Order');

  const from = order.status as OrderStatus;
  if (from === input.status) {
    throw ApiError.conflict(`This order is already ${from}.`);
  }
  if (!canTransition(from, input.status, actor)) {
    throw ApiError.conflict(`An order that is ${from} cannot be moved to ${input.status} by a ${actor}.`, {
      from,
      to: input.status,
      actor,
      allowed: allowedTransitions(from).filter((next) => canTransition(from, next, actor)),
    });
  }

  const timestamp = ctx.now().toISOString();

  // Synchronous for the same reason as `insertOrderTransactionally` above.
  ctx.db.transaction((tx) => {
    // The status is re-checked inside the write. Two couriers tapping "picked up" at
    // the same moment both pass the check above; only the one whose UPDATE still
    // matches the status it read gets to change the row.
    const result = tx
      .update(orders)
      .set({
        status: input.status,
        updatedAt: timestamp,
        // Taking an order out for delivery is also how a courier claims it.
        ...(input.status === 'out_for_delivery' && actor === 'courier' ? { courierId: user.id } : {}),
      })
      .where(and(eq(orders.id, orderId), eq(orders.status, from)))
      .run();

    if (result.changes === 0) {
      throw ApiError.conflict('This order was updated by somebody else. Reload and try again.');
    }

    tx.insert(orderEvents).values({
      id: newId(),
      orderId,
      status: input.status,
      actor,
      actorUserId: user.id,
      reason: input.reason ?? null,
      createdAt: timestamp,
    }).run();
  });

  return getOrder(ctx, orderId, user);
};

export interface ListOrdersOptions {
  status?: OrderStatus[];
  limit: number;
  offset: number;
}

/** The order list, scoped by who is asking: your orders, your restaurant's, or your deliveries. */
export const listOrders = async (
  ctx: AppContext,
  user: AuthenticatedUser,
  options: ListOrdersOptions,
): Promise<Paginated<OrderDto>> => {
  const filters: SQL[] = [];

  if (user.role === 'customer') {
    filters.push(eq(orders.customerId, user.id));
  } else if (user.role === 'restaurant_owner') {
    const owned = await ctx.db
      .select({ id: restaurants.id })
      .from(restaurants)
      .where(eq(restaurants.ownerId, user.id));
    if (owned.length === 0) return { items: [], total: 0, limit: options.limit, offset: options.offset };
    filters.push(inArray(orders.restaurantId, owned.map((row) => row.id)));
  } else if (user.role === 'courier') {
    // A courier sees two things: the unclaimed queue they could pick up, and
    // everything they are already carrying. `isNull` matters here — `courier_id = NULL`
    // is never true in SQL, so comparing with `eq` would hide the whole queue.
    const claimable = and(eq(orders.status, 'ready_for_pickup'), isNull(orders.courierId));
    const mine = eq(orders.courierId, user.id);
    const visible = or(claimable, mine);
    if (visible) filters.push(visible);
  }
  // An admin gets no filter at all, which is the point of being an admin.

  if (options.status && options.status.length > 0) {
    filters.push(inArray(orders.status, options.status));
  }

  const where = filters.length > 0 ? and(...filters) : undefined;

  const rows = await ctx.db
    .select()
    .from(orders)
    .where(where)
    .orderBy(desc(orders.placedAt))
    .limit(options.limit)
    .offset(options.offset);

  const items = await Promise.all(
    rows.map(async (order) => {
      const ownsRestaurant = await ownsRestaurantFor(ctx, order, user);
      const actor = actorFor(order, user, ownsRestaurant) ?? 'customer';
      return hydrateOrder(ctx, order, actor);
    }),
  );

  // Counted against the same filter rather than reported as `items.length`, which
  // would silently equal the page size and make every list look like one page.
  const [{ count } = { count: 0 }] = await ctx.db
    .select({ count: sql<number>`count(*)` })
    .from(orders)
    .where(where);

  return { items, total: count, limit: options.limit, offset: options.offset };
};
