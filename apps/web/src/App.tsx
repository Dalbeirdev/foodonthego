import { NavLink, Navigate, Route, Routes, useLocation } from 'react-router-dom';
import type { ReactElement } from 'react';
import { useAuth } from './state/auth.js';
import { useCart } from './state/cart.js';
import { Browse } from './pages/Browse.js';
import { Restaurant } from './pages/Restaurant.js';
import { Cart } from './pages/Cart.js';
import { Checkout } from './pages/Checkout.js';
import { OrderDetail, OrderList } from './pages/Orders.js';
import { Login, Register } from './pages/Auth.js';
import { Manage } from './pages/Manage.js';
import { Empty, Spinner } from './components/ui.js';

/**
 * Sends an anonymous visitor to sign in and brings them back where they were. It
 * waits for `status` first: routing on a `user` that has not been resolved yet
 * bounces a signed-in person to the sign-in page on every refresh.
 */
const RequireAuth = ({ children, roles }: { children: ReactElement; roles?: string[] }) => {
  const { user, status } = useAuth();
  const location = useLocation();

  if (status === 'loading') {
    return (
      <div className="page container">
        <Spinner label="Checking your session" />
      </div>
    );
  }

  if (!user) {
    return <Navigate to={`/login?next=${encodeURIComponent(location.pathname + location.search)}`} replace />;
  }

  if (roles && !roles.includes(user.role)) {
    return (
      <div className="page container">
        <Empty icon="🔒" title="That is not yours to open">
          This page is for {roles.join(' and ')} accounts.
        </Empty>
      </div>
    );
  }

  return children;
};

const Header = () => {
  const { user, logout } = useAuth();
  const { itemCount } = useCart();
  const showsCart = user?.role === 'customer' || user?.role === 'admin';

  return (
    <header className="header">
      <div className="container header-inner">
        <NavLink to="/" className="brand">
          <span className="brand-mark" aria-hidden="true">
            F
          </span>
          FoodOnTheGo
        </NavLink>

        <nav className="nav">
          <NavLink to="/" end>
            Restaurants
          </NavLink>
          {user ? (
            <NavLink to="/orders">
              {user.role === 'restaurant_owner' ? 'Kitchen' : user.role === 'courier' ? 'Deliveries' : 'Orders'}
            </NavLink>
          ) : null}
          {user?.role === 'restaurant_owner' || user?.role === 'admin' ? (
            <NavLink to="/manage">Menu</NavLink>
          ) : null}

          {showsCart ? (
            <NavLink to="/cart" className="cart-pill">
              🛒 {itemCount > 0 ? itemCount : ''}
              <span className="visually-hidden">items in your cart</span>
            </NavLink>
          ) : null}

          {user ? (
            <button type="button" className="button-ghost" onClick={logout}>
              Sign out
            </button>
          ) : (
            <NavLink to="/login">Sign in</NavLink>
          )}
        </nav>
      </div>
    </header>
  );
};

export const App = () => (
  <div className="app">
    <Header />
    <main>
      <Routes>
        <Route path="/" element={<Browse />} />
        <Route path="/restaurants/:id" element={<Restaurant />} />
        <Route path="/login" element={<Login />} />
        <Route path="/register" element={<Register />} />
        <Route
          path="/cart"
          element={
            <RequireAuth roles={['customer', 'admin']}>
              <Cart />
            </RequireAuth>
          }
        />
        <Route
          path="/checkout"
          element={
            <RequireAuth roles={['customer', 'admin']}>
              <Checkout />
            </RequireAuth>
          }
        />
        <Route
          path="/orders"
          element={
            <RequireAuth>
              <OrderList />
            </RequireAuth>
          }
        />
        <Route
          path="/orders/:id"
          element={
            <RequireAuth>
              <OrderDetail />
            </RequireAuth>
          }
        />
        <Route
          path="/manage"
          element={
            <RequireAuth roles={['restaurant_owner', 'admin']}>
              <Manage />
            </RequireAuth>
          }
        />
        <Route
          path="*"
          element={
            <div className="page container">
              <Empty icon="🧭" title="There is nothing at this address" />
            </div>
          }
        />
      </Routes>
    </main>
  </div>
);
