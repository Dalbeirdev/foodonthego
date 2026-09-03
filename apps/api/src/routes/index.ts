import type { FastifyInstance } from 'fastify';
import { sql } from 'drizzle-orm';
import { z } from 'zod';
import {
  addToCartSchema,
  loginSchema,
  menuCategorySchema,
  menuItemSchema,
  ORDER_STATUSES,
  placeOrderSchema,
  registerSchema,
  restaurantSchema,
  restaurantSearchSchema,
  updateCartItemSchema,
  updateOrderStatusSchema,
} from '@fotg/contracts';
import { requireRole, requireUser } from '../auth.js';
import type { AppContext } from '../context.js';
import { ApiError } from '../lib/errors.js';
import * as authService from '../services/auth.js';
import * as cartService from '../services/cart.js';
import * as menuService from '../services/menu.js';
import * as orderService from '../services/orders.js';
import * as restaurantService from '../services/restaurants.js';

const uuidParam = z.object({ id: z.string().uuid() });

/** Turns a Zod failure into a 400 carrying the field-level detail, rather than a 500. */
const parse = <T extends z.ZodTypeAny>(schema: T, value: unknown): z.infer<T> => {
  const result = schema.safeParse(value);
  if (!result.success) {
    throw ApiError.badRequest('The request body is not valid.', {
      issues: result.error.issues.map((issue) => ({
        path: issue.path.join('.'),
        message: issue.message,
      })),
    });
  }
  return result.data;
};

export const registerRoutes = (app: FastifyInstance, ctx: AppContext): void => {
  const auth = () => requireUser;
  const secret = ctx.config.jwtSecret;
  const now = ctx.now;

  // --- health -------------------------------------------------------------
  // Two questions, two answers. `live` says the process is running; `ready` says it
  // can serve, which means the database answers. An orchestrator restarts on the
  // first and stops routing traffic on the second, and conflating them turns a
  // busy database into a restart loop.
  app.get('/health/live', async () => ({ status: 'ok' }));

  app.get('/health/ready', async (_request, reply) => {
    try {
      await ctx.db.get(sql`SELECT 1`);
    } catch {
      return reply.code(503).send({ status: 'unavailable', database: 'unreachable' });
    }
    return { status: 'ok', database: 'ok' };
  });

  // --- auth ---------------------------------------------------------------
  app.post('/api/auth/register', async (request, reply) => {
    const body = parse(registerSchema, request.body);
    const result = await authService.register(ctx, body);
    return reply.code(201).send(result);
  });

  app.post('/api/auth/login', async (request) => {
    const body = parse(loginSchema, request.body);
    return authService.login(ctx, body);
  });

  app.get('/api/auth/me', async (request) => {
    const user = auth()(request, secret, now);
    return authService.getUserById(ctx, user.id);
  });

  // --- public storefront --------------------------------------------------
  app.get('/api/restaurants', async (request) => {
    const query = parse(restaurantSearchSchema, request.query);
    return restaurantService.searchRestaurants(ctx, query);
  });

  app.get('/api/restaurants/:id', async (request) => {
    const { id } = parse(uuidParam, request.params);
    return restaurantService.getRestaurantDetail(ctx, id);
  });

  // --- cart ---------------------------------------------------------------
  app.get('/api/cart', async (request) => {
    const user = requireRole(request, secret, now, 'customer', 'admin');
    return cartService.getCart(ctx, user.id);
  });

  app.post('/api/cart/items', async (request, reply) => {
    const user = requireRole(request, secret, now, 'customer', 'admin');
    const body = parse(addToCartSchema, request.body);
    const cart = await cartService.addToCart(ctx, user.id, body);
    return reply.code(201).send(cart);
  });

  app.patch('/api/cart/items/:id', async (request) => {
    const user = requireRole(request, secret, now, 'customer', 'admin');
    const { id } = parse(uuidParam, request.params);
    const body = parse(updateCartItemSchema, request.body);
    return cartService.updateCartItem(ctx, user.id, id, body);
  });

  app.delete('/api/cart/items/:id', async (request) => {
    const user = requireRole(request, secret, now, 'customer', 'admin');
    const { id } = parse(uuidParam, request.params);
    return cartService.removeCartItem(ctx, user.id, id);
  });

  app.delete('/api/cart', async (request) => {
    const user = requireRole(request, secret, now, 'customer', 'admin');
    return cartService.clearCart(ctx, user.id);
  });

  // --- orders -------------------------------------------------------------
  const listQuery = z.object({
    status: z
      .union([z.enum(ORDER_STATUSES), z.array(z.enum(ORDER_STATUSES))])
      .optional()
      .transform((value) => (value === undefined ? undefined : Array.isArray(value) ? value : [value])),
    limit: z.coerce.number().int().min(1).max(100).default(25),
    offset: z.coerce.number().int().min(0).max(10_000).default(0),
  });

  app.post('/api/orders', async (request, reply) => {
    const user = requireRole(request, secret, now, 'customer', 'admin');
    const body = parse(placeOrderSchema, request.body);
    const order = await orderService.placeOrder(ctx, user, body);
    return reply.code(201).send(order);
  });

  app.get('/api/orders', async (request) => {
    const user = auth()(request, secret, now);
    const query = parse(listQuery, request.query);
    return orderService.listOrders(ctx, user, query);
  });

  app.get('/api/orders/:id', async (request) => {
    const user = auth()(request, secret, now);
    const { id } = parse(uuidParam, request.params);
    return orderService.getOrder(ctx, id, user);
  });

  app.post('/api/orders/:id/status', async (request) => {
    const user = auth()(request, secret, now);
    const { id } = parse(uuidParam, request.params);
    const body = parse(updateOrderStatusSchema, request.body);
    return orderService.updateOrderStatus(ctx, id, user, body);
  });

  // --- restaurant management ----------------------------------------------
  app.post('/api/manage/restaurants', async (request, reply) => {
    const user = requireRole(request, secret, now, 'restaurant_owner', 'admin');
    const body = parse(restaurantSchema, request.body);
    const created = await menuService.createRestaurant(ctx, user, body);
    return reply.code(201).send(created);
  });

  app.get('/api/manage/restaurants', async (request) => {
    const user = requireRole(request, secret, now, 'restaurant_owner', 'admin');
    return menuService.listOwnedRestaurants(ctx, user);
  });

  app.get('/api/manage/restaurants/:id/menu', async (request) => {
    const user = requireRole(request, secret, now, 'restaurant_owner', 'admin');
    const { id } = parse(uuidParam, request.params);
    await restaurantService.requireOwnedRestaurant(ctx, id, user);
    // The owner's view includes items they have hidden from customers.
    return restaurantService.getMenu(ctx, id, { includeUnavailable: true });
  });

  app.post('/api/manage/restaurants/:id/categories', async (request, reply) => {
    const user = requireRole(request, secret, now, 'restaurant_owner', 'admin');
    const { id } = parse(uuidParam, request.params);
    const body = parse(menuCategorySchema, request.body);
    const created = await menuService.createCategory(ctx, user, id, body);
    return reply.code(201).send(created);
  });

  app.post('/api/manage/restaurants/:id/items', async (request, reply) => {
    const user = requireRole(request, secret, now, 'restaurant_owner', 'admin');
    const { id } = parse(uuidParam, request.params);
    const body = parse(menuItemSchema, request.body);
    const created = await menuService.createMenuItem(ctx, user, id, body);
    return reply.code(201).send(created);
  });

  app.patch('/api/manage/items/:id', async (request) => {
    const user = requireRole(request, secret, now, 'restaurant_owner', 'admin');
    const { id } = parse(uuidParam, request.params);
    const body = parse(menuItemSchema.partial(), request.body);
    return menuService.updateMenuItem(ctx, user, id, body);
  });

  app.delete('/api/manage/items/:id', async (request, reply) => {
    const user = requireRole(request, secret, now, 'restaurant_owner', 'admin');
    const { id } = parse(uuidParam, request.params);
    await menuService.deleteMenuItem(ctx, user, id);
    return reply.code(204).send();
  });
};
