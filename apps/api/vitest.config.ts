import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    environment: 'node',
    include: ['src/**/*.test.ts'],
    // Each suite builds its own SQLite database; running files in parallel
    // processes keeps them from sharing one and is fine because nothing is global.
    pool: 'forks',
    testTimeout: 20_000,
  },
});
