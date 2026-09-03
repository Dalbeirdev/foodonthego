import { readdirSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import type Database from 'better-sqlite3';

const here = dirname(fileURLToPath(import.meta.url));

/**
 * Applies the SQL files in `migrations/` in filename order, once each.
 *
 * Drizzle Kit generates those files from `schema.ts`; this runs them. It is
 * deliberately a few lines rather than a dependency, because the only behaviour
 * needed is "apply what has not been applied, in one transaction, and remember
 * that you did".
 */
export const runMigrations = (sqlite: Database.Database, migrationsDir = join(here, '../../migrations')): string[] => {
  sqlite.exec(`
    CREATE TABLE IF NOT EXISTS __migrations (
      name TEXT PRIMARY KEY,
      applied_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
    );
  `);

  const applied = new Set(
    sqlite.prepare('SELECT name FROM __migrations').all().map((row) => (row as { name: string }).name),
  );

  const files = readdirSync(migrationsDir)
    .filter((file) => file.endsWith('.sql'))
    .sort();

  const newlyApplied: string[] = [];

  for (const file of files) {
    if (applied.has(file)) continue;

    const sql = readFileSync(join(migrationsDir, file), 'utf8');
    // Drizzle separates statements with this marker; splitting on bare semicolons
    // would break any statement containing one inside a string or a trigger body.
    const statements = sql
      .split('--> statement-breakpoint')
      .map((statement) => statement.trim())
      .filter(Boolean);

    const apply = sqlite.transaction(() => {
      for (const statement of statements) {
        sqlite.exec(statement);
      }
      sqlite.prepare('INSERT INTO __migrations (name) VALUES (?)').run(file);
    });

    apply();
    newlyApplied.push(file);
  }

  return newlyApplied;
};
