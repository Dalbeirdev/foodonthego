import { mkdirSync } from 'node:fs';
import { dirname } from 'node:path';
import Database from 'better-sqlite3';
import type { Database as SqliteDatabase } from 'better-sqlite3';
import { drizzle, type BetterSQLite3Database } from 'drizzle-orm/better-sqlite3';
import * as schema from './schema.js';

export type Db = BetterSQLite3Database<typeof schema>;

export interface DbHandle {
  db: Db;
  sqlite: SqliteDatabase;
  close: () => void;
}

export const createDb = (databaseFile: string): DbHandle => {
  if (databaseFile !== ':memory:') {
    mkdirSync(dirname(databaseFile), { recursive: true });
  }

  const sqlite = new Database(databaseFile);

  // Write-ahead logging lets reads continue while an order is being written, which
  // matters because placing an order is a multi-table transaction and the storefront
  // is reading the same tables throughout.
  if (databaseFile !== ':memory:') {
    sqlite.pragma('journal_mode = WAL');
  }
  // SQLite does not enforce foreign keys unless asked, per connection. Every
  // `references()` in the schema is decorative without this line.
  sqlite.pragma('foreign_keys = ON');
  sqlite.pragma('busy_timeout = 5000');

  const db = drizzle(sqlite, { schema });

  return { db, sqlite, close: () => sqlite.close() };
};
