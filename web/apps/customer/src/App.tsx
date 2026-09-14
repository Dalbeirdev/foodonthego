import { Navigate, Route, Routes } from 'react-router-dom';
import { CustomerShell } from './shell/CustomerShell.js';
import { HomeScreen } from './home/HomeScreen.js';
import { SectionComingLater } from './shell/SectionComingLater.js';
import { ProfileScreen } from './session/ProfileScreen.js';
import { RequireSession } from './session/RequireSession.js';
import { SignInScreen } from './auth/SignInScreen.js';
import { RedirectIfSignedIn } from './session/RedirectIfSignedIn.js';

/**
 * Every customer route.
 *
 * The five destinations all exist and all answer. Four of them have no content
 * yet — their restart modules own that — but a route that renders an honest
 * empty section is navigable, bookmarkable and has working back behaviour,
 * which a missing route does not.
 *
 * Guarding wraps the shell rather than each screen, so there is exactly one
 * place a private route can be added without protection, and it is this file.
 */
export const App = () => (
  <Routes>
    {/* A signed-in customer who lands here is sent Home rather than shown a
        form they do not need. */}
    <Route
      path="/login"
      element={
        <RedirectIfSignedIn>
          <SignInScreen />
        </RedirectIfSignedIn>
      }
    />

    <Route
      element={
        <RequireSession>
          <CustomerShell />
        </RequireSession>
      }
    >
      <Route path="/" element={<HomeScreen />} />

      <Route
        path="/trips"
        element={
          <SectionComingLater
            title="Trips"
            description="Journeys you have planned will appear here."
          />
        }
      />
      <Route
        path="/trips/plan"
        element={
          <SectionComingLater
            title="Plan a journey"
            description="Choose where you are starting from and where you are going."
          />
        }
      />
      <Route
        path="/trips/:tripId"
        element={
          <SectionComingLater
            title="Journey"
            description="Your route and the food along it will appear here."
          />
        }
      />
      <Route
        path="/orders"
        element={
          <SectionComingLater
            title="Orders"
            description="Orders you have placed will appear here."
          />
        }
      />
      <Route
        path="/orders/:orderId"
        element={
          <SectionComingLater
            title="Order"
            description="Your order and its progress will appear here."
          />
        }
      />
      <Route
        path="/notifications"
        element={
          <SectionComingLater
            title="Notifications"
            description="No notifications yet. We&rsquo;ll tell you when an order is accepted or ready."
          />
        }
      />
      <Route path="/profile" element={<ProfileScreen />} />

      {/* Anything else inside the shell goes Home rather than to a dead end. */}
      <Route path="*" element={<Navigate to="/" replace />} />
    </Route>
  </Routes>
);
