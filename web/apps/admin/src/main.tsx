import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { BrowserRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import '@fotg/ui/tokens.css';
import { App } from './App.js';

// TanStack Query is installed and wired now so feature modules inherit one cache
// and one retry policy rather than each inventing their own fetching.
const queryClient = new QueryClient({
  defaultOptions: {
    queries: { staleTime: 30_000, retry: 1, refetchOnWindowFocus: false },
  },
});

const container = document.getElementById('root');
if (!container) throw new Error('No #root element to mount into.');

createRoot(container).render(
  <StrictMode>
    <QueryClientProvider client={queryClient}>
      {/* Vite's BASE_URL, so the router's base and the asset base cannot
          drift apart: both come from `base` in vite.config.ts. Hard-coding it
          here is how a shell ends up serving its files correctly and then
          matching no route. */}
      <BrowserRouter basename={import.meta.env.BASE_URL}>
        <App />
      </BrowserRouter>
    </QueryClientProvider>
  </StrictMode>,
);
