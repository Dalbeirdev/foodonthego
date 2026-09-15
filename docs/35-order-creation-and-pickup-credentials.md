# Order creation, confirmation and pickup credentials (Module 16)

Module 15 could take money. This module decides what a captured payment is
allowed to turn into, and hands the customer the two things they need at the
counter: a number to say, and a credential to prove.

> **One captured payment produces at most one order. Not usually one. At most one.**

Everything below is downstream of that sentence.

## The deviation, stated first

Modules 12–15 create an `orders` row at checkout, *before* payment, and point
the payment at it. The Module 16 specification requires the opposite: an order
must not exist until a payment is captured and verified by this server.

Both cannot be true of the same table, and the choice made here was to keep one
table and change what a row means:

| State | What the row is |
| --- | --- |
| `AWAITING_PAYMENT` | **Not an order.** A payment target. No order number, no `placed_at`, no pickup credentials. Never appears in the customer's Orders tab. |
| `PLACED` | An order. Everything above is populated, and `placed_from_payment_id` names the captured payment that caused it. |

The migration that does this is named for the rule rather than for the columns
(`place_orders_only_on_captured_payment`) so that the deviation is visible in
the migration list and not only in a document.

The alternative — a separate `payment_intents` table and a genuinely
order-free checkout — is the cleaner model and was rejected deliberately: it
would have rewritten four modules' worth of working, tested payment code to
reach the same guarantee that a nullable `order_number` and one unique index
already provide.

**What is enforced is the rule, not the row count.** `orders.order_number IS
NULL` is the machine-checkable form of "this is not an order yet", and
`orders:check-integrity` reports any row that violates it.

## Exactly once, and where the guarantee actually lives

Exactly-once delivery does not exist. What exists is at-least-once delivery
plus idempotent creation, and this module is the second half.

There are three layers, and only one of them is a guarantee:

| Layer | What it does | Is it the guarantee? |
| --- | --- | --- |
| `SELECT ... FOR UPDATE` on the order and payment rows | Serialises two concurrent attempts | No — it orders them, it does not decide the second one |
| Re-reading the status *inside* the lock | The second attempt sees `PLACED` and returns the existing order | No — this is the fast path, and it depends on the lock being held |
| **Unique index on `orders.placed_from_payment_id`** | The database refuses a second order for one payment | **Yes** |

The first two are how the common case stays cheap and returns the right
answer. The third is what remains true when the first two are wrong — a
connection dropped mid-transaction, a deploy running two versions at once, a
retry arriving on a different database node.

So `place()` catches the `QueryException`, looks up the order that must now
exist for that payment, logs `orders.duplicate_creation_prevented`, and
returns it. **A duplicate attempt is a successful call**, because the caller —
a webhook Razorpay will retry, a customer's app resuming after a crash — is not
doing anything wrong.

## What is checked before an order exists

`place()` refuses unless all of these hold, and the order of the checks is not
arbitrary:

1. The row is still `AWAITING_PAYMENT` (or already `PLACED`, in which case
   return it).
2. The payment is `CAPTURED` **as this server recorded it after verifying with
   the provider** — not as any client reported it.
3. The payment's amount and currency agree with the order's
   `payable_total_minor`.

There is no path from a client assertion to an order. `payment_success = true`
in a request body is not an input to this decision; it is not read.

## Two identifiers, and why they are not one

| | Order number | Pickup credential |
| --- | --- | --- |
| Shape | `FOTG-YYMMDD-XXXXXXXXXX` | 8 characters, plus a 256-bit token |
| Said out loud? | Yes — that is its whole job | **No** |
| Stored? | Yes, in `orders.order_number` | **Only as a SHA-256 digest** |
| Authorises pickup? | **No** | Yes |
| In the Orders list response? | Yes | No — separate endpoint |

The order number is a reference, and it is safe for it to be quoted in a
support ticket, read across a counter, or printed on a screen a stranger can
see. It is drawn from `random_int` over a 32-character alphabet with I, L, O
and U removed — not from `Math.random`, not from a timestamp, not from the
database id, and not from any sequence. A sequential public number tells its
holder how many orders the platform has ever taken and lets them guess their
neighbours'.

The credential is the thing that gets food handed over, and it is treated
accordingly.

### The credential is derived, never stored

```
code   = base32   ( HMAC-SHA256( pepper, "pickup-code:v{n}:{order_uuid}:{restaurant_id}"  ) )[0..8]
token  = base64url( HMAC-SHA256( pepper, "pickup-token:v{n}:{order_uuid}:{restaurant_id}" ) )
digest =            HMAC-SHA256( pepper, "{purpose}:{value}" )
```

The database holds the two digests and nothing else. There is no column a
plaintext pickup code could be read out of, so a database dump, a log line, a
backup, or a support tool cannot leak one.

The digest is **keyed with the same pepper**, not a bare `sha256`. That matters
for the code specifically: 2^40 is small enough to enumerate offline, so a
plain hash of an 8-character code in a stolen dump is a lookup table away from
plaintext. A keyed digest is not, unless the pepper went with it.

The code's characters are `ord(byte) % 32`, which is unbiased because 256 is a
multiple of 32 — a modulo over a 26-letter alphabet would not have been, and
the alphabet was chosen with that in mind as well as for legibility.

**The order uuid and the restaurant id are inside the HMAC**, which is the
point of the construction. Cross-order replay and cross-tenant replay are not
prevented by a check somewhere that could be forgotten at a new call site —
they are prevented by arithmetic. A credential minted for order A at
restaurant X simply does not equal the one for order B at restaurant Y, and
`OrderPlacementTest` asserts that in both directions, with a positive
assertion alongside so that an implementation matching *nothing* could not pass.

`v{n}` is `orders.pickup_credential_version`. It exists so a credential can be
invalidated without touching the order. The tests record what rotation costs:
bumping the version changes both derived values **and the stored digests must
be re-minted**, because the digest of the old code otherwise keeps matching.

Comparison is `hash_equals`, both for the code and the token.

The pepper is `PICKUP_CREDENTIAL_PEPPER`. It is the single secret the whole
scheme rests on, and that trade is stated in the service itself rather than
hidden: compromise it and every credential for every order becomes derivable.
`ProductionConfigGuard` refuses to boot staging or production without it, and
`derive()` throws `PickupCredentialUnavailable` rather than falling back to an
empty key — a scheme that quietly degrades to `HMAC(pepper: "")` is worse than
one that stops.

### The 8-character code is not sufficient on its own, and is not asked to be

Eight characters of that alphabet is 2^40. That is a large number and a poor
security boundary — it is short because a human types it, and short things get
guessed. It is one factor, not the boundary. The 256-bit token is the other,
and the QR path carries the token rather than the code.

**There is no redemption endpoint yet, so there is no rate limit on guessing
one yet either.** Whichever module builds pickup verification inherits that
obligation: a typed code must be attempt-limited per order, or 2^40 stops being
a large number. This is recorded as an open item rather than left implied.

**No claim is made here that QR pickup verification is complete.** This module
mints and serves the credential; the scanner, the counter flow, and the
redemption endpoint are not in it.

## What the customer's app is told, and what it is not

Once a payment is captured, there are only three honest answers, and none of
them is an error:

| `state` | HTTP | Means |
| --- | --- | --- |
| `PLACED` | 200 | The order exists. Here it is. |
| `ORDER_CREATION_PENDING` | **202** | Money is taken. The order is being written. Hold. |
| `ORDER_RECOVERY_REQUIRED` | **202** | Money is taken. Creation failed. A human process owns this now. |

The two 202s are deliberately **not** members of `ApiErrorCode`. An existing
test — `ErrorContractTest` — rejects any error code that carries a 2xx status,
and it was right to: these are not failures. They live in their own enum,
`OrderCreationState`, precisely so that nothing downstream can render them
through an error path.

This is the rule the confirmation screen exists to keep:

> **After a payment is captured, the customer is never shown "Payment failed",
> and never shown a way back to paying again.**

There is no *Pay Again* button, no *Back to Payment*, no retry affordance on
that screen at any phase. A captured payment that has not yet become an order
is a delay; presenting it as a failure invites a second payment for the same
food. The Flutter confirmation controller polls `status` (10 attempts, 3
seconds apart) and, when it runs out, shows a support path — not a payment
path.

The Flutter model reads unknown states as `creating` and a missing
`is_paid_for` as *paid for*. Both defaults point the same way: when the client
is unsure, it must not imply the money is gone.

## When creation fails after capture

This is the state the module is most careful about, because it is the one
where a customer has paid and has nothing.

`RecoverCapturedPaymentsCommand` (`orders:recover-captured`, every five
minutes) finds payments captured more than a grace period ago — 120 seconds by
default, so that an in-flight creation is not raced — with no order against
them, and runs them through the same `CreateOrderFromCapturedPayment`. Not a
second implementation: the same one, so recovery cannot drift laxer than the
live path.

`CheckOrderIntegrityCommand` (`orders:check-integrity`, hourly) is a
**reporting** command and writes nothing. It looks for both directions of
breakage: captured payments with no order, and placed orders with no captured
payment. A repair job that silently fixes things is a repair job whose bugs
are invisible.

## The outbox

`OutboxEvent` rows are written **inside the creation transaction**, so an event
cannot exist for an order that was rolled back, and an order cannot commit
without its event. `PublishOutboxEventsCommand` (`outbox:publish`, every
minute) drains them.

Payloads carry **identifiers only** — `order_uuid`, `restaurant_id`,
`payment_uuid`. No totals, no customer details, no credentials. A consumer that
needs more asks for it over an authenticated API, where the ownership checks
live.

Unique on `(event_name, dedupe_key)`, for the same reason the payment webhook
table is: a check-then-write has a gap and two attempts can be in flight.

## Snapshots

`orders` carries `customer_name_snapshot`, `customer_phone_snapshot`,
`restaurant_name_snapshot` and `restaurant_address_snapshot`, written once at
placement.

An order is a record of what was true when it was placed. If a restaurant is
renamed or a customer edits their phone number, last week's order must still
read the way it read then — for the customer, for the restaurant, and for any
dispute about either. `OrderSnapshotImmutabilityTest` changes the live records
afterwards and asserts the order does not move.

The customer phone comes from `users.phone_e164`. This is written down because
the obvious column, `users.phone`, is a legacy field that is not populated, and
reading it produced snapshots that were silently `NULL` — caught only because
the test asserted the fixture was non-empty *before* asserting the snapshot
matched it.

## Logging

Never logged, anywhere: the plaintext pickup code, the plaintext QR token,
special instructions, payment signatures, provider secrets.

Logged: order uuid, payment uuid, restaurant id, state transitions, and
`orders.duplicate_creation_prevented` when the unique index does its job.
`PickupCredential::toString()` returns `PickupCredential(v2)` — the version and
nothing else — so that an accidental interpolation into a log line cannot spill
the value.

## What this module does not do

- It does not verify a pickup. No redemption endpoint exists.
- It does not scan a QR code. The payload is served; nothing consumes it.
- It has never run against live Razorpay. The captured-payment path is proven
  against the deterministic fake gateway; a genuine provider capture is not
  something this environment can produce.
- It does not move an order past `PLACED`. Every onward transition in
  `OrderStateMachine` is an empty array, and that is the current truth rather
  than an oversight.
