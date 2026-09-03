import type {
  AddToCartInput,
  AuthResponse,
  CartDto,
  LoginInput,
  MenuCategoryWithItems,
  OrderDto,
  OrderStatus,
  Paginated,
  PublicUser,
  RegisterInput,
  RestaurantDetail,
  RestaurantSummary,
} from '@fotg/contracts';

const BASE_URL: string = (import.meta.env.VITE_API_BASE_URL as string | undefined) ?? 'http://localhost:5310';

/**
 * The error the whole UI catches. It carries the server's machine-readable code and
 * its details, so a screen can react to `conflict` from a cart holding another
 * restaurant's food differently from a generic failure — without parsing prose.
 */
export class ApiRequestError extends Error {
  readonly status: number;
  readonly code: string;
  readonly details: unknown;

  constructor(status: number, code: string, message: string, details?: unknown) {
    super(message);
    this.name = 'ApiRequestError';
    this.status = status;
    this.code = code;
    this.details = details;
  }
}

let authToken: string | null = null;
export const setAuthToken = (token: string | null): void => {
  authToken = token;
};

interface RequestOptions {
  method?: 'GET' | 'POST' | 'PATCH' | 'DELETE';
  body?: unknown;
  signal?: AbortSignal;
}

const request = async <T>(path: string, options: RequestOptions = {}): Promise<T> => {
  const headers: Record<string, string> = {};
  if (options.body !== undefined) headers['content-type'] = 'application/json';
  if (authToken) headers.authorization = `Bearer ${authToken}`;

  let response: Response;
  try {
    response = await fetch(`${BASE_URL}${path}`, {
      method: options.method ?? 'GET',
      headers,
      ...(options.body !== undefined ? { body: JSON.stringify(options.body) } : {}),
      ...(options.signal ? { signal: options.signal } : {}),
    });
  } catch (error) {
    // A network failure is not a 500 and should not be described as one; the user
    // needs to know their connection is the problem, not ours.
    if ((error as Error).name === 'AbortError') throw error;
    throw new ApiRequestError(0, 'network_error', 'Could not reach FoodOnTheGo. Check your connection.');
  }

  if (response.status === 204) return undefined as T;

  const text = await response.text();
  const payload: unknown = text ? JSON.parse(text) : undefined;

  if (!response.ok) {
    const body = payload as { error?: { code?: string; message?: string; details?: unknown } } | undefined;
    throw new ApiRequestError(
      response.status,
      body?.error?.code ?? 'unknown_error',
      body?.error?.message ?? `Request failed (${response.status}).`,
      body?.error?.details,
    );
  }

  return payload as T;
};

export const api = {
  register: (input: RegisterInput) => request<AuthResponse>('/api/auth/register', { method: 'POST', body: input }),
  login: (input: LoginInput) => request<AuthResponse>('/api/auth/login', { method: 'POST', body: input }),
  me: () => request<PublicUser>('/api/auth/me'),

  restaurants: (query: URLSearchParams, signal?: AbortSignal) =>
    request<Paginated<RestaurantSummary>>(`/api/restaurants?${query.toString()}`, signal ? { signal } : {}),
  restaurant: (id: string) => request<RestaurantDetail>(`/api/restaurants/${id}`),

  cart: () => request<CartDto>('/api/cart'),
  addToCart: (input: AddToCartInput) => request<CartDto>('/api/cart/items', { method: 'POST', body: input }),
  updateCartItem: (id: string, quantity: number) =>
    request<CartDto>(`/api/cart/items/${id}`, { method: 'PATCH', body: { quantity } }),
  removeCartItem: (id: string) => request<CartDto>(`/api/cart/items/${id}`, { method: 'DELETE' }),
  clearCart: () => request<CartDto>('/api/cart', { method: 'DELETE' }),

  placeOrder: (body: unknown) => request<OrderDto>('/api/orders', { method: 'POST', body }),
  orders: (query?: URLSearchParams) => request<Paginated<OrderDto>>(`/api/orders${query ? `?${query}` : ''}`),
  order: (id: string) => request<OrderDto>(`/api/orders/${id}`),
  setOrderStatus: (id: string, status: OrderStatus, reason?: string) =>
    request<OrderDto>(`/api/orders/${id}/status`, { method: 'POST', body: { status, ...(reason ? { reason } : {}) } }),

  ownedRestaurants: () => request<RestaurantSummary[]>('/api/manage/restaurants'),
  ownedMenu: (id: string) => request<MenuCategoryWithItems[]>(`/api/manage/restaurants/${id}/menu`),
  setItemAvailability: (itemId: string, isAvailable: boolean) =>
    request<unknown>(`/api/manage/items/${itemId}`, { method: 'PATCH', body: { isAvailable } }),
};
