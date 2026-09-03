import { eq } from 'drizzle-orm';
import type { AuthResponse, LoginInput, PublicUser, RegisterInput, UserRole } from '@fotg/contracts';
import type { AppContext } from '../context.js';
import { users } from '../db/schema.js';
import { ApiError } from '../lib/errors.js';
import { newId } from '../lib/ids.js';
import { issueToken } from '../lib/jwt.js';
import { hashPassword, needsRehash, verifyPassword } from '../lib/password.js';

type UserRow = typeof users.$inferSelect;

export const toPublicUser = (row: UserRow): PublicUser => ({
  id: row.id,
  email: row.email,
  fullName: row.fullName,
  phone: row.phone,
  role: row.role as UserRole,
  createdAt: row.createdAt,
});

const respondWithToken = (ctx: AppContext, row: UserRow): AuthResponse => {
  const { token, expiresAt } = issueToken(
    ctx.config.jwtSecret,
    { sub: row.id, role: row.role as UserRole, email: row.email },
    ctx.config.jwtTtlSeconds,
    ctx.now(),
  );

  return { token, expiresAt: expiresAt.toISOString(), user: toPublicUser(row) };
};

export const register = async (ctx: AppContext, input: RegisterInput): Promise<AuthResponse> => {
  const [existing] = await ctx.db.select().from(users).where(eq(users.email, input.email));
  if (existing) {
    // Registration cannot avoid disclosing that an address is taken — the account
    // has to be unique — so it says so plainly rather than pretending to succeed.
    // Sign-in and password reset are where the disclosure actually matters.
    throw ApiError.conflict('An account with that email already exists.');
  }

  const timestamp = ctx.now().toISOString();
  const row: UserRow = {
    id: newId(),
    email: input.email,
    passwordHash: await hashPassword(input.password),
    fullName: input.fullName,
    phone: input.phone ?? null,
    role: input.role,
    createdAt: timestamp,
    updatedAt: timestamp,
  };

  await ctx.db.insert(users).values(row);
  return respondWithToken(ctx, row);
};

/**
 * A wrong password and an unknown address produce the same error and, near enough,
 * the same amount of work: when no user is found the password is still hashed
 * against a dummy value, so the response time does not answer "does this address
 * have an account here?" for anyone who cares to measure it.
 */
const DUMMY_HASH =
  'scrypt$32768$8$1$AAAAAAAAAAAAAAAAAAAAAA$AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

export const login = async (ctx: AppContext, input: LoginInput): Promise<AuthResponse> => {
  const [row] = await ctx.db.select().from(users).where(eq(users.email, input.email));

  const ok = await verifyPassword(input.password, row?.passwordHash ?? DUMMY_HASH);
  if (!row || !ok) throw ApiError.unauthorized('Email or password is incorrect.');

  // A successful sign-in is the only moment we hold the plaintext, so it is the only
  // moment an old hash can be upgraded to the current cost.
  if (needsRehash(row.passwordHash)) {
    const upgraded = await hashPassword(input.password);
    await ctx.db
      .update(users)
      .set({ passwordHash: upgraded, updatedAt: ctx.now().toISOString() })
      .where(eq(users.id, row.id));
  }

  return respondWithToken(ctx, row);
};

export const getUserById = async (ctx: AppContext, userId: string): Promise<PublicUser> => {
  const [row] = await ctx.db.select().from(users).where(eq(users.id, userId));
  if (!row) throw ApiError.notFound('User');
  return toPublicUser(row);
};
