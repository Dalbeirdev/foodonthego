/**
 * The order lifecycle, and who is allowed to move it along.
 *
 * Order status is the one piece of state three different parties all want to
 * change — the customer cancels, the restaurant accepts and cooks, the courier
 * delivers — so it is defined once, here, and both the API and the UI read the
 * same table. A transition that is not listed is not possible, which is what
 * stops a delivered order being cancelled or a rejected one being cooked.
 */
export const ORDER_STATUSES = [
  'pending',
  'confirmed',
  'preparing',
  'ready_for_pickup',
  'out_for_delivery',
  'delivered',
  'cancelled',
  'rejected',
] as const;

export type OrderStatus = (typeof ORDER_STATUSES)[number];

/** Who is asking for the change. Not the same as the user's role: it is their role *on this order*. */
export const ORDER_ACTORS = ['customer', 'restaurant', 'courier', 'admin'] as const;
export type OrderActor = (typeof ORDER_ACTORS)[number];

export const TERMINAL_ORDER_STATUSES: readonly OrderStatus[] = [
  'delivered',
  'cancelled',
  'rejected',
];

export const isTerminalStatus = (status: OrderStatus): boolean =>
  TERMINAL_ORDER_STATUSES.includes(status);

type TransitionTable = Readonly<Record<OrderStatus, Readonly<Partial<Record<OrderStatus, readonly OrderActor[]>>>>>;

/**
 * `from -> to -> actors permitted to make that move`.
 *
 * `admin` is deliberately listed on every transition rather than special-cased in
 * the checking function, so that reading this table tells you the whole truth
 * about who can do what.
 */
export const ORDER_TRANSITIONS: TransitionTable = {
  pending: {
    confirmed: ['restaurant', 'admin'],
    rejected: ['restaurant', 'admin'],
    cancelled: ['customer', 'admin'],
  },
  confirmed: {
    preparing: ['restaurant', 'admin'],
    cancelled: ['customer', 'restaurant', 'admin'],
  },
  preparing: {
    ready_for_pickup: ['restaurant', 'admin'],
    // Past this point the customer can no longer cancel on their own: the food is
    // being made, and somebody has to absorb the cost of it. The restaurant still
    // can, because a kitchen that has run out of an ingredient must have a way out.
    cancelled: ['restaurant', 'admin'],
  },
  ready_for_pickup: {
    out_for_delivery: ['courier', 'admin'],
    cancelled: ['restaurant', 'admin'],
  },
  out_for_delivery: {
    delivered: ['courier', 'admin'],
  },
  delivered: {},
  cancelled: {},
  rejected: {},
};

export const allowedTransitions = (from: OrderStatus): OrderStatus[] =>
  Object.keys(ORDER_TRANSITIONS[from]) as OrderStatus[];

export const canTransition = (from: OrderStatus, to: OrderStatus, actor: OrderActor): boolean =>
  ORDER_TRANSITIONS[from][to]?.includes(actor) ?? false;

/**
 * The customer-facing label. The internal name is not always the useful one:
 * `ready_for_pickup` means something to the restaurant and nothing to the person
 * waiting at home, who wants to know a courier is coming.
 */
export const ORDER_STATUS_LABELS: Readonly<Record<OrderStatus, string>> = {
  pending: 'Waiting for the restaurant',
  confirmed: 'Order accepted',
  preparing: 'Being prepared',
  ready_for_pickup: 'Ready — waiting for a courier',
  out_for_delivery: 'On its way to you',
  delivered: 'Delivered',
  cancelled: 'Cancelled',
  rejected: 'Declined by the restaurant',
};

/** The steps shown on the tracking bar, in order. Cancellation is not a step; it ends the bar. */
export const ORDER_PROGRESS_STEPS: readonly OrderStatus[] = [
  'pending',
  'confirmed',
  'preparing',
  'ready_for_pickup',
  'out_for_delivery',
  'delivered',
];
