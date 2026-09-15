# 29 — Checkout, commercial calculation and payment readiness

Module 14. The last screen before money changes hands, and the module that
deliberately stops one step short of it.

It answers one question, and the whole design follows from who is allowed to
answer it:

> If the customer proceeds to payment right now, exactly what is being
> purchased, for what pickup time, at what authoritative amount, and is all of
> it still true?

**The server answers. The client renders the answer.** Not "the client proposes
a total and the server checks it" — there is no field in the request a total
could arrive in.

---

## What Module 14 is not

A checkout quote is **not** an order, **not** a Razorpay order, and **not** a
payment. Nothing in this module creates any of the three, and tests assert the
tables for them do not exist.

The statuses reflect that: `ACTIVE`, `STALE`, `EXPIRED`, `CONSUMED`. Borrowing
`PENDING` or `CONFIRMED` from an order lifecycle would make a quote look like
something it is not, and would be the first step towards code treating it as one.

---

## The flow

```
valid cart → valid pickup selection → pre-checkout validation
   → checkout prepare → commercial calculation → short-lived quote
   → payment readiness → STOP
```

Module 15 picks up from the last arrow.

---

## Commercial calculation

### One place money is worked out, still

`CommercialCalculationService` does **not** re-implement tax or fees. Module 12's
`CartTotalsService` remains the only thing in this project that turns a cart into
a total, and the commercial service consumes it.

A second implementation would be a second answer, and the day the two disagree
the customer is charged by whichever one happens to run. What Module 14 adds is
not arithmetic — it is **presentation of provenance**: which components are
actually configured, and which are simply absent.

### Configured is not the same as zero

This is the distinction the module exists to get right.

| State | Meaning | On the wire |
| --- | --- | --- |
| Not configured | Nobody has set this. No decision exists. | **Absent** — no row |
| Configured as zero | Somebody set it, and set it to nothing | A row reading zero |
| Configured, non-zero | Somebody set it | A row with the amount |

A restaurant whose `tax_rate_bps` is `null` has no tax rule. One whose
`tax_rate_bps` is `0` has a rule that says nought. Those are different facts and
the response says so, because a screen showing "Tax ₹0.00" tells a customer a
decision was made when none was.

### What is configured today

Read from live configuration rather than asserted here:

| Component | Source | Default |
| --- | --- | --- |
| Items subtotal | the cart's own lines | always present |
| Tax | `restaurants.tax_rate_bps`, else `CART_TAX_RATE_BPS` | **not configured** |
| Packaging fee | `restaurants.packaging_fee_minor` | **not configured** |
| Platform fee | `CART_PLATFORM_FEE_MINOR` | **not configured** |
| Discount | — | **no mechanism exists** |
| Coupon | — | **no mechanism exists** |
| Rounding adjustment | — | **not needed**: integer minor units throughout |

So with nothing configured, the payable total equals the items subtotal.

**That means "no additional charges are currently configured". It does not mean
"no tax is legally applicable."** The mechanism is built and exercised with
non-zero values in tests; the figures are a business input.

> **COMMERCIAL POLICY PRODUCTION READINESS = PENDING CLIENT DECISION**

Module 14's implementation can be complete while that stays open. The dependency
is not hidden and is repeated in the completion report, the module status and
the known-issues register.

### Money safety

Integer minor units end to end, through the existing `Money` value object. No
float touches an authoritative figure. Tax is basis points on the subtotal,
rounded half up, once — the same rule Module 12 established, for the same reason:
per-line rounding drifts by amounts a customer cannot reconcile.

---

## The quote

`checkout_quotes` holds a short-lived, server-written record of exactly what was
offered.

Every amount column is an integer of minor units. The `*_configured` companions
are what let the response distinguish an absent component from a zero one
without the client inferring it.

### TTL

`CHECKOUT_QUOTE_TTL_MINUTES`, default **10 minutes**.

Short on purpose. Prices change, stock changes, a kitchen pauses, a pickup window
passes. A quote that outlived those would be a promise nobody checked.

### Fingerprint

A quote is bound to a hash over: customer, cart, **cart version**, restaurant,
trip, the selected route's uuid and `calculated_at`, the pickup selection
(window and its own planning fingerprint), the commercial-rule version, and the
currency.

Change any of them and the quote reads `STALE` rather than being honoured.

`COMMERCIAL_RULE_VERSION` is the mechanism by which changing a tax rate or a fee
invalidates every outstanding quote. Without it a customer could hold a quote
across a pricing change and pay yesterday's figure.

### Statuses, and which are stored

`ACTIVE` and `CONSUMED` are stored. `STALE` and `EXPIRED` are **derived** on
every read, for the reason Module 13 established for pickup selections: a column
saying `ACTIVE` after the cart changed is not wrong because a job failed to run
— a column cannot know.

---

## The API

```
POST /api/v1/customer/trips/{trip}/checkout/prepare
POST /api/v1/customer/trips/{trip}/checkout/{checkout}/validate
```

Both POST. `prepare` is a calculation whose side effect is writing the quote
down; `validate` is a point-in-time go/no-go, and a cached yes is somebody at a
payment screen for a kitchen that has shut — the same reasoning as Module 13's
pre-checkout endpoint, recorded in [05-api-standards.md](05-api-standards.md).

### No client total

`prepare` and `validate` read **no** money from the request. A body carrying
`payable_total_minor`, `items_subtotal_minor`, `discount_minor` or `tax_minor`
parses to the same thing as a body without them, because nothing looks for those
keys. The tamper test asserts the response is unchanged by their presence.

### Ownership

The journey in the path must belong to the caller, as everywhere else in this
API, and the quote must belong to the same customer **and** the same cart. Another
customer's checkout id is a 404.

---

## Editing after a quote exists

**Edit Cart** and **Change Pickup Time** return to Modules 12 and 13. Both
invalidate the quote through the fingerprint rather than through a hook somebody
has to remember to call — the cart's version moves, or the pickup selection does,
and the next read of the quote is `STALE`.

Nothing is reserved. Preparing a checkout holds no inventory: a long-lived
reservation is a design with real consequences for other customers, and it is
not being introduced as a side effect of viewing a screen.

---

## Payment readiness

`validate` re-checks everything `prepare` checked, plus the quote itself: it
exists, it is this customer's, it is unexpired, unconsumed, and its fingerprint
still matches. `ready_for_payment` is computed by the backend in one place and
is not a field a request can carry.

At the end of Module 14 a customer can reach a state where `ready_for_payment`
is true — and nothing has been charged, no order exists, and no Razorpay object
has been created.

---

## One response, one clock

Module 13 arrived at this rule the hard way: a device run showed the same pickup
window rendered twice, five and a half hours apart, because the chosen window
came back in UTC while the options beside it came back in the restaurant's zone.
The fix at the time corrected the field somebody had looked at. It did not
correct the rule.

Module 14 found the rest of it. A checkout body was going out with five instants
in UTC — `pickup.server_now`, the travel estimate's two, `earliest_ready_at` and
the quote's `expires_at` — beside two at `+05:30`. Rendered, that is a quote
"held until 6:40 am" underneath a 1:10 pm collection: an expiry seven hours in
the customer's past, on the screen where they agree to pay.

**The rule, stated as an invariant rather than as a field:** if any instant in a
response body is expressed on a particular clock, all of them are. It is the
restaurant's clock, because a pickup happens at a counter and the counter has a
wall.

Where it lives:

| Layer | What enforces it |
| --- | --- |
| `PickupPlan::toApiArray` | every instant goes through `PickupPlan::local` |
| `ArrivalEstimate::toApiArray` | takes the zone as a parameter; has no clock of its own |
| `Cart::toCustomerArray` | `expires_at` through `Cart::localIso` |
| `CheckoutController::payload` | every instant through `$plan->local()` |
| `PickupTimeApiTest`, `CheckoutApiTest` | walk the whole body, fail on two offsets |

The two tests are the point. They do not name the fields; they walk the response
and count distinct offsets, so a field added later is covered by a test written
before it existed. Both also assert the single offset is `+05:30` rather than
merely self-consistent — a body that had become uniform by sending everything in
UTC would pass a sameness check and still be wrong.

### On the client

Dart's `DateTime.parse` **discards the offset**: given
`2026-09-07T13:40:00+05:30` it returns the right instant flagged UTC, and the
only two things a client can then do are show UTC or convert to the phone's
zone. So the models keep two fields for every instant a customer reads — the
absolute one for comparing, and the wall-clock reading exactly as the server
wrote it, parsed out of the string by `wallClockOf`.

`Checkout.localExpiresAt` is the second caller of that function. A screen
reaching for `.toLocal()` instead is the bug this exists to prevent, and on a
device set to London it would put a third clock in a body the server took care
to write on one.

---

## The Flutter layer

**The screen computes no figure and decides no readiness.** The subtotal, every
charge, the payable total and `ready_for_payment` all arrive from the server and
are rendered as sent. That is not a style preference: a client that could produce
its own total would be a second answer to a question that must have exactly one,
and this is the screen where a customer agrees to a number.

`CheckoutRepository` has **no parameter that takes an amount**, and
`ApiCheckoutRepository` sends **no request body at all**. A modified client
cannot name a price because there is nowhere to put one.

| Piece | Responsibility |
| --- | --- |
| `domain/models/checkout.dart` | parsing; an unknown status reads as `STALE`, never usable |
| `domain/repositories/checkout_repository.dart` | `prepare` and `validate`, no amounts |
| `shared/state/checkout_controller.dart` | holds what came back; re-prepares a quote the server has forgotten |
| `features/checkout/checkout_screen.dart` | renders it |
| `features/checkout/widgets/commercial_summary_card.dart` | draws only the components sent |

### What the summary card will not do

It has no code that renders a zero row for a missing component. An absent charge
means nobody configured that rule, and "Tax ₹0.00" would state a decision the
platform has not made. When nothing is configured the card says so in words —
about configuration, and never about tax law.

### Getting there

Module 13's pickup screen shows **Continue to checkout** once its pre-checkout
verdict says the order is ready, and not before. The checkout screen asks the
server again on arrival regardless: the previous screen's answer is a moment old
by the time this one loads, and a stale yes is the kind that costs money.

`Edit cart` and `Change pickup time` are stacked rather than side by side. In a
row on a 393dp phone the second painted as "Change pick…" — a control whose name
a customer cannot read — and half a screen width is much less than enough at
200% text.
