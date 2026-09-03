import { createHmac, timingSafeEqual } from 'node:crypto';
import type { UserRole } from '@fotg/contracts';

/**
 * A deliberately small HS256 implementation, written out rather than pulled in,
 * because the parts that matter are the parts a wrapper hides:
 *
 * - The algorithm is not read from the token. `alg: none` and the RS256/HS256
 *   confusion attack both work by getting the verifier to believe the header; this
 *   verifier checks that the header says exactly `{"alg":"HS256","typ":"JWT"}` and
 *   ignores it otherwise.
 * - The signature is compared in constant time.
 * - `exp` is required, not optional. A token with no expiry is a permanent one.
 */
export interface JwtClaims {
  sub: string;
  role: UserRole;
  email: string;
  iat: number;
  exp: number;
}

const HEADER = { alg: 'HS256', typ: 'JWT' } as const;

const encode = (value: object): string =>
  Buffer.from(JSON.stringify(value), 'utf8').toString('base64url');

const sign = (secret: string, payload: string): string =>
  createHmac('sha256', secret).update(payload).digest('base64url');

export const issueToken = (
  secret: string,
  claims: Omit<JwtClaims, 'iat' | 'exp'>,
  ttlSeconds: number,
  now = new Date(),
): { token: string; expiresAt: Date } => {
  const issuedAt = Math.floor(now.getTime() / 1000);
  const expiresAt = issuedAt + ttlSeconds;
  const body = encode({ ...claims, iat: issuedAt, exp: expiresAt });
  const head = encode(HEADER);
  const signingInput = `${head}.${body}`;

  return {
    token: `${signingInput}.${sign(secret, signingInput)}`,
    expiresAt: new Date(expiresAt * 1000),
  };
};

export class JwtError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'JwtError';
  }
}

export const verifyToken = (secret: string, token: string, now = new Date()): JwtClaims => {
  const parts = token.split('.');
  if (parts.length !== 3) throw new JwtError('Malformed token.');

  const [head, body, signature] = parts as [string, string, string];

  let header: unknown;
  try {
    header = JSON.parse(Buffer.from(head, 'base64url').toString('utf8'));
  } catch {
    throw new JwtError('Malformed token header.');
  }

  // Pinned, not negotiated.
  if (
    typeof header !== 'object' ||
    header === null ||
    (header as { alg?: unknown }).alg !== 'HS256' ||
    (header as { typ?: unknown }).typ !== 'JWT'
  ) {
    throw new JwtError('Unsupported token algorithm.');
  }

  const expected = Buffer.from(sign(secret, `${head}.${body}`), 'utf8');
  const actual = Buffer.from(signature, 'utf8');
  if (expected.length !== actual.length || !timingSafeEqual(expected, actual)) {
    throw new JwtError('Bad token signature.');
  }

  let claims: unknown;
  try {
    claims = JSON.parse(Buffer.from(body, 'base64url').toString('utf8'));
  } catch {
    throw new JwtError('Malformed token payload.');
  }

  if (typeof claims !== 'object' || claims === null) throw new JwtError('Malformed token payload.');
  const candidate = claims as Partial<JwtClaims>;

  if (
    typeof candidate.sub !== 'string' ||
    typeof candidate.role !== 'string' ||
    typeof candidate.email !== 'string' ||
    typeof candidate.iat !== 'number' ||
    typeof candidate.exp !== 'number'
  ) {
    throw new JwtError('Token is missing required claims.');
  }

  const seconds = Math.floor(now.getTime() / 1000);
  if (candidate.exp <= seconds) throw new JwtError('Token has expired.');
  // A little tolerance for clock skew between the issuer and this process.
  if (candidate.iat > seconds + 60) throw new JwtError('Token was issued in the future.');

  return candidate as JwtClaims;
};
