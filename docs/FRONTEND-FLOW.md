# FRONTEND FLOW — the master customer journey

Restart Module 01. Commit `b49dcb4`.

**Customer Web and Customer Android and Customer iOS are one codebase**
(`mobile/`). A route that exists, exists on all three. That is why the Web and
Android columns below agree everywhere: it is a property of the architecture, not
a coincidence, and it is the strongest parity guarantee available.

Status values: VERIFIED COMPLETE · IMPLEMENTED BUT NOT LIVE · BACKEND ONLY ·
FRONTEND ONLY · PARTIALLY IMPLEMENTED · PLATFORM GAP · BROKEN · MISSING ·
NOT YET SCHEDULED · BLOCKED · IOS TEST PENDING

```
  LOGIN            /welcome → /auth/phone → /auth/otp → /auth/register
     │             VERIFIED COMPLETE  (signed in on the live site today)
     ▼
  HOME             /
     │             VERIFIED COMPLETE
     ▼
  PLAN JOURNEY     /trips , /trips/plan
     │             VERIFIED COMPLETE
     ▼
  ROUTE            /trips/:tripId/route
     │             PARTIALLY IMPLEMENTED — screen and API live; map tiles BLOCKED (MF-08),
     │             traffic-aware figures BLOCKED (MF-12)
     ▼
  RESTAURANTS      /trips/:tripId/route/restaurants
     │             IMPLEMENTED BUT NOT LIVE-VERIFIED — list, search, filters, sort all
     │             present in source and routed; not driven end to end in this audit
     ▼
  RESTAURANT       …/restaurants/:restaurantId          IMPLEMENTED BUT NOT LIVE-VERIFIED
     ▼
  MENU             …/restaurants/:restaurantId/menu     IMPLEMENTED BUT NOT LIVE-VERIFIED
     ▼
  ITEM             …/menu/items/:itemId                 IMPLEMENTED BUT NOT LIVE-VERIFIED
     ▼
  CART             /trips/:tripId/cart                  IMPLEMENTED BUT NOT LIVE-VERIFIED
     ▼
  PICKUP TIME      …/cart/pickup                        IMPLEMENTED BUT NOT LIVE-VERIFIED
     ▼
  CHECKOUT         …/pickup/checkout                    IMPLEMENTED BUT NOT LIVE-VERIFIED
     ▼
  PAYMENT          …/checkout/payment                   BLOCKED — no Razorpay credentials (MF-10)
     ▼
  CONFIRMATION     /orders/:orderId/confirmation        IMPLEMENTED BUT NOT LIVE-VERIFIED
     ▼
  TRACKING         /orders/:orderId/track               PARTIALLY IMPLEMENTED — displays state,
     │                                                  but nothing can advance it (MF-11)
     ▼
  ETA              —                                    NOT YET SCHEDULED (Module 18, MF-03)
```

## Why so much reads "IMPLEMENTED BUT NOT LIVE-VERIFIED"

Because it is the honest label. Each of those stages has a route in
`mobile/lib/core/routing/routes.dart`, a screen, a controller, a repository and a
backend endpoint, and each is covered by widget tests and by the 29 on-device
integration tests CI runs on every pull request. What this audit did **not** do is
drive a browser from sign-in to a placed order and photograph each screen.

Under the restart rule — *a feature is complete only when it is visible and usable
in the live application* — "the tests pass and the route exists" is not COMPLETE.
Each stage is promoted to VERIFIED COMPLETE by its own restart module, with a
screenshot taken from the running application.

## Navigation entry points — can a real user reach each screen?

| Stage | Reachable by tapping, not by typing a URL? | Entry point |
| --- | --- | --- |
| Login | YES | App launch when unauthenticated |
| Home | YES | After sign-in; bottom nav "Home" |
| Trips | YES | Bottom nav "Trips" |
| Plan journey | YES | Home CTA and Trips CTA |
| Route | YES | After creating a journey |
| Restaurants | YES | "Find food on this route" CTA on Route |
| Restaurant detail | YES | Tapping a restaurant card |
| Menu | YES | "View menu" CTA |
| Item | YES | Tapping a menu item |
| Cart | YES | Cart CTA after adding an item |
| Pickup time | YES | "Choose pickup time" CTA |
| Checkout | YES | "Continue to checkout" CTA |
| Payment | YES | "Proceed to payment" CTA |
| Confirmation | YES | After payment |
| Tracking | YES | "Track order" CTA, and Orders tab |
| ETA | **NO** | Does not exist |

## Back navigation

`go_router` nested routes carry trip, restaurant and menu context in the path, so
going back up the stack cannot lose the trip or the restaurant — they are in the
URL. Browser back, Android system back and the iOS back gesture all drive the same
router. **Not exercised by hand in this audit** — asserted from the routing
structure, and listed for its own restart module to verify with a person driving it.

---

## Updated by Restart Module 02

Customer Web is now React (`web/apps/customer`); Flutter is Android and iOS.
The three columns no longer come from one codebase, so each is stated separately.

| Stage | Customer Web | Android / iOS | Backend |
| --- | --- | --- | --- |
| LOGIN | **VERIFIED COMPLETE** — live, new and existing customer, screenshots | VERIFIED COMPLETE | VERIFIED COMPLETE |
| HOME | **VERIFIED COMPLETE** — live, real data, screenshot | IMPLEMENTED, device pending | **VERIFIED COMPLETE** — `GET /customer/home` |
| PLAN JOURNEY | route exists, content R-05 | IMPLEMENTED | VERIFIED COMPLETE |
| ROUTE | route exists, content R-06 | IMPLEMENTED | map tiles BLOCKED (MF-08) |
| RESTAURANTS | **MISSING — R-07** | IMPLEMENTED | VERIFIED COMPLETE |
| RESTAURANT | **MISSING — R-09** | IMPLEMENTED | VERIFIED COMPLETE |
| MENU | **MISSING — R-10** | IMPLEMENTED | VERIFIED COMPLETE |
| ITEM | **MISSING — R-11** | IMPLEMENTED | VERIFIED COMPLETE |
| CART | **MISSING — R-12** | IMPLEMENTED | VERIFIED COMPLETE |
| PICKUP | **MISSING — R-13** | IMPLEMENTED | VERIFIED COMPLETE |
| CHECKOUT | **MISSING — R-14** | IMPLEMENTED | VERIFIED COMPLETE |
| PAYMENT | **MISSING — R-15** | IMPLEMENTED | BLOCKED — no credentials |
| CONFIRMATION | **MISSING — R-16** | IMPLEMENTED | VERIFIED COMPLETE |
| TRACKING | **MISSING — R-17** | IMPLEMENTED | PARTIAL — nothing advances state |
| ETA | MISSING | MISSING | **NOT YET SCHEDULED** |

Choosing React created a real web gap that did not exist before: eleven journey
stages are on Android and iOS and not yet on the web. That is the cost the client
accepted, it is tracked here rather than glossed, and each stage is closed by its
own restart module.
