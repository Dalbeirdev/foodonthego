import type { Cents } from './money.js';
import type { OpeningWindow } from './hours.js';
import type { OrderStatus } from './orders.js';
import type { Cuisine, DietaryTag, UserRole } from './schemas.js';

export interface PublicUser {
  id: string;
  email: string;
  fullName: string;
  phone: string | null;
  role: UserRole;
  createdAt: string;
}

export interface AuthResponse {
  token: string;
  expiresAt: string;
  user: PublicUser;
}

export interface RestaurantSummary {
  id: string;
  name: string;
  description: string | null;
  cuisine: Cuisine;
  city: string;
  region: string;
  imageUrl: string | null;
  deliveryFeeCents: Cents;
  minimumOrderCents: Cents;
  prepTimeMinutes: number;
  ratingAverage: number | null;
  ratingCount: number;
  isActive: boolean;
  isOpenNow: boolean;
}

export interface RestaurantDetail extends RestaurantSummary {
  phone: string | null;
  addressLine1: string;
  postalCode: string;
  latitude: number | null;
  longitude: number | null;
  openingHours: OpeningWindow[];
  menu: MenuCategoryWithItems[];
}

export interface MenuCategoryWithItems {
  id: string;
  name: string;
  description: string | null;
  sortOrder: number;
  items: MenuItemDto[];
}

export interface MenuItemDto {
  id: string;
  categoryId: string;
  name: string;
  description: string | null;
  priceCents: Cents;
  imageUrl: string | null;
  dietaryTags: DietaryTag[];
  isAvailable: boolean;
  sortOrder: number;
}

export interface CartLine {
  id: string;
  menuItemId: string;
  name: string;
  unitPriceCents: Cents;
  quantity: number;
  notes: string | null;
  lineTotalCents: Cents;
  isAvailable: boolean;
}

/**
 * Every figure the customer is shown before paying, computed server-side. The
 * client never adds these up itself — see `pricing.ts` in the API for why the
 * breakdown travels whole rather than as a total to be re-derived.
 */
export interface OrderTotals {
  subtotalCents: Cents;
  deliveryFeeCents: Cents;
  serviceFeeCents: Cents;
  taxCents: Cents;
  tipCents: Cents;
  totalCents: Cents;
}

export interface CartDto {
  id: string;
  restaurantId: string | null;
  restaurantName: string | null;
  lines: CartLine[];
  totals: OrderTotals;
  minimumOrderCents: Cents;
  meetsMinimum: boolean;
}

export interface OrderLine {
  id: string;
  menuItemId: string | null;
  name: string;
  unitPriceCents: Cents;
  quantity: number;
  notes: string | null;
  lineTotalCents: Cents;
}

export interface OrderEventDto {
  id: string;
  status: OrderStatus;
  actor: string;
  reason: string | null;
  createdAt: string;
}

export interface OrderDto {
  id: string;
  reference: string;
  status: OrderStatus;
  restaurantId: string;
  restaurantName: string;
  customerId: string;
  customerName: string;
  courierId: string | null;
  lines: OrderLine[];
  totals: OrderTotals;
  deliveryAddress: {
    label: string;
    line1: string;
    line2: string | null;
    city: string;
    region: string;
    postalCode: string;
    deliveryNotes: string | null;
  };
  customerNotes: string | null;
  estimatedReadyAt: string | null;
  placedAt: string;
  updatedAt: string;
  events: OrderEventDto[];
  allowedNextStatuses: OrderStatus[];
}

export interface Paginated<T> {
  items: T[];
  total: number;
  limit: number;
  offset: number;
}

export interface ApiErrorBody {
  error: {
    code: string;
    message: string;
    details?: unknown;
  };
}
