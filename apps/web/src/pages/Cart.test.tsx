import { beforeEach, describe, expect, it, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import type { CartDto } from '@fotg/contracts';
import { Cart } from './Cart.js';

const setQuantity = vi.fn();
const clear = vi.fn();
let cart: CartDto | null = null;

vi.mock('../state/cart.js', () => ({
  useCart: () => ({ cart, isLoading: false, error: null, setQuantity, clear }),
}));

const makeCart = (overrides: Partial<CartDto> = {}): CartDto => ({
  id: 'cart-1',
  restaurantId: 'r-1',
  restaurantName: 'Sopra Pizzeria',
  lines: [
    {
      id: 'line-1',
      menuItemId: 'item-1',
      name: 'Margherita',
      unitPriceCents: 1450,
      quantity: 2,
      notes: null,
      lineTotalCents: 2900,
      isAvailable: true,
    },
  ],
  totals: {
    subtotalCents: 2900,
    deliveryFeeCents: 299,
    serviceFeeCents: 145,
    taxCents: 284,
    tipCents: 0,
    totalCents: 3628,
  },
  minimumOrderCents: 1500,
  meetsMinimum: true,
  ...overrides,
});

const renderCart = () =>
  render(
    <MemoryRouter>
      <Cart />
    </MemoryRouter>,
  );

beforeEach(() => {
  vi.clearAllMocks();
  cart = makeCart();
});

describe('Cart', () => {
  it('shows the lines and the restaurant they came from', () => {
    renderCart();
    expect(screen.getByText('Margherita')).toBeInTheDocument();
    expect(screen.getByText('Sopra Pizzeria')).toBeInTheDocument();
    expect(screen.getByText('$36.28')).toBeInTheDocument();
  });

  it('offers checkout when the minimum is met', () => {
    renderCart();
    expect(screen.getByText('Go to checkout')).toHaveAttribute('aria-disabled', 'false');
  });

  it('blocks checkout and says how much more is needed below the minimum', () => {
    cart = makeCart({
      meetsMinimum: false,
      minimumOrderCents: 5000,
      totals: { ...makeCart().totals, subtotalCents: 2900 },
    });
    renderCart();

    expect(screen.getByText('Go to checkout')).toHaveAttribute('aria-disabled', 'true');
    expect(screen.getByText(/\$21\.00 more/)).toBeInTheDocument();
  });

  it('blocks checkout while a sold-out item is still in the cart', () => {
    const base = makeCart();
    cart = makeCart({ lines: [{ ...base.lines[0]!, isAvailable: false }] });
    renderCart();

    expect(screen.getByText('Sold out')).toBeInTheDocument();
    expect(screen.getByText('Go to checkout')).toHaveAttribute('aria-disabled', 'true');
  });

  it('removes a line by stepping the quantity to zero', async () => {
    const user = userEvent.setup();
    renderCart();

    await user.click(screen.getByLabelText('One fewer Margherita'));
    expect(setQuantity).toHaveBeenCalledWith('line-1', 1);
  });

  it('shows the empty state rather than a broken summary', () => {
    cart = makeCart({ lines: [] });
    renderCart();
    expect(screen.getByText('Your cart is empty')).toBeInTheDocument();
    expect(screen.queryByText('Go to checkout')).not.toBeInTheDocument();
  });
});
