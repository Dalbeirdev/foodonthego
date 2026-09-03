import { describe, expect, it } from 'vitest';
import { ConfigError, loadConfig } from './config.js';

const productionEnv = (overrides: Record<string, string> = {}) =>
  ({
    NODE_ENV: 'production',
    JWT_SECRET: 'a-real-production-secret-that-is-long-enough',
    CORS_ORIGINS: 'https://foodonthego.example',
    ...overrides,
  }) as NodeJS.ProcessEnv;

describe('development defaults', () => {
  it('comes up with no configuration at all', () => {
    const config = loadConfig({} as NodeJS.ProcessEnv);
    expect(config.nodeEnv).toBe('development');
    expect(config.port).toBe(5310);
    expect(config.jwtSecret).toBeTruthy();
  });

  it('parses the CORS list into exact origins', () => {
    const config = loadConfig({ CORS_ORIGINS: 'http://a.test, http://b.test ,' } as NodeJS.ProcessEnv);
    expect(config.corsOrigins).toEqual(['http://a.test', 'http://b.test']);
  });
});

describe('production guards', () => {
  it('starts when everything is set properly', () => {
    expect(() => loadConfig(productionEnv())).not.toThrow();
  });

  it('refuses to start with no JWT secret', () => {
    const env = productionEnv();
    delete env.JWT_SECRET;
    expect(() => loadConfig(env)).toThrow(ConfigError);
    expect(() => loadConfig(env)).toThrow(/JWT_SECRET/);
  });

  it('refuses to start on the committed development key', () => {
    expect(() =>
      loadConfig(productionEnv({ JWT_SECRET: 'development-only-insecure-signing-key-do-not-deploy' })),
    ).toThrow(/development signing key/);
  });

  it('refuses a JWT secret that is too short to be worth having', () => {
    expect(() => loadConfig(productionEnv({ JWT_SECRET: 'short' }))).toThrow(/at least 32/);
  });

  it('refuses to start with an empty CORS allow-list', () => {
    expect(() => loadConfig(productionEnv({ CORS_ORIGINS: '' }))).toThrow(/CORS_ORIGINS/);
  });

  it('refuses a wildcard CORS origin on a credentialed API', () => {
    expect(() => loadConfig(productionEnv({ CORS_ORIGINS: '*' }))).toThrow(/wildcard/);
  });

  it('names the offending key when a value cannot be parsed', () => {
    expect(() => loadConfig(productionEnv({ PORT: 'not-a-number' }))).toThrow(/PORT/);
  });
});
