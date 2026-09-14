import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  // The shell is served under /admin/ by deploy/nginx/app.conf, not at the
  // origin root. Without this, Vite emits root-absolute asset URLs
  // (/assets/index-<hash>.js) which resolve to the customer app's directory and
  // 404, leaving a blank page with no error anywhere the operator can see.
  base: '/admin/',

  server: { port: 5174, strictPort: true },
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./src/testSetup.ts'],
    include: ['src/**/*.test.ts', 'src/**/*.test.tsx'],
  },
});
