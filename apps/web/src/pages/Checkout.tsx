import { useState, type FormEvent } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { formatCents } from '@fotg/contracts';
import { api, ApiRequestError } from '../api/client.js';
import { useCart } from '../state/cart.js';
import { Banner, Empty, Totals } from '../components/ui.js';

const TIP_PRESETS = [0, 10, 15, 20] as const;

export const Checkout = () => {
  const navigate = useNavigate();
  const { cart, refresh } = useCart();
  const [tipPercent, setTipPercent] = useState<number>(15);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (!cart || cart.lines.length === 0) {
    return (
      <div className="page container">
        <h1>Checkout</h1>
        <Empty icon="🛒" title="There is nothing to check out">
          <Link to="/">Find something to eat</Link>
        </Empty>
      </div>
    );
  }

  const tipCents = Math.round((cart.totals.subtotalCents * tipPercent) / 100);
  // Shown, not charged: the server recomputes every figure and rejects the order if
  // this preview and its own arithmetic disagree.
  const previewTotal = cart.totals.totalCents + tipCents;

  const submit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setIsSubmitting(true);
    setError(null);

    const form = new FormData(event.currentTarget);
    const address = {
      label: String(form.get('label') || 'Home'),
      line1: String(form.get('line1') || ''),
      city: String(form.get('city') || ''),
      region: String(form.get('region') || ''),
      postalCode: String(form.get('postalCode') || ''),
      ...(form.get('line2') ? { line2: String(form.get('line2')) } : {}),
      ...(form.get('deliveryNotes') ? { deliveryNotes: String(form.get('deliveryNotes')) } : {}),
    };

    try {
      const order = await api.placeOrder({
        address,
        tipCents,
        expectedTotalCents: previewTotal,
        ...(form.get('customerNotes') ? { customerNotes: String(form.get('customerNotes')) } : {}),
      });
      await refresh();
      navigate(`/orders/${order.id}`, { replace: true });
    } catch (caught) {
      if (caught instanceof ApiRequestError && caught.code === 'conflict') {
        // Refresh so the customer is looking at the new figures while they read this.
        await refresh();
      }
      setError(caught instanceof ApiRequestError ? caught.message : 'Could not place your order.');
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div className="page container">
      <h1>Checkout</h1>
      <p className="muted">
        From <strong>{cart.restaurantName}</strong>
      </p>

      {error ? <Banner>{error}</Banner> : null}

      <form onSubmit={(event) => void submit(event)} className="layout-split">
        <div className="stack">
          <section className="card stack">
            <h2>Where is it going?</h2>
            <fieldset>
              <label>
                Label
                <input name="label" defaultValue="Home" maxLength={60} />
              </label>
              <label>
                Street address
                <input name="line1" required maxLength={160} autoComplete="address-line1" />
              </label>
              <label>
                Apartment, floor (optional)
                <input name="line2" maxLength={160} autoComplete="address-line2" />
              </label>
              <div className="row" style={{ alignItems: 'start' }}>
                <label style={{ flex: '2 1 180px' }}>
                  City
                  <input name="city" required maxLength={80} autoComplete="address-level2" />
                </label>
                <label style={{ flex: '1 1 90px' }}>
                  State
                  <input name="region" required maxLength={80} autoComplete="address-level1" />
                </label>
                <label style={{ flex: '1 1 110px' }}>
                  ZIP
                  <input name="postalCode" required maxLength={16} autoComplete="postal-code" />
                </label>
              </div>
              <label>
                Notes for the courier (optional)
                <input name="deliveryNotes" maxLength={400} placeholder="Gate code, which door…" />
              </label>
            </fieldset>
          </section>

          <section className="card stack">
            <h2>Anything for the kitchen?</h2>
            <label>
              <span className="visually-hidden">Notes for the restaurant</span>
              <textarea name="customerNotes" rows={3} maxLength={500} placeholder="Allergies, no onions…" />
            </label>
          </section>

          <section className="card stack">
            <h2>Tip</h2>
            <p className="faint">Goes to your courier. It is not taxed.</p>
            <div className="row">
              {TIP_PRESETS.map((percent) => (
                <button
                  key={percent}
                  type="button"
                  className={percent === tipPercent ? 'button-primary' : 'button-secondary'}
                  aria-pressed={percent === tipPercent}
                  onClick={() => setTipPercent(percent)}
                >
                  {percent === 0 ? 'No tip' : `${percent}%`}
                </button>
              ))}
            </div>
          </section>
        </div>

        <aside className="sticky-aside">
          <div className="card stack">
            <h2>Order summary</h2>
            <Totals totals={{ ...cart.totals, tipCents, totalCents: previewTotal }} />
            <p className="faint">
              {cart.lines.reduce((total, line) => total + line.quantity, 0)} items ·{' '}
              {formatCents(previewTotal)}
            </p>
            <button type="submit" className="button-primary button-block" disabled={isSubmitting}>
              {isSubmitting ? 'Placing your order…' : `Place order · ${formatCents(previewTotal)}`}
            </button>
            <p className="faint">
              No payment is taken. This deployment has no payment provider connected — see the README.
            </p>
          </div>
        </aside>
      </form>
    </div>
  );
};
