import type { ReactNode } from 'react';
import { formatCents, ORDER_STATUS_LABELS, type OrderStatus, type OrderTotals } from '@fotg/contracts';

export const Money = ({ cents }: { cents: number }) => <span className="price">{formatCents(cents)}</span>;

export const Banner = ({ tone = 'error', children }: { tone?: 'error' | 'info' | 'success'; children: ReactNode }) => (
  <p className={`banner banner-${tone}`} role={tone === 'error' ? 'alert' : 'status'}>
    {children}
  </p>
);

export const Empty = ({ icon, title, children }: { icon: string; title: string; children?: ReactNode }) => (
  <div className="empty">
    <span className="empty-icon" aria-hidden="true">
      {icon}
    </span>
    <h2>{title}</h2>
    {children ? <p className="muted">{children}</p> : null}
  </div>
);

export const Spinner = ({ label }: { label: string }) => (
  <div className="stack" aria-busy="true" aria-live="polite">
    <span className="visually-hidden">{label}</span>
    <div className="skeleton" style={{ height: 80 }} />
    <div className="skeleton" style={{ height: 80 }} />
    <div className="skeleton" style={{ height: 80 }} />
  </div>
);

const STATUS_TONE: Record<OrderStatus, string> = {
  pending: 'badge-warning',
  confirmed: 'badge-accent',
  preparing: 'badge-accent',
  ready_for_pickup: 'badge-accent',
  out_for_delivery: 'badge-accent',
  delivered: 'badge-open',
  cancelled: 'badge-closed',
  rejected: 'badge-danger',
};

export const StatusBadge = ({ status }: { status: OrderStatus }) => (
  <span className={`badge ${STATUS_TONE[status]}`}>{ORDER_STATUS_LABELS[status]}</span>
);

/**
 * Prints the breakdown exactly as the server computed it. Nothing here re-adds the
 * numbers: if the display and the charge could ever disagree, this is where it
 * would happen, so the component's whole job is to not do arithmetic.
 */
export const Totals = ({ totals, note }: { totals: OrderTotals; note?: string }) => (
  <div className="totals">
    <div className="totals-row">
      <span>Subtotal</span>
      <Money cents={totals.subtotalCents} />
    </div>
    <div className="totals-row">
      <span>Delivery</span>
      <Money cents={totals.deliveryFeeCents} />
    </div>
    <div className="totals-row">
      <span>Service fee</span>
      <Money cents={totals.serviceFeeCents} />
    </div>
    <div className="totals-row">
      <span>Tax</span>
      <Money cents={totals.taxCents} />
    </div>
    {totals.tipCents > 0 ? (
      <div className="totals-row">
        <span>Tip</span>
        <Money cents={totals.tipCents} />
      </div>
    ) : null}
    <div className="totals-row totals-row-final">
      <span>Total</span>
      <Money cents={totals.totalCents} />
    </div>
    {note ? <p className="faint">{note}</p> : null}
  </div>
);

export const QuantityStepper = ({
  quantity,
  onChange,
  disabled,
  label,
}: {
  quantity: number;
  onChange: (next: number) => void;
  disabled?: boolean;
  label: string;
}) => (
  <div className="qty">
    <button
      type="button"
      onClick={() => onChange(quantity - 1)}
      disabled={disabled}
      aria-label={quantity === 1 ? `Remove ${label}` : `One fewer ${label}`}
    >
      −
    </button>
    <span aria-label={`Quantity of ${label}`}>{quantity}</span>
    <button
      type="button"
      onClick={() => onChange(quantity + 1)}
      disabled={disabled || quantity >= 50}
      aria-label={`One more ${label}`}
    >
      +
    </button>
  </div>
);

/**
 * Stands in for a photograph we do not have. A generic grey frame at 16:9 is a
 * promise of an image that never loads; a small tile carrying something specific
 * to the cuisine at least tells the eye which card is which while scanning.
 */
const CUISINE_ICONS: Record<string, string> = {
  american: '🍟', bakery: '🥐', breakfast: '🥞', burgers: '🍔', chinese: '🥡',
  dessert: '🍰', greek: '🥙', indian: '🍛', italian: '🍝', japanese: '🍣',
  korean: '🍲', mediterranean: '🫒', mexican: '🌮', pizza: '🍕', sandwiches: '🥪',
  seafood: '🦐', thai: '🍜', vegan: '🥗', vietnamese: '🍜',
};

export const CuisineTile = ({ cuisine }: { cuisine: string }) => (
  <span className="cuisine-tile" aria-hidden="true">
    {CUISINE_ICONS[cuisine] ?? '🍽️'}
  </span>
);
