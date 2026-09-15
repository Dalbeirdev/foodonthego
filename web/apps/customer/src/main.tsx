import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { BrowserRouter } from 'react-router-dom';
import '@fotg/ui/tokens.css';
import { App } from './App.js';
import { SessionProvider } from './session/SessionProvider.js';

const container = document.getElementById('root');
if (!container) throw new Error('No #root element to mount into.');

createRoot(container).render(
  <StrictMode>
    {/* The session wraps the router, not the other way round: the guard reads
        it during the first render of the first route, so it has to exist by
        then or every route starts as anonymous for one tick. */}
    <SessionProvider>
      {/* Vite's BASE_URL, so the router's base and the asset base cannot drift
          apart — both come from `base` in vite.config.ts. */}
      <BrowserRouter basename={import.meta.env.BASE_URL}>
        <App />
      </BrowserRouter>
    </SessionProvider>
  </StrictMode>,
);
