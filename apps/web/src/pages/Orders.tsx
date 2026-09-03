import { useCallback, useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import {
  formatCents,
  isTerminalStatus,
  ORDER_PROGRESS_STEPS,
  ORDER_STATUS_LABELS,
  type OrderDto,
  type OrderStatus,
} from '@fotg/contracts';
import { api, ApiRequestError } from '../api/client.js';
import { useAuth } from '../state/auth.js';
import { Banner, Empty, Money, Spinner, StatusBadge, Totals } from '../components/ui.js';

const formatTime = (iso: string): string =>
  new Date(iso).toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' });

export const OrderList = () => {
  const { user } = useAuth();
  const [orders, setOrders] = useState<OrderDto[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api
      .orders()
      .then((response) => setOrders(response.items))
      .catch((caught: unknown) =>
        setError(caught instanceof ApiRequestError ? caught.message : 'Could not load your orders.'),
      );
  }, []);

  const heading =
    user?.role === 'restaurant_owner' ? 'Your kitchen' : user?.role === 'courier' ? 'Deliveries' : 'Your orders';

  if (error) {
    return (
      <div className="page container">
        <h1>{heading}</h1>
        <Banner>{error}</Banner>
      </div>
    );
  }

  if (!orders) {
    return (
      <div className="page container">
        <h1>{heading}</h1>
        <Spinner label="Loading orders" />
      </div>
    );
  }

  return (
    <div className="page container">
      <h1>{heading}</h1>
      {orders.length === 0 ? (
        <Empty icon="🧾" title="Nothing here yet">
          {user?.role === 'courier'
            ? 'Orders appear here once a kitchen marks them ready for pickup.'
            : user?.role === 'restaurant_owner'
              ? 'Orders placed with your restaurants will appear here.'
              : 'Once you order something, you can follow it from here.'}
        </Empty>
      ) : (
        <div className="stack">
          {orders.map((order) => (
            <Link key={order.id} to={`/orders/${order.id}`} className="card spread" style={{ textDecoration: 'none' }}>
              <div className="stack-sm">
                <div className="row">
                  <h3>{order.restaurantName}</h3>
                  <StatusBadge status={order.status} />
                </div>
                <span className="faint">
                  #{order.reference} · {formatTime(order.placedAt)} ·{' '}
                  {order.lines.reduce((total, line) => total + line.quantity, 0)} items
                </span>
              </div>
              <Money cents={order.totals.totalCents} />
            </Link>
          ))}
        </div>
      )}
    </div>
  );
};

const ProgressTrack = ({ order }: { order: OrderDto }) => {
  // A cancelled or rejected order never reaches the end of the track, so drawing the
  // remaining steps as "still to come" would be a lie. The track stops where it stopped.
  if (order.status === 'cancelled' || order.status === 'rejected') {
    const reason = order.events.at(-1)?.reason;
    return (
      <div className="stack-sm">
        <Banner tone="error">
          {ORDER_STATUS_LABELS[order.status]}
          {reason ? ` — ${reason}` : ''}
        </Banner>
      </div>
    );
  }

  const currentIndex = ORDER_PROGRESS_STEPS.indexOf(order.status);
  const reachedAt = new Map(order.events.map((event) => [event.status, event.createdAt]));
  // A delivered order is finished, not in progress: its last step reads as done so
  // the track does not sit there looking like it is still waiting on something.
  const isComplete = order.status === 'delivered';

  return (
    <div className="track">
      {ORDER_PROGRESS_STEPS.map((step, index) => {
        const state =
          index < currentIndex || (isComplete && index === currentIndex)
            ? 'done'
            : index === currentIndex
              ? 'current'
              : 'pending';
        const timestamp = reachedAt.get(step);
        return (
          <div key={step} className={`track-step track-step-${state}`}>
            <div className="track-rail" aria-hidden="true">
              <span className="track-dot" />
              {index < ORDER_PROGRESS_STEPS.length - 1 ? <span className="track-line" /> : null}
            </div>
            <div className="track-body">
              <strong>{ORDER_STATUS_LABELS[step]}</strong>
              {timestamp ? <div className="faint">{formatTime(timestamp)}</div> : null}
            </div>
          </div>
        );
      })}
    </div>
  );
};

export const OrderDetail = () => {
  const { id = '' } = useParams();
  const { user } = useAuth();
  const [order, setOrder] = useState<OrderDto | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [isUpdating, setIsUpdating] = useState(false);

  const load = useCallback(async () => {
    try {
      setOrder(await api.order(id));
      setError(null);
    } catch (caught) {
      setError(caught instanceof ApiRequestError ? caught.message : 'Could not load that order.');
    }
  }, [id]);

  useEffect(() => {
    void load();
  }, [load]);

  // A live order changes on somebody else's screen — the kitchen's, the courier's —
  // so it is re-read on a timer. Polling stops once the order is finished, because
  // a delivered order will never change again and the request would be pure waste.
  useEffect(() => {
    if (!order || isTerminalStatus(order.status)) return;
    const timer = window.setInterval(() => void load(), 10_000);
    return () => window.clearInterval(timer);
  }, [order, load]);

  const advance = async (status: OrderStatus) => {
    setIsUpdating(true);
    try {
      setOrder(await api.setOrderStatus(id, status));
      setError(null);
    } catch (caught) {
      setError(caught instanceof ApiRequestError ? caught.message : 'Could not update the order.');
      await load();
    } finally {
      setIsUpdating(false);
    }
  };

  if (error && !order) {
    return (
      <div className="page container">
        <Empty icon="🧾" title="We could not find that order">
          {error} <Link to="/orders">Back to your orders</Link>
        </Empty>
      </div>
    );
  }

  if (!order) {
    return (
      <div className="page container">
        <Spinner label="Loading the order" />
      </div>
    );
  }

  return (
    <div className="page container">
      <div className="stack-sm">
        <Link to="/orders" className="faint" style={{ textDecoration: 'none' }}>
          ← All orders
        </Link>
        <div className="spread">
          <h1>{order.restaurantName}</h1>
          <StatusBadge status={order.status} />
        </div>
        <p className="faint">
          Order #{order.reference} · placed {formatTime(order.placedAt)}
        </p>
      </div>

      {error ? <Banner>{error}</Banner> : null}

      <div className="layout-split">
        <div className="stack">
          <section className="card stack">
            <h2>Progress</h2>
            <ProgressTrack order={order} />
            {order.estimatedReadyAt && !isTerminalStatus(order.status) ? (
              <p className="faint">Estimated ready around {formatTime(order.estimatedReadyAt)}.</p>
            ) : null}
          </section>

          {order.allowedNextStatuses.length > 0 ? (
            <section className="card stack-sm">
              <h2>{user?.role === 'customer' ? 'Change your mind?' : 'Move this order on'}</h2>
              <div className="row">
                {order.allowedNextStatuses.map((status) => (
                  <button
                    key={status}
                    type="button"
                    className={status === 'cancelled' || status === 'rejected' ? 'button-danger' : 'button-primary'}
                    disabled={isUpdating}
                    onClick={() => void advance(status)}
                  >
                    {ORDER_STATUS_LABELS[status]}
                  </button>
                ))}
              </div>
            </section>
          ) : null}

          <section className="card stack">
            <h2>What was ordered</h2>
            <div>
              {order.lines.map((line) => (
                <div key={line.id} className="menu-item">
                  <div className="stack-sm">
                    <h3>
                      {line.quantity} × {line.name}
                    </h3>
                    <span className="faint">{formatCents(line.unitPriceCents)} each</span>
                    {line.notes ? <span className="faint">Note: {line.notes}</span> : null}
                  </div>
                  <Money cents={line.lineTotalCents} />
                </div>
              ))}
            </div>
            {order.customerNotes ? (
              <p className="faint">Notes for the kitchen: {order.customerNotes}</p>
            ) : null}
          </section>
        </div>

        <aside className="sticky-aside">
          <div className="card stack">
            <h2>Total</h2>
            <Totals totals={order.totals} />
          </div>
          <div className="card stack-sm">
            <h3>Delivering to</h3>
            <p className="faint">
              {order.deliveryAddress.label}
              <br />
              {order.deliveryAddress.line1}
              {order.deliveryAddress.line2 ? (
                <>
                  <br />
                  {order.deliveryAddress.line2}
                </>
              ) : null}
              <br />
              {order.deliveryAddress.city}, {order.deliveryAddress.region} {order.deliveryAddress.postalCode}
            </p>
            {order.deliveryAddress.deliveryNotes ? (
              <p className="faint">Courier note: {order.deliveryAddress.deliveryNotes}</p>
            ) : null}
          </div>
          <div className="card stack-sm">
            <h3>History</h3>
            <ul className="stack-sm" style={{ listStyle: 'none', padding: 0, margin: 0 }}>
              {order.events.map((event) => (
                <li key={event.id} className="faint">
                  <strong>{ORDER_STATUS_LABELS[event.status]}</strong> · {event.actor} ·{' '}
                  {formatTime(event.createdAt)}
                  {event.reason ? <div>{event.reason}</div> : null}
                </li>
              ))}
            </ul>
          </div>
        </aside>
      </div>
    </div>
  );
};
