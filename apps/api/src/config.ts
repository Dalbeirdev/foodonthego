import { z } from 'zod';

/**
 * Configuration is read once, validated once, and the process refuses to start on
 * anything it cannot make sense of.
 *
 * The alternative — reading `process.env` where it is needed and defaulting on the
 * spot — is how a service comes up healthy in production while signing tokens with
 * a development key. The two `superRefine` rules below are the whole point of this
 * file: in production there is no default secret and no wildcard CORS.
 */
const schema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().min(0).max(65_535).default(5310),
  HOST: z.string().default('127.0.0.1'),

  DATABASE_FILE: z.string().default('./data/foodonthego.db'),

  JWT_SECRET: z.string().min(1).optional(),
  JWT_TTL_SECONDS: z.coerce.number().int().min(60).max(60 * 60 * 24 * 30).default(60 * 60 * 12),

  /** Comma-separated list of exact origins. Empty in production is a startup failure. */
  CORS_ORIGINS: z.string().default('http://localhost:5181'),

  /** Tax and service fee as basis points, so 8.25% is 825 and stays an integer. */
  TAX_BASIS_POINTS: z.coerce.number().int().min(0).max(10_000).default(825),
  SERVICE_FEE_BASIS_POINTS: z.coerce.number().int().min(0).max(10_000).default(500),
  SERVICE_FEE_CAP_CENTS: z.coerce.number().int().min(0).default(599),
});

const DEV_JWT_SECRET = 'development-only-insecure-signing-key-do-not-deploy';

export interface AppConfig {
  nodeEnv: 'development' | 'test' | 'production';
  port: number;
  host: string;
  databaseFile: string;
  jwtSecret: string;
  jwtTtlSeconds: number;
  corsOrigins: string[];
  taxBasisPoints: number;
  serviceFeeBasisPoints: number;
  serviceFeeCapCents: number;
}

export class ConfigError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ConfigError';
  }
}

export const loadConfig = (env: NodeJS.ProcessEnv = process.env): AppConfig => {
  const parsed = schema.safeParse(env);
  if (!parsed.success) {
    const detail = parsed.error.issues
      .map((issue) => `${issue.path.join('.') || '(root)'}: ${issue.message}`)
      .join('; ');
    throw new ConfigError(`Invalid configuration — ${detail}`);
  }

  const value = parsed.data;
  const isProduction = value.NODE_ENV === 'production';
  const corsOrigins = value.CORS_ORIGINS.split(',')
    .map((origin) => origin.trim())
    .filter(Boolean);

  if (isProduction) {
    if (!value.JWT_SECRET || value.JWT_SECRET === DEV_JWT_SECRET) {
      throw new ConfigError(
        'JWT_SECRET must be set to a real secret in production. Refusing to start with the ' +
          'development signing key, which is committed to this repository and therefore public.',
      );
    }
    if (value.JWT_SECRET.length < 32) {
      throw new ConfigError('JWT_SECRET must be at least 32 characters in production.');
    }
    if (corsOrigins.length === 0) {
      throw new ConfigError(
        'CORS_ORIGINS must list at least one origin in production. Refusing to start with an ' +
          'empty allow-list, which would leave the browser to decide.',
      );
    }
    if (corsOrigins.includes('*')) {
      throw new ConfigError(
        'CORS_ORIGINS may not be "*" in production: this API is credentialed, and a wildcard ' +
          'origin with credentials is exactly the configuration that leaks them.',
      );
    }
  }

  return {
    nodeEnv: value.NODE_ENV,
    port: value.PORT,
    host: value.HOST,
    databaseFile: value.DATABASE_FILE,
    jwtSecret: value.JWT_SECRET ?? DEV_JWT_SECRET,
    jwtTtlSeconds: value.JWT_TTL_SECONDS,
    corsOrigins,
    taxBasisPoints: value.TAX_BASIS_POINTS,
    serviceFeeBasisPoints: value.SERVICE_FEE_BASIS_POINTS,
    serviceFeeCapCents: value.SERVICE_FEE_CAP_CENTS,
  };
};
