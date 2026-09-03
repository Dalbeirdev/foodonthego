import { eq } from 'drizzle-orm';
import type {
  Cuisine,
  MenuCategoryInput,
  MenuItemDto,
  MenuItemInput,
  RestaurantInput,
  RestaurantSummary,
} from '@fotg/contracts';
import type { AuthenticatedUser } from '../auth.js';
import type { AppContext } from '../context.js';
import { menuCategories, menuItems, restaurants } from '../db/schema.js';
import { ApiError } from '../lib/errors.js';
import { newId } from '../lib/ids.js';
import { requireOwnedRestaurant } from './restaurants.js';

const toSummary = (row: typeof restaurants.$inferSelect): RestaurantSummary => ({
  id: row.id,
  name: row.name,
  description: row.description,
  cuisine: row.cuisine as Cuisine,
  city: row.city,
  region: row.region,
  imageUrl: row.imageUrl,
  deliveryFeeCents: row.deliveryFeeCents,
  minimumOrderCents: row.minimumOrderCents,
  prepTimeMinutes: row.prepTimeMinutes,
  ratingAverage: row.ratingCount === 0 ? null : Math.round((row.ratingSum / row.ratingCount) * 10) / 10,
  ratingCount: row.ratingCount,
  isActive: row.isActive,
  isOpenNow: false,
});

export const createRestaurant = async (
  ctx: AppContext,
  user: AuthenticatedUser,
  input: RestaurantInput,
): Promise<RestaurantSummary> => {
  const timestamp = ctx.now().toISOString();
  const row = {
    id: newId(),
    ownerId: user.id,
    name: input.name,
    description: input.description ?? null,
    cuisine: input.cuisine,
    phone: input.phone ?? null,
    addressLine1: input.addressLine1,
    city: input.city,
    region: input.region,
    postalCode: input.postalCode,
    latitude: input.latitude ?? null,
    longitude: input.longitude ?? null,
    deliveryFeeCents: input.deliveryFeeCents,
    minimumOrderCents: input.minimumOrderCents,
    prepTimeMinutes: input.prepTimeMinutes,
    imageUrl: input.imageUrl ?? null,
    isActive: input.isActive,
    ratingSum: 0,
    ratingCount: 0,
    createdAt: timestamp,
    updatedAt: timestamp,
  };

  await ctx.db.insert(restaurants).values(row);
  return toSummary(row);
};

export const listOwnedRestaurants = async (
  ctx: AppContext,
  user: AuthenticatedUser,
): Promise<RestaurantSummary[]> => {
  const rows =
    user.role === 'admin'
      ? await ctx.db.select().from(restaurants)
      : await ctx.db.select().from(restaurants).where(eq(restaurants.ownerId, user.id));

  return rows.map(toSummary);
};

export const createCategory = async (
  ctx: AppContext,
  user: AuthenticatedUser,
  restaurantId: string,
  input: MenuCategoryInput,
) => {
  await requireOwnedRestaurant(ctx, restaurantId, user);

  const row = {
    id: newId(),
    restaurantId,
    name: input.name,
    description: input.description ?? null,
    sortOrder: input.sortOrder,
    createdAt: ctx.now().toISOString(),
  };

  await ctx.db.insert(menuCategories).values(row);
  return row;
};

const toItemDto = (row: typeof menuItems.$inferSelect): MenuItemDto => ({
  id: row.id,
  categoryId: row.categoryId,
  name: row.name,
  description: row.description,
  priceCents: row.priceCents,
  imageUrl: row.imageUrl,
  dietaryTags: JSON.parse(row.dietaryTags) as MenuItemDto['dietaryTags'],
  isAvailable: row.isAvailable,
  sortOrder: row.sortOrder,
});

export const createMenuItem = async (
  ctx: AppContext,
  user: AuthenticatedUser,
  restaurantId: string,
  input: MenuItemInput,
): Promise<MenuItemDto> => {
  await requireOwnedRestaurant(ctx, restaurantId, user);

  const [category] = await ctx.db
    .select()
    .from(menuCategories)
    .where(eq(menuCategories.id, input.categoryId));
  // Without this the owner of one restaurant could file a dish under a category
  // belonging to another, and it would appear on somebody else's menu.
  if (!category || category.restaurantId !== restaurantId) {
    throw ApiError.badRequest('That category does not belong to this restaurant.');
  }

  const timestamp = ctx.now().toISOString();
  const row = {
    id: newId(),
    restaurantId,
    categoryId: input.categoryId,
    name: input.name,
    description: input.description ?? null,
    priceCents: input.priceCents,
    imageUrl: input.imageUrl ?? null,
    dietaryTags: JSON.stringify(input.dietaryTags),
    isAvailable: input.isAvailable,
    sortOrder: input.sortOrder,
    createdAt: timestamp,
    updatedAt: timestamp,
  };

  await ctx.db.insert(menuItems).values(row);
  return toItemDto(row);
};

export const updateMenuItem = async (
  ctx: AppContext,
  user: AuthenticatedUser,
  itemId: string,
  input: Partial<MenuItemInput>,
): Promise<MenuItemDto> => {
  const [existing] = await ctx.db.select().from(menuItems).where(eq(menuItems.id, itemId));
  if (!existing) throw ApiError.notFound('Menu item');
  await requireOwnedRestaurant(ctx, existing.restaurantId, user);

  if (input.categoryId) {
    const [category] = await ctx.db
      .select()
      .from(menuCategories)
      .where(eq(menuCategories.id, input.categoryId));
    if (!category || category.restaurantId !== existing.restaurantId) {
      throw ApiError.badRequest('That category does not belong to this restaurant.');
    }
  }

  const patch = {
    ...(input.categoryId !== undefined ? { categoryId: input.categoryId } : {}),
    ...(input.name !== undefined ? { name: input.name } : {}),
    ...(input.description !== undefined ? { description: input.description } : {}),
    ...(input.priceCents !== undefined ? { priceCents: input.priceCents } : {}),
    ...(input.imageUrl !== undefined ? { imageUrl: input.imageUrl } : {}),
    ...(input.dietaryTags !== undefined ? { dietaryTags: JSON.stringify(input.dietaryTags) } : {}),
    ...(input.isAvailable !== undefined ? { isAvailable: input.isAvailable } : {}),
    ...(input.sortOrder !== undefined ? { sortOrder: input.sortOrder } : {}),
    updatedAt: ctx.now().toISOString(),
  };

  await ctx.db.update(menuItems).set(patch).where(eq(menuItems.id, itemId));

  const [updated] = await ctx.db.select().from(menuItems).where(eq(menuItems.id, itemId));
  return toItemDto(updated!);
};

export const deleteMenuItem = async (
  ctx: AppContext,
  user: AuthenticatedUser,
  itemId: string,
): Promise<void> => {
  const [existing] = await ctx.db.select().from(menuItems).where(eq(menuItems.id, itemId));
  if (!existing) throw ApiError.notFound('Menu item');
  await requireOwnedRestaurant(ctx, existing.restaurantId, user);

  await ctx.db.delete(menuItems).where(eq(menuItems.id, itemId));
};
