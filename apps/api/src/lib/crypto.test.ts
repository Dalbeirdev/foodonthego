import { describe, expect, it } from 'vitest';
import { hashPassword, needsRehash, verifyPassword } from './password.js';
import { issueToken, JwtError, verifyToken } from './jwt.js';
import { newOrderReference } from './ids.js';

const SECRET = 'a-test-secret-that-is-plenty-long-for-hmac';

describe('password hashing', () => {
  it('round-trips a correct password and rejects a wrong one', async () => {
    const hash = await hashPassword('correct horse battery staple');
    expect(await verifyPassword('correct horse battery staple', hash)).toBe(true);
    expect(await verifyPassword('Correct horse battery staple', hash)).toBe(false);
    expect(await verifyPassword('', hash)).toBe(false);
  });

  it('salts, so the same password hashes differently every time', async () => {
    const [first, second] = await Promise.all([hashPassword('same-password'), hashPassword('same-password')]);
    expect(first).not.toBe(second);
    expect(await verifyPassword('same-password', first)).toBe(true);
    expect(await verifyPassword('same-password', second)).toBe(true);
  });

  it('treats a malformed stored hash as a failed verification, not a crash', async () => {
    for (const bad of ['', 'nonsense', 'scrypt$1$2$3', 'bcrypt$1$1$1$aaaa$bbbb', 'scrypt$x$8$1$aa$bb']) {
      expect(await verifyPassword('anything', bad)).toBe(false);
    }
  });

  it('refuses a stored hash claiming an absurd cost instead of trying to honour it', async () => {
    // N = 2^30 would ask scrypt for well over a gigabyte.
    const hostile = `scrypt$${2 ** 30}$8$1$AAAA$BBBB`;
    expect(await verifyPassword('anything', hostile)).toBe(false);
  });

  it('flags legacy parameters for upgrade but not current ones', async () => {
    expect(needsRehash(await hashPassword('x-long-enough-password'))).toBe(false);
    expect(needsRehash('scrypt$1024$8$1$AAAA$BBBB')).toBe(true);
    expect(needsRehash('not-a-hash')).toBe(true);
  });

  it('normalises unicode so the same typed password verifies', async () => {
    const composed = 'café-passphrase-long';       // é as one code point
    const decomposed = 'café-passphrase-long'; // e + combining accent
    const hash = await hashPassword(composed);
    expect(await verifyPassword(decomposed, hash)).toBe(true);
  });
});

describe('jwt', () => {
  const claims = { sub: 'user-1', role: 'customer' as const, email: 'a@example.com' };

  it('issues a token that verifies with the same secret', () => {
    const { token, expiresAt } = issueToken(SECRET, claims, 3600);
    const verified = verifyToken(SECRET, token);
    expect(verified.sub).toBe('user-1');
    expect(verified.email).toBe('a@example.com');
    expect(expiresAt.getTime()).toBeGreaterThan(Date.now());
  });

  it('rejects a token signed with a different secret', () => {
    const { token } = issueToken(SECRET, claims, 3600);
    expect(() => verifyToken('a-different-secret-entirely', token)).toThrow(JwtError);
  });

  it('rejects a tampered payload', () => {
    const { token } = issueToken(SECRET, claims, 3600);
    const [head, , signature] = token.split('.');
    const forged = Buffer.from(
      JSON.stringify({ ...claims, role: 'admin', iat: 1, exp: 9_999_999_999 }),
      'utf8',
    ).toString('base64url');
    expect(() => verifyToken(SECRET, `${head}.${forged}.${signature}`)).toThrow(JwtError);
  });

  it('rejects the alg:none forgery', () => {
    const head = Buffer.from(JSON.stringify({ alg: 'none', typ: 'JWT' }), 'utf8').toString('base64url');
    const body = Buffer.from(
      JSON.stringify({ ...claims, role: 'admin', iat: 1, exp: 9_999_999_999 }),
      'utf8',
    ).toString('base64url');
    expect(() => verifyToken(SECRET, `${head}.${body}.`)).toThrow(JwtError);
    expect(() => verifyToken(SECRET, `${head}.${body}.anything`)).toThrow(JwtError);
  });

  it('rejects an expired token', () => {
    const issuedAt = new Date('2024-01-01T00:00:00Z');
    const { token } = issueToken(SECRET, claims, 60, issuedAt);
    expect(() => verifyToken(SECRET, token, new Date('2024-01-01T00:00:59Z'))).not.toThrow();
    expect(() => verifyToken(SECRET, token, new Date('2024-01-01T00:01:01Z'))).toThrow(/expired/i);
  });

  it('rejects structurally broken tokens rather than throwing something unexpected', () => {
    for (const bad of ['', 'a', 'a.b', 'a.b.c.d', '...', 'not.a.token']) {
      expect(() => verifyToken(SECRET, bad)).toThrow(JwtError);
    }
  });
});

describe('order references', () => {
  it('avoids the characters that get misread aloud', () => {
    for (let attempt = 0; attempt < 500; attempt += 1) {
      expect(newOrderReference()).toMatch(/^[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{8}$/);
    }
  });

  it('does not repeat itself in any realistic run', () => {
    const seen = new Set(Array.from({ length: 2000 }, () => newOrderReference()));
    expect(seen.size).toBe(2000);
  });
});
