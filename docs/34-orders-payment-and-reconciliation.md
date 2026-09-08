# Orders, payment, webhooks and reconciliation (Module 15)

A checkout quote becomes an order; an order gets paid for. This document is
about the second half, and about the one rule the whole module exists to
enforce.

> **A client's word about money is evidence to check, never a fact to accept.**

## No credentials, stated first

**No Razorpay credentials exist for this project and none were invented.**

The container binds `UnconfiguredPaymentGateway`, which refuses every call and
logs why. In staging or production `ProductionConfigGuard` refuses to boot at
all rather than run a deployment that cannot take money. The Flutter app binds
`UnconfiguredPaymentHandoff`, which reports that no checkout can be opened, and
the payment screen says so in those words.

`RazorpayGateway` is written and reviewable. **It has never spoken to Razorpay.**
Supplying credentials is a configuration change, not a development task — but no
claim is made here that the integration has been exercised end to end, because
it has not.

## The three checks

A signature proves one thing: the message was not tampered with. It does not
prove the payment succeeded, does not prove the amount, and does not prove the
payment belongs to this order. Each of those is established separately.

| # | Check | The hole it closes |
| --- | --- | --- |
| 1 | **Signature** — HMAC-SHA256 over `order_id\|payment_id` with the API secret, compared with `hash_equals` | A forged or altered result |
| 2 | **Binding** — the provider's own `order_id` for that payment must equal the provider order we created for *this* order | A genuine, correctly signed payment belonging to somebody else |
| 3 | **Amount and currency** — against `orders.payable_total_minor`, not against the payment row | A real, signed, correctly bound ₹1 payment settling a ₹838 order |

All three run on every path, because they live in one method.

## Three paths to PAID, one implementation

| Path | When it is the only one that works |
| --- | --- |
| **Client callback** | The ordinary case: the app came back. |
| **Webhook** | The app was killed the instant after paying, or the network dropped the callback. Without this, those orders stay unpaid forever. |
| **Reconciliation** | Both of the above were lost. It starts from the provider order this server created and asks what happened against it. |

They share `PaymentService::confirmAgainstProvider()`. Three routes with three
sets of conditions is how one of them ends up laxer than the others — and
reconciliation, the path with nobody waiting on it, is exactly where a shortcut
would never be noticed.

## Why signature verification is not on the gateway interface

`PaymentGateway` has two methods and neither of them verifies a signature.

That is deliberate. Signature checking is arithmetic over a shared secret, not a
network call. Behind the interface, the test double would be the thing deciding
whether signatures are valid — and every payment-security test in the project
would be asserting against a `return true`.

It lives in `RazorpaySignature`, is the same code in tests as in production, and
the tests compute genuine HMACs against it.

## The webhook, and the attack that shaped the schema

The webhook endpoint is unauthenticated, because Razorpay has no account here.
An HMAC over the **raw** body stands in for authentication — raw, because
re-encoding parsed JSON changes bytes and the hash would never match.

`payment_events` has a unique index on `(provider, provider_event_id)`, and that
single constraint is the entire idempotency mechanism. A unique index rather
than a "have I seen this?" query, because two deliveries can be in flight at
once and a check-then-write has a gap.

**Only verified deliveries are stored there**, and that is a security property
rather than tidiness:

> The endpoint is public. If a rejected delivery were recorded under the event
> id it claimed, an attacker could post a forged body carrying the event id of a
> payment about to happen. It would be rejected — but the row would exist, and
> the genuine delivery would then collide with the unique index and be discarded
> as a duplicate. An order paid for, left unpaid, by somebody who never had the
> secret.

Rejected deliveries are logged instead, where they are visible without being
load-bearing. `test_a_forged_delivery_cannot_poison_the_idempotency_key` asserts
both halves.

The webhook secret is separate from the API secret because Razorpay signs the
two messages with two different keys. Reusing one for both verifies nothing
while appearing to work, and there is a test for that configuration mistake.

## What is stored, and what is not

**No card data of any kind.** Not a PAN, not a last four, not a network, not a
cardholder name. There is deliberately no column such a thing could be written
into by a later change that was not thinking about it.

**No webhook payloads.** Only a SHA-256 digest of the raw body plus the few
identifiers the handler needs. A provider payload can carry a contact number, an
email address, a billing name and card metadata, and none of it is ours to keep.

**No provider decline text reaches the customer.** It is written for a merchant
dashboard, and relaying it verbatim tells somebody things about a card that are
not ours to say.

## Order status is payment state only

`AWAITING_PAYMENT`, `PAID`, `PAYMENT_FAILED`, `CANCELLED`.

There is no `PREPARING`, `READY` or `COLLECTED`. **No fulfilment workflow has
been specified**, and inventing plausible states would create a vocabulary that
screens, reports and restaurant tooling start depending on before anybody has
decided it is right. "Has the customer paid" and "has the kitchen finished" are
independent questions; one status string cannot answer both without lying about
one of them.

The Flutter app has a separate `PlacedOrderStatus` for this reason. Module 02
declared an `OrderStatus` with `cooking`, `ready` and `pickedUp` speculatively;
the server does not send those, and reusing that enum would mean screens
switching on states the API cannot produce. One of the two goes when fulfilment
is specified.

## Orders are frozen; lines are snapshots

Nothing recalculates an order's total. Not on read, not when the menu changes,
not when commercial rules change. The amounts are copied from the quote — not
recomputed, even though the arithmetic would be identical, because the customer
agreed to a number they were shown and the quote is the only record of it.

Order lines carry `item_name_snapshot`, `unit_price_minor` and the rest, and
`menu_item_id` is nullable and **nulled** on delete rather than cascaded. In a
cart, deleting a menu item should take its lines with it — an unbuyable dish
should not sit in a basket. Here it would delete evidence of a sale.

## Idempotency, in three places

| Where | Mechanism |
| --- | --- |
| Placing an order | `orders.checkout_quote_id` is UNIQUE. A double tap answers 200 with the existing order, not 201 with a second. The service checks first; the index is what holds when two requests race. |
| Opening a payment | An existing `CREATED` attempt at the same amount is reused. Several live provider orders against one of ours is how a customer ends up able to pay twice. |
| Webhook delivery | The unique event id, above. |
| Settling | The order row is locked and its status re-read inside the transaction, so a callback and a webhook arriving together settle it once. |

## Money

Integer minor units everywhere. No float has authority over money in this
schema, in the services, or in the app. `amount_minor` is stored on both the
order and the attempt and compared — the duplication is the point: the value the
provider was asked for and the value the order says is owed are different facts,
and a mismatch between them is the thing worth detecting.

## What is not built

- **No refunds.** A refunded payment maps to `CAPTURED` rather than being
  flattened into "failed", so an order that was paid and then refunded does not
  look like one that never paid. Refund handling gets its own record when it is
  specified.
- **No fulfilment workflow**, as above.
- **No settlement or payout to restaurants.** Reconciliation compares this
  server against the provider; it says nothing about what a restaurant is owed.
- **No operator login**, unchanged since Module 14T. The tenant-scoped order
  endpoints exist and are tested; nothing mints a token for them yet.
