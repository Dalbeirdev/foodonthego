# FoodOnTheGo

Restaurant discovery, ordering and delivery tracking. A customer browses kitchens near them,
builds a cart, pays nothing (see [Not built](#not-built)) and follows the order from the kitchen
accepting it to a courier handing it over. The restaurant works the same order from the other
side, and the courier from a third.

Built as a TypeScript monorepo: a Fastify API over SQLite, and a React 19 single-page app.

```
apps/
  api/       Fastify + Drizzle ORM + SQLite. REST on :5310
  web/       Vite + React 19 + TypeScript SPA on :5181
packages/
  contracts/ Zod schemas, money helpers, opening-hours logic and the order state
             machine — the rules both sides have to agree on, written once
```

## Running it

Node 22.5 or newer. From the repository root:

```bash
npm install
npm run build --workspace @fotg/contracts   # the API and web app import its built output
npm run seed                                # four restaurants, 24 dishes, three demo accounts
```

Then, in two terminals:

```bash
npm run dev:api    # http://localhost:5310
npm run dev:web    # http://localhost:5181
```

Open <http://localhost:5181> and sign in as any of the seeded accounts — all with the password
`foodonthego-demo`:

| Account | Role | What it can do |
| --- | --- | --- |
| `customer@foodonthego.test` | customer | Browse, build a cart, order, track, cancel |
| `owner@foodonthego.test` | restaurant owner | Accept, cook, mark ready; take a dish off the menu |
| `courier@foodonthego.test` | courier | See the ready queue, pick up, deliver |

**Use `localhost`, not `127.0.0.1`.** The API's CORS allow-list is an exact-match list, and
`http://127.0.0.1:5181` is a different origin from `http://localhost:5181`. This is the allow-list
doing its job rather than a bug.

> The seeded restaurants keep normal hours (roughly 11:00–23:00 **in the server's own timezone** —
> see [Known limitations](#known-limitations)). If everything shows as *Closed*, that is the
> opening-hours logic working; browsing still works, and ordering unlocks during opening hours.

## Testing

```bash
npm test                                   # everything: 124 tests
npm test --workspace @fotg/api             # 85 — routes, pricing, crypto, config
npm test --workspace @fotg/web             # 22 — components, the cart page, the API client
npm test --workspace @fotg/contracts       # 17 — money, opening hours, the order state machine
```

The API tests run against a real SQLite database with the real migrations applied — there is no
in-memory fake of the data layer, because a foreign key that is not enforced or a transaction that
does not roll back is exactly what a fake hides. (One such bug did surface this way: see
[Decisions worth knowing about](#decisions-worth-knowing-about).)

## What it does

**Discovery.** Search by name, description or cuisine; filter by cuisine, maximum delivery fee and
*open now*; sort by rating, delivery fee or prep time. Opening hours handle windows that run past
midnight, which is the case a naive `opens <= now < closes` comparison gets wrong and the case a
late-night kitchen actually lives in.

**Ordering.** A cart holds food from one restaurant at a time. Adding from a second is *refused*
rather than silently emptying the first — losing a cart somebody spent five minutes on is worse
than an error the UI can turn into a choice. Prices are re-read from the menu on every cart view,
so the figure on the checkout button is the figure that will be charged; and the client sends the
total it last displayed, so a price that moved while the cart sat open becomes an error the
customer sees rather than a surprise.

**The order lifecycle**, defined once in `packages/contracts/src/orders.ts` and read by both sides:

```
pending ──▶ confirmed ──▶ preparing ──▶ ready_for_pickup ──▶ out_for_delivery ──▶ delivered
   │            │             │                │
   ├─▶ rejected │             │                │
   └─▶ cancelled ◀────────────┴────────────────┘
```

Who may make each move is part of that table, not scattered across route handlers. A customer can
cancel while the order is `pending` or `confirmed` but not once the food is being made; a
restaurant can cancel later, because a kitchen that has run out of an ingredient needs a way out; a
courier can only move an order that is already `ready_for_pickup`. Every transition is recorded as
an event with who did it and why, and the API returns each caller's *own* permitted next steps, so
the UI shows a button only when pressing it would work.

## Decisions worth knowing about

**Money is integer cents everywhere.** No floating point touches a price. Tax and the service fee
are basis points (8.25% is `825`), rounded half away from zero rather than with `Math.round`, which
rounds half *up* and quietly biases every half-cent toward the house.

**Every total is computed server-side, once.** `apps/api/src/lib/pricing.ts` is the only
implementation, used for both the cart preview and the order that gets written. The web app's
`<Totals>` component deliberately does no arithmetic — it prints what it was given, so the screen
and the receipt cannot disagree.

**Order items are snapshots, not joins.** A line stores the name and price as they were when the
order was placed. Renaming a dish or changing its price does not rewrite an old receipt, and
deleting it from the menu does not blank one.

**JWT verification pins the algorithm.** `apps/api/src/lib/jwt.ts` checks that the header is
exactly `{"alg":"HS256","typ":"JWT"}` rather than believing what the token says — `alg: none` and
the RS256/HS256 confusion attack both work by getting the verifier to trust the header. Signatures
are compared in constant time and `exp` is required, not optional. There are tests for each of
those specifically.

**Passwords are scrypt with the cost parameters stored in the hash**, so raising the cost later
does not invalidate existing passwords; an old hash is upgraded on the next successful sign-in. A
stored record claiming an absurd cost is rejected rather than honoured, so somebody who can write
to the users table cannot turn a sign-in into memory exhaustion.

**Sign-in does not leak whether an account exists.** A wrong password and an unknown address return
byte-identical responses, and the unknown-address path still hashes against a dummy value so the
timing does not answer the question either. (Registration necessarily does disclose it — the
address has to be unique — so it says so plainly instead of pretending.)

**A `better-sqlite3` transaction callback must be synchronous.** Writing it `async` throws at
runtime, and worse, every statement after the first `await` runs *outside* the transaction it looks
like it is in — a half-written order with an already-emptied cart, which is the double-charge
shape. The integration tests caught this; both transaction bodies are synchronous and say why.

**The production configuration refuses to start when it is wrong.** No `JWT_SECRET`, the committed
development key, a secret under 32 characters, an empty CORS list or a wildcard origin on a
credentialed API each stop the process with the key named and the fix stated, rather than coming up
and reporting itself healthy.

**`/health/live` and `/health/ready` answer different questions.** Live says the process is running;
ready says the database answers. Conflating them turns a busy database into a restart loop.

## Not built

Named rather than stubbed, because a settings page that does nothing is worse than an honest gap:

- **Payments.** No provider is connected. Checkout places the order and takes no money. Everything
  a payment step would need is in place — a server-computed total the client cannot alter, and an
  order written in one transaction — but the charge itself is not there.
- **Real-time updates.** The tracking page polls every 10 seconds and stops once the order reaches
  a terminal state. Websockets or SSE would be better and are not wired up.
- **Reviews.** The schema has a `reviews` table and restaurants carry a running rating sum and
  count, but nothing writes a review yet; the seeded ratings are invented.
- **Menu editing.** An owner can take a dish off the menu and put it back — the thing a kitchen
  actually needs mid-service. Creating and editing dishes works over the API
  (`POST /api/manage/restaurants/:id/items`) but has no form.
- **Courier assignment.** A courier claims an order by marking it out for delivery. There is no
  dispatch, no routing and no location tracking.
- **Images.** Menu items and restaurants have `imageUrl` columns that nothing populates; the
  storefront draws a cuisine tile instead of a broken image frame.

## Known limitations

- **Opening hours are evaluated in the server's timezone, not each restaurant's.** The schema
  stores minutes from midnight per weekday with no zone attached, so a deployment serving
  restaurants in more than one timezone will get *open now* wrong for some of them. Fixing it means
  a timezone column on `restaurants` and evaluating against that zone.
- **`openNow` filters after paging, not in SQL**, because the overnight-window rule cannot be
  expressed in SQL without writing it a second time. A page can therefore come back with fewer rows
  than `limit`, and `total` counts matches *before* the open/closed split.
- **SQLite only.** The schema is Drizzle's SQLite dialect. Postgres would need the dialect changed
  and the migrations regenerated; nothing here depends on SQLite-specific SQL, but that work has
  not been done and is not claimed.
- **`npm audit` reports 4 moderate advisories**, all esbuild's dev-server issue reached only
  through `drizzle-kit`, a build-time migration generator that never runs in production and never
  serves anything. The high-severity drizzle-orm SQL-injection advisory *is* patched — that is why
  the pin is `^0.45.2`.

## Configuration

The API reads its configuration once at startup and validates all of it (`apps/api/src/config.ts`).

| Variable | Default | Notes |
| --- | --- | --- |
| `PORT` / `HOST` | `5310` / `127.0.0.1` | |
| `DATABASE_FILE` | `./data/foodonthego.db` | `:memory:` is used by the tests |
| `JWT_SECRET` | a development key | **Required in production**, minimum 32 characters |
| `JWT_TTL_SECONDS` | `43200` (12h) | |
| `CORS_ORIGINS` | `http://localhost:5181` | Comma-separated exact origins; no wildcard in production |
| `TAX_BASIS_POINTS` | `825` (8.25%) | |
| `SERVICE_FEE_BASIS_POINTS` | `500` (5%) | |
| `SERVICE_FEE_CAP_CENTS` | `599` | The fee is capped rather than scaling forever |

The web app reads `VITE_API_BASE_URL` (see `apps/web/.env.example`).
