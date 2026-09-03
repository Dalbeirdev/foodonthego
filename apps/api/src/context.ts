import type { AppConfig } from './config.js';
import type { Db } from './db/client.js';

export interface AppContext {
  db: Db;
  config: AppConfig;
  /** Injectable so tests can place an order at a known time and assert on the estimate. */
  now: () => Date;
}
