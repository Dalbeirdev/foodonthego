import { z } from 'zod';
import { ORDER_STATUSES } from './orders.js';

export const USER_ROLES = ['customer', 'restaurant_owner', 'courier', 'admin'] as const;
export type UserRole = (typeof USER_ROLES)[number];

export const CUISINES = [
  'american',
  'bakery',
  'breakfast',
  'burgers',
  'chinese',
  'dessert',
  'greek',
  'indian',
  'italian',
  'japanese',
  'korean',
  'mediterranean',
  'mexican',
  'pizza',
  'sandwiches',
  'seafood',
  'thai',
  'vegan',
  'vietnamese',
] as const;
export type Cuisine = (typeof CUISINES)[number];

export const DIETARY_TAGS = [
  'vegetarian',
  'vegan',
  'gluten_free',
  'dairy_free',
  'nut_free',
  'halal',
  'spicy',
] as const;
export type DietaryTag = (typeof DIETARY_TAGS)[number];

const trimmed = (min: number, max: number) => z.string().trim().min(min).max(max);

export const emailSchema = z.string().trim().toLowerCase().email().max(254);

/**
 * A deliberately low floor with no composition rules. Length is the property that
 * actually resists guessing; "must contain a symbol" mostly produces `Password1!`
 * and a sticky note. Long passphrases are what we want to allow, so the ceiling is
 * generous but present — an unbounded password is a way to make the hash function
 * do unbounded work.
 */
export const passwordSchema = z.string().min(10).max(200);

export const registerSchema = z.object({
  email: emailSchema,
  password: passwordSchema,
  fullName: trimmed(1, 120),
  phone: trimmed(5, 32).optional(),
  role: z.enum(['customer', 'restaurant_owner', 'courier']).default('customer'),
});
export type RegisterInput = z.infer<typeof registerSchema>;

export const loginSchema = z.object({
  email: emailSchema,
  password: z.string().min(1).max(200),
});
export type LoginInput = z.infer<typeof loginSchema>;

export const addressSchema = z.object({
  label: trimmed(1, 60).default('Home'),
  line1: trimmed(1, 160),
  line2: trimmed(1, 160).optional(),
  city: trimmed(1, 80),
  region: trimmed(1, 80),
  postalCode: trimmed(2, 16),
  latitude: z.number().min(-90).max(90).optional(),
  longitude: z.number().min(-180).max(180).optional(),
  deliveryNotes: trimmed(1, 400).optional(),
});
export type AddressInput = z.infer<typeof addressSchema>;

export const restaurantSearchSchema = z.object({
  q: z.string().trim().max(120).optional(),
  cuisine: z.enum(CUISINES).optional(),
  maxDeliveryFee: z.coerce.number().int().min(0).max(100_000).optional(),
  openNow: z
    .union([z.boolean(), z.enum(['true', 'false'])])
    .transform((value) => value === true || value === 'true')
    .optional(),
  sort: z.enum(['relevance', 'rating', 'delivery_fee', 'prep_time']).default('relevance'),
  limit: z.coerce.number().int().min(1).max(50).default(20),
  offset: z.coerce.number().int().min(0).max(10_000).default(0),
});
export type RestaurantSearchInput = z.infer<typeof restaurantSearchSchema>;

export const menuItemSchema = z.object({
  categoryId: z.string().uuid(),
  name: trimmed(1, 120),
  description: trimmed(1, 600).optional(),
  priceCents: z.number().int().min(0).max(1_000_000),
  imageUrl: z.string().url().max(500).optional(),
  dietaryTags: z.array(z.enum(DIETARY_TAGS)).max(DIETARY_TAGS.length).default([]),
  isAvailable: z.boolean().default(true),
  sortOrder: z.number().int().min(0).max(10_000).default(0),
});
export type MenuItemInput = z.infer<typeof menuItemSchema>;

export const menuCategorySchema = z.object({
  name: trimmed(1, 80),
  description: trimmed(1, 400).optional(),
  sortOrder: z.number().int().min(0).max(10_000).default(0),
});
export type MenuCategoryInput = z.infer<typeof menuCategorySchema>;

export const addToCartSchema = z.object({
  menuItemId: z.string().uuid(),
  quantity: z.number().int().min(1).max(50),
  notes: trimmed(1, 300).optional(),
});
export type AddToCartInput = z.infer<typeof addToCartSchema>;

export const updateCartItemSchema = z.object({
  /** Zero removes the line, which is what a stepper pressed down to nothing means. */
  quantity: z.number().int().min(0).max(50),
  notes: trimmed(1, 300).optional(),
});
export type UpdateCartItemInput = z.infer<typeof updateCartItemSchema>;

export const placeOrderSchema = z.object({
  address: addressSchema,
  /**
   * What the client last showed the customer, in cents. The server recomputes the
   * true total and refuses the order if the two disagree, so a price that changed
   * while the cart sat open becomes an error the customer sees rather than a
   * surprise on their card. See `POST /api/orders` in the API docs.
   */
  expectedTotalCents: z.number().int().min(0).optional(),
  tipCents: z.number().int().min(0).max(100_000).default(0),
  customerNotes: trimmed(1, 500).optional(),
});
export type PlaceOrderInput = z.infer<typeof placeOrderSchema>;

export const updateOrderStatusSchema = z.object({
  status: z.enum(ORDER_STATUSES),
  reason: trimmed(1, 300).optional(),
});
export type UpdateOrderStatusInput = z.infer<typeof updateOrderStatusSchema>;

export const restaurantSchema = z.object({
  name: trimmed(1, 120),
  description: trimmed(1, 1000).optional(),
  cuisine: z.enum(CUISINES),
  phone: trimmed(5, 32).optional(),
  addressLine1: trimmed(1, 160),
  city: trimmed(1, 80),
  region: trimmed(1, 80),
  postalCode: trimmed(2, 16),
  latitude: z.number().min(-90).max(90).optional(),
  longitude: z.number().min(-180).max(180).optional(),
  deliveryFeeCents: z.number().int().min(0).max(100_000).default(299),
  minimumOrderCents: z.number().int().min(0).max(1_000_000).default(0),
  prepTimeMinutes: z.number().int().min(1).max(240).default(25),
  imageUrl: z.string().url().max(500).optional(),
  isActive: z.boolean().default(true),
});
export type RestaurantInput = z.infer<typeof restaurantSchema>;
