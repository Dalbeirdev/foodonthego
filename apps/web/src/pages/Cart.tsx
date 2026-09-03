import { Link } from 'react-router-dom';
import { useCart } from '../state/cart.js';
import { Banner, Empty, Money, QuantityStepper, Totals } from '../components/ui.js';
import { formatCents } from '@fotg/contracts';

export const Cart = () => {
  const { cart, isLoading, error, setQuantity, clear } = useCart();

  if (!cart || cart.lines.length === 0) {
    return (
      <div className="page container">
        <h1>Your cart</h1>
        <Empty icon="🛒" title="Your cart is empty">
          <Link to="/">Find something to eat</Link>
        </Empty>
      </div>
    );
  }

  const hasUnavailable = cart.lines.some((line) => !line.isAvailable);
  const shortfall = cart.minimumOrderCents - cart.totals.subtotalCents;

  return (
    <div className="page container">
      <div className="spread">
        <h1>Your cart</h1>
        <button type="button" className="button-ghost" onClick={() => void clear()} disabled={isLoading}>
          Empty cart
        </button>
      </div>
      <p className="muted">
        From <strong>{cart.restaurantName}</strong>
      </p>

      {error ? <Banner>{error}</Banner> : null}
      {hasUnavailable ? (
        <Banner tone="info">
          Something in your cart has sold out since you added it. It is not included in the total, and you
          will need to remove it before you can order.
        </Banner>
      ) : null}

      <div className="layout-split">
        <div className="card stack">
          {cart.lines.map((line) => (
            <div key={line.id} className={`menu-item${line.isAvailable ? '' : ' menu-item-unavailable'}`}>
              <div className="stack-sm">
                <h3>{line.name}</h3>
                <span className="faint">{formatCents(line.unitPriceCents)} each</span>
                {line.notes ? <span className="faint">Note: {line.notes}</span> : null}
                {!line.isAvailable ? <span className="badge badge-danger">Sold out</span> : null}
              </div>
              <div className="stack-sm" style={{ justifyItems: 'end' }}>
                <Money cents={line.lineTotalCents} />
                <QuantityStepper
                  quantity={line.quantity}
                  disabled={isLoading}
                  label={line.name}
                  onChange={(next) => void setQuantity(line.id, Math.max(0, next))}
                />
              </div>
            </div>
          ))}
        </div>

        <aside className="sticky-aside">
          <div className="card stack">
            <h2>Order summary</h2>
            <Totals totals={cart.totals} note="A tip can be added at checkout." />
            {!cart.meetsMinimum ? (
              <Banner tone="info">
                Add {formatCents(shortfall)} more to reach this restaurant&rsquo;s{' '}
                {formatCents(cart.minimumOrderCents)} minimum.
              </Banner>
            ) : null}
            <Link
              to="/checkout"
              className="button button-primary button-block"
              aria-disabled={!cart.meetsMinimum || hasUnavailable}
              onClick={(event) => {
                if (!cart.meetsMinimum || hasUnavailable) event.preventDefault();
              }}
            >
              Go to checkout
            </Link>
            <Link to={`/restaurants/${cart.restaurantId}`} className="button button-ghost button-block">
              Add more from {cart.restaurantName}
            </Link>
          </div>
        </aside>
      </div>
    </div>
  );
};
