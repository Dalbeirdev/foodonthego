import { and, asc, desc, eq, inArray, like, or, sql, type SQL } from 'drizzle-orm';
import {
  isOpenAt,
  type DietaryTag,
  type Cuisine,
  type MenuCategoryWithItems,
  type MenuItemDto,
  type OpeningWindow,
  type Paginated,
  type RestaurantDetail,
  type RestaurantSearchInput,
  type RestaurantSummary,
} from '@fotg/contracts';
import type { AppContext } from '../context.js';
import { menuCategories, menuItems, openingHours, restaurants } from '../db/schema.js';
import { ApiError } from '../lib/errors.js';

type RestaurantRow = typeof restaurants.$inferSelect;

const parseDietaryTags = (raw: string): DietaryTag[] => {
  try {
    const parsed: unknown = JSON.parse(raw);
    return Array.isArray(parsed) ? (parsed.filter((tag) => typeof tag === 'string') as DietaryTag[]) : [];
  } catch {
    return [];
  }
};

const averageRating = (row: RestaurantRow): number | null =>
  row.ratingCount === 0 ? null : Math.round((row.ratingSum / row.ratingCount) * 10) / 10;

const toSummary = (row: RestaurantRow, windows: OpeningWindow[], now: Date): RestaurantSummary => ({
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
  ratingAverage: averageRating(row),
  ratingCount: row.ratingCount,
  isActive: row.isActive,
  // A restaurant that has been deactivated is never "open", whatever its hours say.
  isOpenNow: row.isActive && isOpenAt(windows, now),
});

export const searchRestaurants = async (
  ctx: AppContext,
  input: RestaurantSearchInput,
): Promise<Paginated<RestaurantSummary>> => {
  const filters: SQL[] = [eq(restaurants.isActive, true)];

  if (input.q) {
    // `like` here is Drizzle's parameterised builder, not string concatenation, so
    // the wildcards below are the only ones the pattern contains.
    const pattern = `%${input.q.replace(/[%_\\]/g, (char) => `\\${char}`)}%`;
    const match = or(
      like(restaurants.name, pattern),
      like(restaurants.description, pattern),
      like(restaurants.cuisine, pattern),
    );
    if (match) filters.push(match);
  }

  if (input.cuisine) filters.push(eq(restaurants.cuisine, input.cuisine));
  if (input.maxDeliveryFee !== undefined) {
    filters.push(sql`${restaurants.deliveryFeeCents} <= ${input.maxDeliveryFee}`);
  }

  const where = and(...filters);

  const orderBy = {
    relevance: [desc(restaurants.ratingCount), asc(restaurants.name)],
    rating: [desc(sql`CASE WHEN ${restaurants.ratingCount} = 0 THEN -1 ELSE CAST(${restaurants.ratingSum} AS REAL) / ${restaurants.ratingCount} END`), asc(restaurants.name)],
    delivery_fee: [asc(restaurants.deliveryFeeCents), asc(restaurants.name)],
    prep_time: [asc(restaurants.prepTimeMinutes), asc(restaurants.name)],
  }[input.sort];

  // `openNow` cannot be expressed in SQL without reimplementing the overnight-window
  // rule in two places, so it is applied after the query. That means paging happens
  // before the filter; the total below is therefore the number of matching
  // restaurants before the open/closed split, and the API documents it as such.
  const rows = await ctx.db
    .select()
    .from(restaurants)
    .where(where)
    .orderBy(...orderBy)
    .limit(input.limit)
    .offset(input.offset);

  const [{ count } = { count: 0 }] = await ctx.db
    .select({ count: sql<number>`count(*)` })
    .from(restaurants)
    .where(where);

  const windowsByRestaurant = await loadOpeningHours(
    ctx,
    rows.map((row) => row.id),
  );

  const now = ctx.now();
  let items = rows.map((row) => toSummary(row, windowsByRestaurant.get(row.id) ?? [], now));
  if (input.openNow) items = items.filter((item) => item.isOpenNow);

  return { items, total: count, limit: input.limit, offset: input.offset };
};

const loadOpeningHours = async (
  ctx: AppContext,
  restaurantIds: string[],
): Promise<Map<string, OpeningWindow[]>> => {
  const byRestaurant = new Map<string, OpeningWindow[]>();
  if (restaurantIds.length === 0) return byRestaurant;

  const rows = await ctx.db
    .select()
    .from(openingHours)
    .where(inArray(openingHours.restaurantId, restaurantIds));

  for (const row of rows) {
    const list = byRestaurant.get(row.restaurantId) ?? [];
    list.push({
      weekday: row.weekday,
      opensMinute: row.opensMinute,
      closesMinute: row.closesMinute,
    });
    byRestaurant.set(row.restaurantId, list);
  }

  return byRestaurant;
};

export const getRestaurantDetail = async (
  ctx: AppContext,
  restaurantId: string,
): Promise<RestaurantDetail> => {
  const [row] = await ctx.db.select().from(restaurants).where(eq(restaurants.id, restaurantId));
  if (!row || !row.isActive) throw ApiError.notFound('Restaurant');

  const windows = (await loadOpeningHours(ctx, [row.id])).get(row.id) ?? [];
  const menu = await getMenu(ctx, row.id, { includeUnavailable: false });

  return {
    ...toSummary(row, windows, ctx.now()),
    phone: row.phone,
    addressLine1: row.addressLine1,
    postalCode: row.postalCode,
    latitude: row.latitude,
    longitude: row.longitude,
    openingHours: windows.sort(
      (left, right) => left.weekday - right.weekday || left.opensMinute - right.opensMinute,
    ),
    menu,
  };
};

export const getMenu = async (
  ctx: AppContext,
  restaurantId: string,
  options: { includeUnavailable: boolean },
): Promise<MenuCategoryWithItems[]> => {
  const categories = await ctx.db
    .select()
    .from(menuCategories)
    .where(eq(menuCategories.restaurantId, restaurantId))
    .orderBy(asc(menuCategories.sortOrder), asc(menuCategories.name));

  const itemFilters: SQL[] = [eq(menuItems.restaurantId, restaurantId)];
  if (!options.includeUnavailable) itemFilters.push(eq(menuItems.isAvailable, true));

  const items = await ctx.db
    .select()
    .from(menuItems)
    .where(and(...itemFilters))
    .orderBy(asc(menuItems.sortOrder), asc(menuItems.name));

  const byCategory = new Map<string, MenuItemDto[]>();
  for (const item of items) {
    const list = byCategory.get(item.categoryId) ?? [];
    list.push({
      id: item.id,
      categoryId: item.categoryId,
      name: item.name,
      description: item.description,
      priceCents: item.priceCents,
      imageUrl: item.imageUrl,
      dietaryTags: parseDietaryTags(item.dietaryTags),
      isAvailable: item.isAvailable,
      sortOrder: item.sortOrder,
    });
    byCategory.set(item.categoryId, list);
  }

  return categories
    .map((category) => ({
      id: category.id,
      name: category.name,
      description: category.description,
      sortOrder: category.sortOrder,
      items: byCategory.get(category.id) ?? [],
    }))
    // An empty category is a heading with nothing under it; it is noise on a menu.
    .filter((category) => category.items.length > 0 || options.includeUnavailable);
};

export const requireOwnedRestaurant = async (
  ctx: AppContext,
  restaurantId: string,
  user: { id: string; role: string },
): Promise<RestaurantRow> => {
  const [row] = await ctx.db.select().from(restaurants).where(eq(restaurants.id, restaurantId));
  if (!row) throw ApiError.notFound('Restaurant');
  if (user.role !== 'admin' && row.ownerId !== user.id) {
    // 404 rather than 403: whether a restaurant exists is not information somebody
    // who does not own it needs, and a 403 here would confirm it.
    throw ApiError.notFound('Restaurant');
  }
  return row;
};
