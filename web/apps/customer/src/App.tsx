import { Navigate, Route, Routes } from 'react-router-dom';
import { CustomerShell } from './shell/CustomerShell.js';
import { HomeScreen } from './home/HomeScreen.js';
import { SectionComingLater } from './shell/SectionComingLater.js';
import { TripPlannerScreen } from './trips/TripPlannerScreen.js';
import { TripsScreen } from './trips/TripsScreen.js';
import { RouteScreen } from './route/RouteScreen.js';
import { RestaurantsHandoffScreen } from './route/RestaurantsHandoffScreen.js';
import { AddressesScreen } from './addresses/AddressesScreen.js';
import { ProfileScreen } from './session/ProfileScreen.js';
import { RequireSession } from './session/RequireSession.js';
import { SignInScreen } from './auth/SignInScreen.js';
import { RedirectIfSignedIn } from './session/RedirectIfSignedIn.js';

/**
 * Every customer route.
 *
 * The five destinations all exist and all answer. Orders and Notifications have
 * no content yet — their restart modules own that — but a route that renders an
 * honest empty section is navigable, bookmarkable and has working back
 * behaviour, which a missing route does not.
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

      <Route path="/trips" element={<TripsScreen />} />

      {/* Before /trips/:tripId, so "plan" is a screen and not a journey id.
          React Router ranks static segments above dynamic ones, so the order
          here is documentation rather than load-bearing — but the next person
          to add /trips/something should not have to know that. */}
      <Route path="/trips/plan" element={<TripPlannerScreen />} />
      {/* Restart Module 06 replaced the placeholder journey screen with the
          real route screen: map, distance, travel time, alternatives and the
          handoff onward. */}
      <Route path="/trips/:tripId" element={<RouteScreen />} />

      {/* Where "Find food on this route" lands. Restart Module 07 owns the
          listing; until then this is an honest screen rather than a dead
          click, and it carries the trip and route ids that module needs. */}
      <Route path="/trips/:tripId/restaurants" element={<RestaurantsHandoffScreen />} />
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
      <Route path="/profile/addresses" element={<AddressesScreen />} />

      {/* Anything else inside the shell goes Home rather than to a dead end. */}
      <Route path="*" element={<Navigate to="/" replace />} />
    </Route>
  </Routes>
);
