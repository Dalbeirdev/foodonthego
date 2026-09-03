import { and, eq } from 'drizzle-orm';
import type { AddToCartInput, CartDto, CartLine, UpdateCartItemInput } from '@fotg/contracts';
import type { AppContext } from '../context.js';
import { cartItems, carts, menuItems, restaurants } from '../db/schema.js';
import { ApiError } from '../lib/errors.js';
import { newId } from '../lib/ids.js';
import { computeTotals } from '../lib/pricing.js';

const touch = async (ctx: AppContext, cartId: string): Promise<void> => {
  await ctx.db
    .update(carts)
    .set({ updatedAt: ctx.now().toISOString() })
    .where(eq(carts.id, cartId));
};

const findOrCreateCart = async (ctx: AppContext, userId: string) => {
  const [existing] = await ctx.db.select().from(carts).where(eq(carts.userId, userId));
  if (existing) return existing;

  const row = {
    id: newId(),
    userId,
    restaurantId: null,
    createdAt: ctx.now().toISOString(),
    updatedAt: ctx.now().toISOString(),
  };
  await ctx.db.insert(carts).values(row);
  return row;
};

/**
 * Builds the cart the customer sees, pricing every line from the menu *now* rather
 * than from whatever it cost when it was added. A cart can sit open for a day; the
 * figure on the checkout button has to be the figure that will be charged.
 */
export const getCart = async (ctx: AppContext, userId: string): Promise<CartDto> => {
  const cart = await findOrCreateCart(ctx, userId);

  const rows = await ctx.db
    .select({ item: cartItems, menuItem: menuItems })
    .from(cartItems)
    .innerJoin(menuItems, eq(cartItems.menuItemId, menuItems.id))
    .where(eq(cartItems.cartId, cart.id));

  const lines: CartLine[] = rows.map(({ item, menuItem }) => ({
    id: item.id,
    menuItemId: menuItem.id,
    name: menuItem.name,
    unitPriceCents: menuItem.priceCents,
    quantity: item.quantity,
    notes: item.notes,
    lineTotalCents: menuItem.priceCents * item.quantity,
    isAvailable: menuItem.isAvailable,
  }));

  let restaurantName: string | null = null;
  let deliveryFeeCents = 0;
  let minimumOrderCents = 0;

  if (cart.restaurantId) {
    const [restaurant] = await ctx.db
      .select()
      .from(restaurants)
      .where(eq(restaurants.id, cart.restaurantId));
    if (restaurant) {
      restaurantName = restaurant.name;
      deliveryFeeCents = restaurant.deliveryFeeCents;
      minimumOrderCents = restaurant.minimumOrderCents;
    }
  }

  // Unavailable lines are shown, so the customer can see what has gone, but they are
  // not priced in — charging for a dish the kitchen has run out of would be worse
  // than the surprise of the total changing.
  const priceable = lines.filter((line) => line.isAvailable);
  const totals = computeTotals(priceable, priceable.length > 0 ? deliveryFeeCents : 0, 0, ctx.config);

  return {
    id: cart.id,
    restaurantId: cart.restaurantId,
    restaurantName,
    lines,
    totals,
    minimumOrderCents,
    meetsMinimum: totals.subtotalCents >= minimumOrderCents,
  };
};

export const addToCart = async (
  ctx: AppContext,
  userId: string,
  input: AddToCartInput,
): Promise<CartDto> => {
  const [menuItem] = await ctx.db.select().from(menuItems).where(eq(menuItems.id, input.menuItemId));
  if (!menuItem) throw ApiError.notFound('Menu item');
  if (!menuItem.isAvailable) {
    throw ApiError.conflict('That item is not available right now.', { menuItemId: menuItem.id });
  }

  const [restaurant] = await ctx.db
    .select()
    .from(restaurants)
    .where(eq(restaurants.id, menuItem.restaurantId));
  if (!restaurant || !restaurant.isActive) throw ApiError.notFound('Restaurant');

  const cart = await findOrCreateCart(ctx, userId);

  if (cart.restaurantId && cart.restaurantId !== menuItem.restaurantId) {
    // Refused rather than silently emptied. Wiping a cart the customer spent five
    // minutes building because they tapped one dish elsewhere is a worse outcome
    // than an error the UI can turn into "start a new order?".
    throw ApiError.conflict(
      'Your cart has items from another restaurant. Empty it before ordering from this one.',
      { currentRestaurantId: cart.restaurantId, requestedRestaurantId: menuItem.restaurantId },
    );
  }

  if (!cart.restaurantId) {
    await ctx.db
      .update(carts)
      .set({ restaurantId: menuItem.restaurantId })
      .where(eq(carts.id, cart.id));
  }

  // Same dish with the same note is one line with a bigger number, not two lines.
  const [existing] = await ctx.db
    .select()
    .from(cartItems)
    .where(and(eq(cartItems.cartId, cart.id), eq(cartItems.menuItemId, menuItem.id)));

  if (existing && (existing.notes ?? null) === (input.notes ?? null)) {
    await ctx.db
      .update(cartItems)
      .set({ quantity: Math.min(existing.quantity + input.quantity, 50) })
      .where(eq(cartItems.id, existing.id));
  } else {
    await ctx.db.insert(cartItems).values({
      id: newId(),
      cartId: cart.id,
      menuItemId: menuItem.id,
      quantity: input.quantity,
      notes: input.notes ?? null,
      createdAt: ctx.now().toISOString(),
    });
  }

  await touch(ctx, cart.id);
  return getCart(ctx, userId);
};

export const updateCartItem = async (
  ctx: AppContext,
  userId: string,
  cartItemId: string,
  input: UpdateCartItemInput,
): Promise<CartDto> => {
  const cart = await findOrCreateCart(ctx, userId);

  const [existing] = await ctx.db
    .select()
    .from(cartItems)
    .where(and(eq(cartItems.id, cartItemId), eq(cartItems.cartId, cart.id)));
  if (!existing) throw ApiError.notFound('Cart item');

  if (input.quantity === 0) {
    await ctx.db.delete(cartItems).where(eq(cartItems.id, existing.id));
  } else {
    await ctx.db
      .update(cartItems)
      .set({ quantity: input.quantity, notes: input.notes ?? existing.notes })
      .where(eq(cartItems.id, existing.id));
  }

  await clearRestaurantIfEmpty(ctx, cart.id);
  await touch(ctx, cart.id);
  return getCart(ctx, userId);
};

export const removeCartItem = async (
  ctx: AppContext,
  userId: string,
  cartItemId: string,
): Promise<CartDto> => updateCartItem(ctx, userId, cartItemId, { quantity: 0 });

export const clearCart = async (ctx: AppContext, userId: string): Promise<CartDto> => {
  const cart = await findOrCreateCart(ctx, userId);
  await ctx.db.delete(cartItems).where(eq(cartItems.cartId, cart.id));
  await ctx.db.update(carts).set({ restaurantId: null }).where(eq(carts.id, cart.id));
  await touch(ctx, cart.id);
  return getCart(ctx, userId);
};

/**
 * An empty cart must forget which restaurant it belonged to, or the customer is
 * locked out of every other restaurant by a cart with nothing in it.
 */
const clearRestaurantIfEmpty = async (ctx: AppContext, cartId: string): Promise<void> => {
  const remaining = await ctx.db.select({ id: cartItems.id }).from(cartItems).where(eq(cartItems.cartId, cartId));
  if (remaining.length === 0) {
    await ctx.db.update(carts).set({ restaurantId: null }).where(eq(carts.id, cartId));
  }
};
