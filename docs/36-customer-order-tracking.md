# Customer order tracking and the order state machine (Module 17)

Module 16 could turn a captured payment into an order. This module decides what
may then happen to that order, records every time something does, and shows the
customer a story they can trust.

> **The mobile app displays order state. It does not decide it.**

Everything below follows from that sentence, including the things this module
deliberately did not build.

## The lifecycle, exactly

| From | May go to | Why not further |
| --- | --- | --- |
| `PLACED` | `ACCEPTED`, `REJECTED`, `CANCELLED` | — |
| `ACCEPTED` | `COOKING`, `CANCELLED` | — |
| `COOKING` | `READY` | **Not `CANCELLED`.** The food exists by now and somebody has to decide who pays for it. Nobody has. |
| `READY` | `PICKED_UP` | Module 21 owns that edge: it requires a verified pickup credential, and nothing verifies one yet. |
| `REJECTED` | — | Terminal. |
| `PICKED_UP` | — | Terminal. |
| `CANCELLED` | — | Terminal. |
| `REFUNDED` | — | **Unreachable, on purpose.** See below. |

`AWAITING_PAYMENT` and `PAYMENT_FAILED` remain Module 15's, unchanged.

**The terminal rows are empty lists, and the emptiness is the protection.**
There is no force flag, no admin override and no `allowUnsafe` parameter in
`OrderStateMachine`. A deliberate recovery workflow would be a new, separately
authorised service — not an argument somebody could pass by accident.

### Transitions that are refused, and tested by name

`PLACED → READY` · `PLACED → PICKED_UP` · `ACCEPTED → READY` ·
`COOKING → ACCEPTED` · `READY → COOKING` · `PICKED_UP → READY` ·
`REJECTED → ACCEPTED` · `CANCELLED → COOKING` · `COOKING → CANCELLED`

Each is a named test rather than a loop over "all illegal pairs". A loop proves
the table is self-consistent, which it would be even if the table were wrong.

## REFUNDED is payment state, not order state

The specification lists `REFUNDED` in the lifecycle. This module keeps it
declared and unreachable, which is the architecture the specification itself
calls preferred.

A rejected order whose money came back is **two facts on two records**:

```
order.status   = REJECTED
payment.status = REFUNDED
```

Folding them into one status forces a single string to answer two questions and
loses one of the answers — and the question it loses is always the one somebody
needs during a dispute.

**No refund workflow exists in this build.** `PaymentStatus` has no `REFUNDED`
case, nothing initiates a refund, and therefore nothing can display one. The
customer app maps the value anyway, so that a build meeting it later reads it
correctly rather than showing a bare "Payment" — but a rejected order in this
build says only that it was rejected. It does not claim a refund.

## The history is the record

`order_status_history` is append-only. There is no update path in the model and
no service that edits a row after writing it.

| Column | Reaches the customer? |
| --- | --- |
| `from_status`, `to_status`, `occurred_at` | Yes |
| `customer_safe_note` | Yes — and only when somebody wrote it deliberately |
| `source_type`, `actor_type`, `actor_id` | **No** |
| `reason_code` | **No** |
| `correlation_id` | **No** |

A customer needs to know their order was accepted, not which member of staff
pressed the button. `OrderTrackingApiTest` asserts the absence against the
serialised response rather than field by field, so a value appearing somewhere
nobody thought to check is still caught — and it asserts the fixture really
carried those values first, so the absence is a property of the presenter
rather than of the fixture.

`orders.status` and the milestone timestamps are a **denormalised cache** of
the latest history row, kept because the Orders tab must not join a history
table to sort a list. Where they disagree, the history is right and something
is broken.

### One row per order per state

The unique index on `(order_id, to_status)` is the duplicate protection. The
current lifecycle has no state an order legitimately enters twice, so a second
`ACCEPTED` row means a duplicate delivery got through — and the index refuses
it rather than putting two "Restaurant accepted your order" entries on a
timeline.

The day a state does legitimately repeat, that constraint has to be removed
deliberately. That is the point: it forces the decision to be made rather than
discovered.

## One writer, and what one call does

`OrderTransitionService::transition()`, inside one transaction:

1. lock the order row
2. **re-read its status under the lock** — not the model the caller handed in
3. return early, writing nothing, if it is already in the target state
4. refuse if the table has no such edge
5. refuse if a restaurant actor is acting on another tenant's order
6. apply the status and its milestone timestamp
7. bump `order_version`
8. append the history row
9. queue a domain event on Module 16's outbox
10. commit

Step 2 is the one that is easy to skip. A caller's `$order` may have been loaded
seconds ago, and in those seconds another worker may have moved it; validating
against a stale status is how two concurrent actors both decide their
transition is legal.

Steps 1–3 make a duplicate delivery cheap and correct. Step 8's unique index is
what holds when they are wrong.

### The actor is derived, never received

`OrderTransitionActor` has only named factories — `system()`, `payment()`,
`restaurant($operator, $restaurantId)`, `admin($user)`, `testHarness()`. Nothing
builds one from a request body. A client that could name its own source could
write `RESTAURANT` into the audit trail of an order it does not own, which
would make the trail worse than not having one.

The cross-tenant check lives in the service rather than at each call site,
because Module 14T established that a boundary checked at the call site is a
boundary somebody forgets when they add the second one. **The first restaurant
screen inherits it rather than having to remember it.**

## `order_version` exists for the client

A phone polling this order can receive two answers out of order — a slow
`COOKING` response arriving after a fast `READY` one. Comparing status strings
cannot tell which is newer without the client knowing that `COOKING` precedes
`READY`, and **it must not know that**: the lifecycle is the server's, and a
client that encodes it is wrong the moment the lifecycle changes.

A monotonically increasing integer answers *which of these is fresher* without
answering *what comes next*, which is exactly the amount a client is allowed to
know. It is bumped under the same lock as the status, so a response carrying
version N carries the status that version N is.

## The customer API

`GET /api/v1/customer/orders` — split into `active` and `past`, where "active"
comes from the transition table rather than a list kept in the controller.
Active orders sort by **soonest pickup**, because a customer with two live
orders cares about the one they must collect next, not the one they bought last.

`GET /api/v1/customer/orders/{order}` — the tracking response. Module 17
enriched this rather than adding a parallel `/tracking` route: two endpoints
returning almost the same order would drift, and the day they did a customer
would read one status in a list and another on the screen they opened from it.

**Read-only, and that is the module's central security property.** There is no
`PATCH`, no `/ready`, no `/confirm`. `OrderTrackingApiTest` walks the registered
routes and fails if any customer order route accepts a write, so a route named
something nobody predicted is still caught.

### What the timeline sends

Every step arrives with its state already decided — `COMPLETED`, `CURRENT`,
`UPCOMING` or `EXCEPTION` — and with the server's own wording for its title.

**An upcoming step carries no timestamp.** A fabricated one is the single error
a customer cannot detect and cannot recover from: it tells them their food was
ready at an hour it was not, and nothing on the screen contradicts it.

**A rejected order shows no steps it will never reach.** The happy path is
truncated where the order left it and the exception is appended in its place.
Leaving Cooking and Ready sitting ahead of a refusal tells a customer their
refused order is queued to be prepared.

### Status copy comes from the server

A phone that decided "COOKING means your food is being prepared" would need an
app-store release before the lifecycle could gain a state, and until then every
un-updated app would show a raw enum value to a customer. `status_title` and
`status_subtitle` travel with every order; the client's own labels are a
documented fallback for an older server.

Writing the tests caught this being half-done: the status hero rendered the
client's label while the timeline rendered the server's, so one screen could
show "Being prepared" above "Your food is being prepared".

## Refresh, and what it is not called

**This is temporary tracking refresh. It is not realtime, and nothing in the
code or the UI says otherwise.** Module 19 replaces the timer with a
subscription; the fastest way to end up with two realtime systems is to call
the first one realtime.

| Rule | Value | Why |
| --- | --- | --- |
| Interval | 20s, from `FOTG_ORDER_TRACKING_REFRESH_SECONDS` | A restaurant accepting an order is not a sub-second event, and the customer is usually driving |
| Floor | 5s | A mistyped define must not produce a request storm |
| Terminal orders | stop | The server says whether an order is active; the client keeps no list to go stale |
| Backgrounded | stop, one read on resume | A backgrounded app on a timer is a battery complaint |
| After failures | ×2, ×4, ×8 | A server that just refused one request is not helped by the same request from every open screen |
| Budget | 30 minutes | A screen left open overnight stops |

**No `LIVE` badge**, and a test asserts its absence. The screen says "Updated
just now" instead.

### Cost control

A tracking refresh reads internal order and payment state only. Twenty
consecutive refreshes make **zero** calls to Google and **zero** to Razorpay,
and the test asserting it is also a correctness test: this project's provider
bindings refuse every call, so a refresh that reached one would throw rather
than quietly cost money.

Payment state comes from Module 15's own record. Nothing re-fetches a provider
on a screen refresh.

## Offline

A cached order stays on screen, clearly marked stale, with what was last read
and a note that it may have changed. Replacing a real order with an error page
because one refresh timed out on a motorway loses the customer the information
they opened the screen for.

Nothing about the cached state is presented as current, and no timeline entry
is invented while offline.

## The QA transition harness

The restaurant dashboard that will legitimately accept, cook and finish orders
is several modules away, and this module's tracking cannot be verified against
an order that can never leave `PLACED`.

`dev:order-transition` is a console command. The alternative was a
customer-facing endpoint that moves an order, which would be a critical
security defect however carefully it was worded.

- No route, no controller, no HTTP surface.
- Refuses to run outside `local` and `testing`, as its first act.
- Records `source_type = TEST_HARNESS`, so a production database can be
  **queried** for rows that should not exist rather than trusted not to have
  them.
- Validates through `OrderTransitionService` like every other caller. An
  illegal transition asked for there is refused exactly as it would be
  anywhere: a harness that could force one would let QA produce states the
  product cannot reach, and then those states would get designed for.

## What this module does not do

- **No realtime.** Module 19.
- **No live ETA, no GPS, no arrival prediction.** Module 18. The pickup card
  says "Requested pickup … Not a live estimate" so the screen cannot be read as
  claiming one.
- **No push notifications.** Module 20.
- **No pickup verification.** The credential is minted and its availability is
  reported; nothing scans or redeems one, and nothing marks an order picked up
  from the customer app. Module 21.
- **No restaurant UI.** The service foundation exists and is tested with
  controlled identities; the screens that will use it do not.
- **No customer cancellation.** No cancellation policy has been agreed, so
  there is no button. Adding one because other food apps have one would be
  inventing commercial rules.
- **No order history, reorder or invoice.** Module 22. The list is capped at 50
  and says so.

## Handoffs

**Module 18 (ETA).** The tracking response keeps status state, timing state,
payment state and credential state in separate objects, so an ETA can be added
beside the pickup window without touching the lifecycle. `OrderTimelineService`
produces the status story; nothing in it computes a time.

**Module 19 (realtime).** Every transition already queues a domain event —
`OrderAccepted`, `OrderRejected`, `OrderCookingStarted`, `OrderReady`,
`OrderPickedUp`, `OrderCancelled` — on Module 16's outbox, keyed
`{order_uuid}:{status}` so a duplicate is refused by the same unique index the
rest of the outbox relies on. A realtime layer consumes those rather than
polling, and the client's `order_version` handling already tolerates updates
arriving out of order.

## How stale is too stale (KI-031, added after the module closed)

The screen used to show a cached order behind an "it may have changed" banner
with no upper bound. Half an hour old and two days old rendered identically, and
`orderTrackingUpdatedJustNow` / `orderTrackingUpdatedMinutesAgo` had been
written into `AppStrings` and wired to nothing.

Three rules now:

1. **The age is always said.** `OrderTrackingState.ageAt(now)` measures it and
   `AppStrings.orderTrackingUpdatedAgo(Duration)` says it, in one phrase used by
   both the hero and the offline banner so they cannot disagree. Coarse on
   purpose: just now → minutes → hours → more than a day.
2. **Past `TrackingConfig.vouchedFor` the status is withheld.** The hero and the
   timeline come off the screen; an explicit "we can't tell you where this order
   is right now" replaces them, carrying the age and the order number. The
   pickup window, restaurant, items and amount paid stay, because they do not
   change while nobody is looking.
3. **The bound is `pollingBudget`, not a new number.** Thirty minutes is how
   long this app is willing to keep a status fresh; past that it has already
   stopped checking, and vouching for a status it decided not to check is the
   contradiction. A test asserts the constants are equal.

`trackingClockProvider` exists so this is testable at the second rather than
described in a comment. It is the *device* clock and it is used only for "how
long ago" — every instant a customer is shown still comes from the server on the
restaurant's clock, which is Module 13's rule and unchanged.

A device clock that jumps backwards reads as "just now" rather than as a
negative age, so a timezone change cannot blank a fresh screen.
