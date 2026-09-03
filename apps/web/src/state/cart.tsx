import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import type { CartDto } from '@fotg/contracts';
import { api, ApiRequestError } from '../api/client.js';
import { useAuth } from './auth.js';

interface CartState {
  cart: CartDto | null;
  itemCount: number;
  isLoading: boolean;
  error: string | null;
  refresh: () => Promise<void>;
  add: (menuItemId: string, quantity?: number) => Promise<void>;
  setQuantity: (cartItemId: string, quantity: number) => Promise<void>;
  clear: () => Promise<void>;
}

const CartContext = createContext<CartState | null>(null);

export const CartProvider = ({ children }: { children: ReactNode }) => {
  const { user } = useAuth();
  const [cart, setCart] = useState<CartDto | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Only customers have carts. Signing out has to drop the local copy too, or the
  // next person to use the browser sees the previous one's order.
  const canHaveCart = user?.role === 'customer' || user?.role === 'admin';

  const refresh = useCallback(async () => {
    if (!canHaveCart) {
      setCart(null);
      return;
    }
    setIsLoading(true);
    try {
      setCart(await api.cart());
      setError(null);
    } catch (caught) {
      setError(caught instanceof ApiRequestError ? caught.message : 'Could not load your cart.');
    } finally {
      setIsLoading(false);
    }
  }, [canHaveCart]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  const run = useCallback(async (operation: () => Promise<CartDto>) => {
    setIsLoading(true);
    try {
      setCart(await operation());
      setError(null);
    } catch (caught) {
      // Rethrown as well as recorded: a screen may want to show the conflict inline
      // (a cart from another restaurant) rather than as a banner.
      setError(caught instanceof ApiRequestError ? caught.message : 'Something went wrong.');
      throw caught;
    } finally {
      setIsLoading(false);
    }
  }, []);

  const add = useCallback(
    (menuItemId: string, quantity = 1) => run(() => api.addToCart({ menuItemId, quantity })),
    [run],
  );
  const setQuantity = useCallback(
    (cartItemId: string, quantity: number) => run(() => api.updateCartItem(cartItemId, quantity)),
    [run],
  );
  const clear = useCallback(() => run(() => api.clearCart()), [run]);

  const itemCount = useMemo(
    () => cart?.lines.reduce((total, line) => total + line.quantity, 0) ?? 0,
    [cart],
  );

  const value = useMemo<CartState>(
    () => ({ cart, itemCount, isLoading, error, refresh, add, setQuantity, clear }),
    [cart, itemCount, isLoading, error, refresh, add, setQuantity, clear],
  );

  return <CartContext.Provider value={value}>{children}</CartContext.Provider>;
};

export const useCart = (): CartState => {
  const context = useContext(CartContext);
  if (!context) throw new Error('useCart must be used inside a CartProvider.');
  return context;
};
