import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { createHarness, registerActor, type TestHarness } from '../testing/harness.js';

let harness: TestHarness;

beforeEach(async () => {
  harness = await createHarness();
});
afterEach(async () => {
  await harness.close();
});

describe('POST /api/auth/register', () => {
  it('creates an account and returns a usable token', async () => {
    const response = await harness.app.inject({
      method: 'POST',
      url: '/api/auth/register',
      payload: { email: 'Ada@Example.com', password: 'a-perfectly-fine-password', fullName: 'Ada Lovelace' },
    });

    expect(response.statusCode).toBe(201);
    const body = response.json();
    expect(body.user.email).toBe('ada@example.com');
    expect(body.user.role).toBe('customer');

    const me = await harness.app.inject({
      method: 'GET',
      url: '/api/auth/me',
      headers: { authorization: `Bearer ${body.token}` },
    });
    expect(me.statusCode).toBe(200);
    expect(me.json().id).toBe(body.user.id);
  });

  it('never returns the password hash', async () => {
    const response = await harness.app.inject({
      method: 'POST',
      url: '/api/auth/register',
      payload: { email: 'a@example.com', password: 'a-perfectly-fine-password', fullName: 'A' },
    });
    expect(JSON.stringify(response.json())).not.toMatch(/scrypt|passwordHash|password_hash/);
  });

  it('rejects a duplicate email', async () => {
    const payload = { email: 'dup@example.com', password: 'a-perfectly-fine-password', fullName: 'A' };
    expect((await harness.app.inject({ method: 'POST', url: '/api/auth/register', payload })).statusCode).toBe(201);

    const second = await harness.app.inject({ method: 'POST', url: '/api/auth/register', payload });
    expect(second.statusCode).toBe(409);
    expect(second.json().error.code).toBe('conflict');
  });

  it('will not let anyone register themselves as an admin', async () => {
    const response = await harness.app.inject({
      method: 'POST',
      url: '/api/auth/register',
      payload: {
        email: 'sneaky@example.com',
        password: 'a-perfectly-fine-password',
        fullName: 'Sneaky',
        role: 'admin',
      },
    });
    expect(response.statusCode).toBe(400);
  });

  it('reports every invalid field rather than only the first', async () => {
    const response = await harness.app.inject({
      method: 'POST',
      url: '/api/auth/register',
      payload: { email: 'not-an-email', password: 'short', fullName: '' },
    });
    expect(response.statusCode).toBe(400);
    const paths = response.json().error.details.issues.map((issue: { path: string }) => issue.path);
    expect(paths).toContain('email');
    expect(paths).toContain('password');
    expect(paths).toContain('fullName');
  });
});

describe('POST /api/auth/login', () => {
  beforeEach(async () => {
    await harness.app.inject({
      method: 'POST',
      url: '/api/auth/register',
      payload: { email: 'user@example.com', password: 'a-perfectly-fine-password', fullName: 'User' },
    });
  });

  it('signs in with the right password', async () => {
    const response = await harness.app.inject({
      method: 'POST',
      url: '/api/auth/login',
      payload: { email: 'user@example.com', password: 'a-perfectly-fine-password' },
    });
    expect(response.statusCode).toBe(200);
    expect(response.json().token).toBeTruthy();
  });

  it('gives the same answer for a wrong password and an unknown address', async () => {
    const wrongPassword = await harness.app.inject({
      method: 'POST',
      url: '/api/auth/login',
      payload: { email: 'user@example.com', password: 'the-wrong-password' },
    });
    const unknownUser = await harness.app.inject({
      method: 'POST',
      url: '/api/auth/login',
      payload: { email: 'nobody@example.com', password: 'the-wrong-password' },
    });

    expect(wrongPassword.statusCode).toBe(401);
    expect(unknownUser.statusCode).toBe(401);
    // Identical down to the wording: anything else is an account-existence oracle.
    expect(wrongPassword.json()).toEqual(unknownUser.json());
  });
});

describe('GET /api/auth/me', () => {
  it('refuses anything that is not a valid bearer token', async () => {
    for (const authorization of ['', 'Bearer', 'Bearer nonsense', 'Basic abc', 'Bearer a.b.c']) {
      const response = await harness.app.inject({
        method: 'GET',
        url: '/api/auth/me',
        ...(authorization ? { headers: { authorization } } : {}),
      });
      expect(response.statusCode).toBe(401);
    }
  });

  it('refuses a token signed with the wrong key', async () => {
    const { issueToken } = await import('../lib/jwt.js');
    const actor = await registerActor(harness);
    const { token } = issueToken(
      'an-entirely-different-signing-key-here',
      { sub: actor.userId, role: 'admin', email: 'a@example.com' },
      3600,
    );

    const response = await harness.app.inject({
      method: 'GET',
      url: '/api/auth/me',
      headers: { authorization: `Bearer ${token}` },
    });
    expect(response.statusCode).toBe(401);
  });
});
