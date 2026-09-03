import type { FastifyInstance } from 'fastify';
import { buildApp } from '../app.js';
import { loadConfig } from '../config.js';
import { createDb } from '../db/client.js';
import { runMigrations } from '../db/migrate.js';
import type { AppContext } from '../context.js';

export interface TestHarness {
  app: FastifyInstance;
  ctx: AppContext;
  setNow: (date: Date) => void;
  close: () => Promise<void>;
}

/**
 * Every suite gets a real SQLite database with the real migrations applied. There
 * is no in-memory fake of the data layer anywhere in these tests: a foreign key
 * that is not enforced, or a transaction that does not roll back, is exactly the
 * kind of bug a fake hides.
 */
export const createHarness = async (): Promise<TestHarness> => {
  const config = loadConfig({
    NODE_ENV: 'test',
    DATABASE_FILE: ':memory:',
    JWT_SECRET: 'test-signing-key-that-is-long-enough-to-be-fine',
    CORS_ORIGINS: 'http://localhost:5181',
  } as NodeJS.ProcessEnv);

  const { db, sqlite, close } = createDb(config.databaseFile);
  runMigrations(sqlite);

  let now = new Date('2024-05-15T12:00:00.000Z');
  const ctx: AppContext = { db, config, now: () => now };
  const app = await buildApp(ctx);

  return {
    app,
    ctx,
    setNow: (date: Date) => {
      now = date;
    },
    close: async () => {
      await app.close();
      close();
    },
  };
};

export interface ActorSession {
  token: string;
  userId: string;
  headers: Record<string, string>;
}

export const registerActor = async (
  harness: TestHarness,
  overrides: Partial<{ email: string; password: string; fullName: string; role: string }> = {},
): Promise<ActorSession> => {
  const email = overrides.email ?? `user-${Math.random().toString(36).slice(2, 10)}@example.com`;
  const password = overrides.password ?? 'a-perfectly-fine-password';

  const response = await harness.app.inject({
    method: 'POST',
    url: '/api/auth/register',
    payload: {
      email,
      password,
      fullName: overrides.fullName ?? 'Test Person',
      role: overrides.role ?? 'customer',
    },
  });

  if (response.statusCode !== 201) {
    throw new Error(`Could not register test actor: ${response.statusCode} ${response.body}`);
  }

  const body = response.json() as { token: string; user: { id: string } };
  return {
    token: body.token,
    userId: body.user.id,
    headers: { authorization: `Bearer ${body.token}` },
  };
};

/** Promotes a user to admin directly, since the API deliberately offers no way to. */
export const makeAdmin = async (harness: TestHarness, userId: string): Promise<ActorSession> => {
  const { users } = await import('../db/schema.js');
  const { eq } = await import('drizzle-orm');
  const { issueToken } = await import('../lib/jwt.js');

  await harness.ctx.db.update(users).set({ role: 'admin' }).where(eq(users.id, userId));
  const [row] = await harness.ctx.db.select().from(users).where(eq(users.id, userId));

  const { token } = issueToken(
    harness.ctx.config.jwtSecret,
    { sub: row!.id, role: 'admin', email: row!.email },
    harness.ctx.config.jwtTtlSeconds,
    harness.ctx.now(),
  );

  return { token, userId, headers: { authorization: `Bearer ${token}` } };
};
