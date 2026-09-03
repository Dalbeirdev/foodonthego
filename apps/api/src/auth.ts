import type { FastifyRequest } from 'fastify';
import type { UserRole } from '@fotg/contracts';
import { ApiError } from './lib/errors.js';
import { JwtError, verifyToken, type JwtClaims } from './lib/jwt.js';

export interface AuthenticatedUser {
  id: string;
  email: string;
  role: UserRole;
}

const BEARER = /^Bearer (.+)$/i;

export const readUser = (request: FastifyRequest, secret: string, now: () => Date): AuthenticatedUser | null => {
  const header = request.headers.authorization;
  if (!header) return null;

  const match = BEARER.exec(header.trim());
  if (!match) return null;

  let claims: JwtClaims;
  try {
    claims = verifyToken(secret, match[1]!, now());
  } catch (error) {
    if (error instanceof JwtError) return null;
    throw error;
  }

  return { id: claims.sub, email: claims.email, role: claims.role };
};

export const requireUser = (
  request: FastifyRequest,
  secret: string,
  now: () => Date,
): AuthenticatedUser => {
  const user = readUser(request, secret, now);
  if (!user) throw ApiError.unauthorized();
  return user;
};

export const requireRole = (
  request: FastifyRequest,
  secret: string,
  now: () => Date,
  ...roles: UserRole[]
): AuthenticatedUser => {
  const user = requireUser(request, secret, now);
  if (!roles.includes(user.role)) {
    throw ApiError.forbidden(`This action is restricted to: ${roles.join(', ')}.`);
  }
  return user;
};
