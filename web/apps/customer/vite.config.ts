import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],

  // The customer app is served at the origin root, unlike the two operator
  // shells which live under /restaurant/ and /admin/. Stated rather than left
  // to the default so the three configs read the same way.
  base: '/',

  server: { port: 5175, strictPort: true },
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./src/testSetup.ts'],
    include: ['src/**/*.test.ts', 'src/**/*.test.tsx'],
  },
});
