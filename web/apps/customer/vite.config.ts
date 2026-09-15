import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],

  // The customer app is served at the origin root, unlike the two operator
  // shells which live under /restaurant/ and /admin/. Stated rather than left
  // to the default so the three configs read the same way.
  base: '/',

  server: {
    port: 5175,
    strictPort: true,

    // The API on the same origin as the page, exactly as deploy/nginx serves it.
    //
    // Not VITE_API_BASE_URL pointing at :8000, which is what the two operator
    // shells do: a cross-origin dev server means dev exercises a CORS path that
    // production never takes, and the one bug this project has already shipped
    // three times (KI-052/057/059) was a client compiled with an address that
    // was right on one machine and wrong everywhere else. Same origin in dev and
    // same origin in production means there is no address to get wrong.
    proxy: { '/api': { target: 'http://127.0.0.1:8000', changeOrigin: false } },
  },
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./src/testSetup.ts'],
    include: ['src/**/*.test.ts', 'src/**/*.test.tsx'],
  },
});
