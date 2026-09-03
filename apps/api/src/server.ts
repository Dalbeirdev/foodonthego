import { createDb } from './db/client.js';
import { runMigrations } from './db/migrate.js';
import { loadConfig, ConfigError } from './config.js';
import { buildApp } from './app.js';

const main = async (): Promise<void> => {
  const config = loadConfig();
  const { db, sqlite, close } = createDb(config.databaseFile);

  const applied = runMigrations(sqlite);
  if (applied.length > 0) {
    console.log(`Applied ${applied.length} migration(s): ${applied.join(', ')}`);
  }

  const app = await buildApp({ db, config, now: () => new Date() });

  // A signal has to close the HTTP server *and* the database, or the WAL file is
  // left behind mid-checkpoint and the next start has work to recover.
  const shutdown = async (signal: string): Promise<void> => {
    app.log.info({ signal }, 'Shutting down');
    await app.close();
    close();
    process.exit(0);
  };
  process.on('SIGTERM', () => void shutdown('SIGTERM'));
  process.on('SIGINT', () => void shutdown('SIGINT'));

  await app.listen({ port: config.port, host: config.host });
};

main().catch((error: unknown) => {
  if (error instanceof ConfigError) {
    // Named and explained, then a hard stop. Coming up misconfigured and reporting
    // healthy is worse than not coming up at all.
    console.error(`\nFoodOnTheGo API refused to start.\n\n  ${error.message}\n`);
    process.exit(1);
  }
  console.error(error);
  process.exit(1);
});
