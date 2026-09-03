import cors from '@fastify/cors';
import Fastify, { type FastifyInstance } from 'fastify';
import { ZodError } from 'zod';
import type { AppContext } from './context.js';
import { ApiError } from './lib/errors.js';
import { registerRoutes } from './routes/index.js';

export const buildApp = async (ctx: AppContext): Promise<FastifyInstance> => {
  const app = Fastify({
    logger:
      ctx.config.nodeEnv === 'test'
        ? false
        : {
            level: ctx.config.nodeEnv === 'production' ? 'info' : 'debug',
            redact: {
              // A request body carrying a password must never reach the log, and
              // neither must the bearer token that would let somebody replay it.
              paths: ['req.headers.authorization', 'req.headers.cookie', 'body.password'],
              remove: true,
            },
          },
    // The default 1 MiB is already generous for this API's largest body (a menu
    // item), and a cap is what stops a single request eating the process.
    bodyLimit: 256 * 1024,
    trustProxy: ctx.config.nodeEnv === 'production',
  });

  await app.register(cors, {
    // An exact allow-list, never a reflection of whatever Origin arrived.
    origin: ctx.config.corsOrigins.length > 0 ? ctx.config.corsOrigins : false,
    credentials: true,
    methods: ['GET', 'POST', 'PATCH', 'DELETE', 'OPTIONS'],
  });

  app.setErrorHandler((error, request, reply) => {
    if (error instanceof ApiError) {
      return reply.code(error.statusCode).send({
        error: { code: error.code, message: error.message, ...(error.details ? { details: error.details } : {}) },
      });
    }

    if (error instanceof ZodError) {
      return reply.code(400).send({
        error: {
          code: 'bad_request',
          message: 'The request is not valid.',
          details: { issues: error.issues.map((i) => ({ path: i.path.join('.'), message: i.message })) },
        },
      });
    }

    // Fastify's own 4xx (bad JSON, unsupported media type) are the client's fault
    // and safe to pass through; anything else is ours and is not described.
    const fastifyError = error as { statusCode?: number; code?: string; message?: string };
    const statusCode = fastifyError.statusCode ?? 500;
    if (statusCode < 500) {
      return reply.code(statusCode).send({
        error: {
          code: fastifyError.code ?? 'bad_request',
          message: fastifyError.message ?? 'The request is not valid.',
        },
      });
    }

    request.log.error({ err: error }, 'Unhandled error');
    return reply.code(500).send({
      error: { code: 'internal_error', message: 'Something went wrong on our side.' },
    });
  });

  app.setNotFoundHandler((request, reply) =>
    reply.code(404).send({
      error: { code: 'not_found', message: `No route for ${request.method} ${request.url}.` },
    }),
  );

  registerRoutes(app, ctx);

  return app;
};
