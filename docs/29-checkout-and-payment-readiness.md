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
