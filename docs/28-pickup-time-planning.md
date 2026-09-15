# 28 — Pickup time planning

Module 13. A cart is a list of food. This module answers the question that turns
it into a plan:

> **When can this customer realistically pick up this exact cart from this
> restaurant while travelling on this route?**

Everything here is decided on the server. Flutter renders what Laravel returns
and decides nothing about feasibility.

---

## This is Pickup Planning V1, not the ETA engine

Saying so plainly, because the difference will matter to whoever reads this next.

**What Module 13 computes.** A deterministic, explainable plan from data the
platform already holds: the selected route's travel time to the restaurant, the
cart's preparation requirement, an operational buffer, the restaurant's opening
hours in its own timezone, and the server's clock.

**What it does not.** No live GPS. No traffic refreshed as you drive. No idea
whether the customer has actually left. No early/late detection, no
cooking-start signal, no kitchen queue. Those belong to the ETA engine in a
later module.

The boundary is drawn in code, not only in prose: arrival comes from an
`ArrivalEstimateProvider` interface. Today the only implementation reads the
planned route. When the ETA engine arrives it implements the same interface and
pickup planning does not change.

### The planning reference, stated exactly

`trips` has no departure-time column, and Module 13 does not track the customer.
So the reference is **server-now**: the plan assumes the customer sets off at the
moment of planning.

```
estimated_arrival_at = server_now + time_ahead_seconds
```

`time_ahead_seconds` is Module 07's figure — the selected route's
traffic-aware duration multiplied by the fraction of the route at which the
restaurant sits. A customer who plans at 3pm and leaves at 4pm has an estimate
an hour out, and nothing in V1 can know that. **This is the single largest
approximation in the module** and the first thing the ETA engine replaces.

---

## Terminology

Used precisely, and not interchangeably.

| Term | Meaning |
| --- | --- |
| **Estimated arrival time** | When the customer would reach the restaurant, from route data |
| **Estimated ready time** | The earliest the kitchen could have this cart done |
| **Recommended pickup time** | The window the backend picks as the best alignment of the two |
| **Selected pickup time** | The window the customer chose |
| **Pickup window** | A selectable interval, e.g. 4:10–4:20 PM |

### It is a request, not a promise

Until Module 14 creates an order and a restaurant accepts it, nothing here is
guaranteed. The copy says **"Requested pickup"** and **"Pickup around 4:10 PM"**.
It never says "Your food will be ready at 4:10" — that is a promise no part of
this system is yet in a position to make.

---

## Preparation time

### Precedence

For each cart line, the first of these that is present wins:

1. the chosen **variant's** `preparation_minutes`
2. the **menu item's** `preparation_minutes`
3. the **restaurant's** `default_preparation_minutes`
4. the **platform** fallback, `PICKUP_FALLBACK_PREP_MINUTES`

All four already exist in the schema except the last, which is configuration.
Every fall past step 2 is logged with the line and the level reached, because a
menu that quietly relies on a platform default is a menu nobody has finished
setting up.

**Never zero as a silent default.** A missing prep time is missing data, not a
dish that takes no time.

### Modifiers do not affect preparation

There is no preparation metadata on `menu_modifier_options` — the column does
not exist. So Module 13 does not pretend Extra Paneer adds five minutes. If that
metadata is ever added, this is the place to consume it.

### The cart's requirement is the maximum, not the sum

```
cart_preparation_minutes = max(preparation_minutes of each line)
```

A kitchen cooks several dishes at once. Summing them would tell a customer their
two-dish order takes forty minutes when the kitchen has it done in twenty-five,
and the recommendation would push them into needlessly late pickups.

### Quantity does not multiply preparation

Three portions of a fifteen-minute dish is fifteen minutes, not forty-five. A
tandoor holds more than one skewer. **V1 has no evidence about batch sizes**, and
inventing a multiplier would be inventing a number. Quantity therefore does not
enter the preparation calculation at all, and this paragraph exists so that the
absence is a decision rather than an oversight.

---

## Operational buffer and lead time

```
earliest_ready_at = server_now
                  + cart_preparation_minutes
                  + operational_buffer_minutes
```

then

```
earliest_ready_at = max(earliest_ready_at, server_now + minimum_lead_minutes)
```

The buffer is packing, bagging and handing over. It is a **restaurant-level
override falling back to a platform default**, applied exactly once, and it is
**not a charge** — it moves time and never money.

---

## Recommended pickup

```
recommended_centre = max(estimated_arrival_at, earliest_ready_at)
```

Then rounded **forward** to the next valid slot boundary. Forward, always:
rounding back would recommend a time the kitchen cannot meet.

The three cases the spec names fall out of that single line:

| Case | What happens |
| --- | --- |
| Arrival later than ready | `arrival` wins — food is not cooked an hour early to sit under a lamp |
| Arrival earlier than ready | `earliest_ready` wins — and the screen says how much longer the food needs |
| They align | Either; the answer is the same. This is the experience the product is for |

---

## Windows

Slots are generated on a configurable interval with a configurable duration, and
only where every one of these holds:

- at or after `earliest_ready_at`
- at or after `server_now + minimum_lead_minutes`
- entirely inside a restaurant opening window, **including the end of the window**
- at or before the last pickup cutoff before closing
- within `MAX_PICKUP_HORIZON_MINUTES` of now
- the restaurant is open *and* accepting orders

A window whose end falls after closing is not offered. Neither is one that
starts inside an opening gap. Overnight hours (18:00–02:00) are handled by the
timezone-aware interval arithmetic rather than by special-casing midnight.

### Closing, and the cutoff

The schema has no `last_order_at`. Rather than invent an undocumented cutoff,
V1 uses one configurable rule — `PICKUP_LAST_ORDER_BEFORE_CLOSE_MINUTES`,
defaulting to **0** — so that by default the only constraint is the closing time
itself. A restaurant that wants a real last-order rule gets one when the operator
module can set it.

### Timezone

Every hours comparison happens in the restaurant's own IANA zone
(`restaurants.timezone`, e.g. `Asia/Kolkata`), never at a fixed offset. Windows
are returned as ISO 8601 instants with offset, plus the zone name, so the client
formats without doing arithmetic.

---

## Options are opaque and short-lived

The client never sends a timestamp. It sends an **option id**, and the server
resolves it.

Each generated option is stored in Redis under a random opaque id, scoped to
customer, cart, trip and restaurant, with a TTL. Selecting resolves the id and
re-checks every condition; a client cannot invent a window, edit one, borrow
another customer's, or replay an expired one, because there is no timestamp in
the request to tamper with.

MySQL remains authoritative for what the customer actually chose. Redis holds
only the short-lived menu of what they *could* choose.

## Binding, and what makes a selection stale

A selection is tied to a **planning fingerprint** over:

- cart version
- selected route uuid and its `calculated_at`
- restaurant id, its accepting-orders flag and its opening-hours fingerprint
- the pickup configuration version

Change any of them and the stored selection reads `STALE` rather than being
silently honoured. Adding a slow dish, switching route, or a restaurant editing
its hours all invalidate a plan that was made under different facts.

`carts.version` is new in this module and increments on every mutation of a
cart's contents — which is also what lets a price-only change be told apart from
a timing-relevant one.

### Selection status

`NONE`, `SELECTED`, `STALE`, `INVALID`. Deliberately not order statuses; no
order exists.

---

## Route freshness

`trip_routes.calculated_at` against `ROUTE_ESTIMATE_MAX_AGE_SECONDS`.

**Fresh: reuse. Stale: refuse, and say so.** V1 does not silently refresh a
route on the customer's behalf — a route call is billed, and one triggered by
opening a screen is a cost nobody asked for. The response sets
`requires_route_refresh: true` and the screen offers **Refresh journey**, which
goes through Module 06's existing service. There is no second routing engine.

**Cost control.** Generating slots, switching between them, selecting one, and
pre-checkout validation call no routing provider at all. The only provider call
is an explicit refresh the customer asked for.

---

## Pre-checkout validation

A read that computes and creates nothing. It re-runs Module 12's full cart
revalidation and then checks the pickup layer, returning `ready_for_checkout`
plus structured issues.

It never returns true with an unreviewed price rise, a sold-out line, a paused
kitchen, a stale route, a stale pickup selection, or no selection at all.

**No order is created. No payment is created. No capacity is reserved.** A
pickup selection is customer intent; Module 14 revalidates everything again.

---

## API

```
POST /api/v1/customer/trips/{trip}/cart/pickup-options
PUT  /api/v1/customer/trips/{trip}/cart/pickup-selection      { pickup_option_id }
POST /api/v1/customer/trips/{trip}/cart/pre-checkout-validate
```

`POST` for options because it is a calculation over live state, not a resource
fetch — and because its result is deliberately short-lived.

What the response explains: travel minutes, preparation minutes, buffer minutes,
estimated arrival, earliest ready, the recommended window and the alternatives,
route freshness. What it does not: internal staffing rules, capacity figures,
ranking formulas, provider credentials, or anything from an operator's private
columns.

---

## Not in this module

Checkout, payment, order creation, order numbers, pickup codes, restaurant
accept/reject, cooking and ready workflows, live GPS ETA, early/late detection,
WebSockets, push notifications, QR pickup, and multi-day scheduling.

Module 13 ends when a customer has a valid cart, a feasible selected pickup
window, current pre-checkout validation, and a backend-generated
`ready_for_checkout` — and not one step further.
