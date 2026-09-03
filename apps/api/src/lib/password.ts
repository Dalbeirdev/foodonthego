import { randomBytes, scrypt as scryptCallback, timingSafeEqual, type ScryptOptions } from 'node:crypto';

/**
 * `util.promisify` resolves to the three-argument overload and loses the options
 * parameter, which is where the cost parameters live — so the promise wrapper is
 * written out rather than inferred.
 */
const scrypt = (
  password: string,
  salt: Buffer,
  keyLength: number,
  options: ScryptOptions,
): Promise<Buffer> =>
  new Promise((resolve, reject) => {
    scryptCallback(password, salt, keyLength, options, (error, derivedKey) => {
      if (error) reject(error);
      else resolve(derivedKey);
    });
  });

/**
 * Passwords are stored as `scrypt$N$r$p$salt$hash`, all base64url.
 *
 * The parameters are recorded in the string rather than assumed, so raising the
 * cost later does not invalidate every existing password: an old hash still
 * verifies with the parameters it was made under, and `needsRehash` says when to
 * upgrade it on the next successful sign-in.
 */
const CURRENT = { N: 2 ** 15, r: 8, p: 1, keyLength: 32, saltLength: 16 } as const;

// scrypt's memory use is roughly 128 * N * r bytes; Node's default 32 MiB cap is
// below what N = 32768 needs, so it is raised here rather than silently failing.
const maxmem = 256 * 1024 * 1024;

const toB64 = (buffer: Buffer): string => buffer.toString('base64url');
const fromB64 = (value: string): Buffer => Buffer.from(value, 'base64url');

export const hashPassword = async (password: string): Promise<string> => {
  const salt = randomBytes(CURRENT.saltLength);
  const derived = await scrypt(password.normalize('NFKC'), salt, CURRENT.keyLength, {
    N: CURRENT.N,
    r: CURRENT.r,
    p: CURRENT.p,
    maxmem,
  });

  return ['scrypt', CURRENT.N, CURRENT.r, CURRENT.p, toB64(salt), toB64(derived)].join('$');
};

export const verifyPassword = async (password: string, stored: string): Promise<boolean> => {
  const parts = stored.split('$');
  if (parts.length !== 6 || parts[0] !== 'scrypt') return false;

  const N = Number(parts[1]);
  const r = Number(parts[2]);
  const p = Number(parts[3]);
  if (!Number.isInteger(N) || !Number.isInteger(r) || !Number.isInteger(p)) return false;
  // A stored record claiming an absurd cost would otherwise let anyone who can
  // write to the users table turn a sign-in attempt into a memory exhaustion.
  if (N < 2 || N > 2 ** 20 || r < 1 || r > 32 || p < 1 || p > 16) return false;

  let salt: Buffer;
  let expected: Buffer;
  try {
    salt = fromB64(parts[4]!);
    expected = fromB64(parts[5]!);
  } catch {
    return false;
  }
  if (expected.length === 0) return false;

  let derived: Buffer;
  try {
    derived = await scrypt(password.normalize('NFKC'), salt, expected.length, {
      N,
      r,
      p,
      maxmem,
    });
  } catch {
    return false;
  }

  return derived.length === expected.length && timingSafeEqual(derived, expected);
};

/** True when a hash was made with weaker parameters than the ones in use now. */
export const needsRehash = (stored: string): boolean => {
  const parts = stored.split('$');
  if (parts.length !== 6 || parts[0] !== 'scrypt') return true;
  return Number(parts[1]) < CURRENT.N || Number(parts[2]) < CURRENT.r || Number(parts[3]) < CURRENT.p;
};
