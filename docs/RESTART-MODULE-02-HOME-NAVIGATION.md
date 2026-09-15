# RESTART MODULE 02 — CUSTOMER HOME & NAVIGATION

Commit at completion: see git. Captured 2026-09-14.

## What changed, and the decision behind it

Restart Module 01 reported that a Customer Web application already existed — the
Flutter app compiled for the browser — and put the choice to the client: keep it,
or build the React application the brief asks for and accept maintaining the
customer journey twice.

**The client reaffirmed React + TypeScript in the Restart Module 02 brief.** That
is treated as the decision and is not re-argued here. Its consequences:

- `web/apps/customer` is a new React application, served at the origin root.
- `deploy/web.Dockerfile` has **no Flutter stage at all**. Flutter builds Android
  and iOS; the browser gets a build made for a browser.
- Two open defects from Restart Module 01 are resolved by that change rather than
  by patching: **MF-01** (all text invisible when `fonts.gstatic.com` is blocked —
  the React app renders real DOM text and made **zero external requests** in
  every capture) and **MF-02** (the phone layout stretched to 1920px).
- The bundle went from **3.9 MB** of `main.dart.js` to **249 KB / 79 KB gzipped**.

## The customer web application

| | |
| --- | --- |
| Path | `web/apps/customer` |
| Stack | React 19, TypeScript 5.7, Vite 6, `@fotg/ui` design system |
| Base | `/` — the origin root |
| Router | `BrowserRouter`, basename from `import.meta.env.BASE_URL` |
| Bundle | `index-DOKa6EBA.js` 249 KB, `index-UTrU5lQU.css` 28 KB |

### Routes

| Route | Screen | Guarded | Status |
| --- | --- | --- | --- |
| `/login` | Sign-in required notice | no | **VERIFIED COMPLETE** (Restart Module 03 owns the form) |
| `/` | Home | yes | **VERIFIED COMPLETE** |
| `/trips` | Trips section | yes | **VERIFIED COMPLETE** (shell only — Restart Module 05) |
| `/trips/plan` | Plan a journey | yes | shell only — Restart Module 05 |
| `/trips/:tripId` | Journey | yes | shell only — Restart Module 06 |
| `/orders` | Orders section | yes | shell only — Restart Module 16/17 |
| `/orders/:orderId` | Order | yes | shell only — Restart Module 17 |
| `/notifications` | Notifications | yes | **VERIFIED COMPLETE** (honest empty state; no backend exists) |
| `/profile` | Profile | yes | shell only — Restart Module 04 |
| anything else | redirect to `/` | yes | no dead ends |

Every route answers. None is a 404 and none is blank. What later modules add is
content, not routes — so navigation is never dead, URLs are bookmarkable, and
back behaves throughout.

### Navigation model

One array, `shell/navigation.ts`, drives both navigations, so the desktop rail
and the phone bottom bar cannot disagree about order or wording. Labels match the
Flutter app exactly: Home, Trips, Orders, Notifications, Profile.

CSS chooses which is shown — both are in the DOM and a media query at 900px
decides. No resize listener, no measuring, no layout flash on first paint.

Active state carries **three** signals, never colour alone: `aria-current` from
`NavLink` for assistive technology, the icon, and the label weight/colour.

## Authentication routing

Three states, not two: `restoring`, `authenticated`, `anonymous`. The third state
is the whole point — a guard that treats "we have not looked yet" as "not signed
in" sends a returning customer to the sign-in screen for a frame and then bounces
them back. That is the auth flash, and `RequireSession` renders `AppLoading`
during `restoring` instead of redirecting.

Verified live: an anonymous visitor asking for `/` **and** for `/orders` landed on
`/login`, and **made zero API calls on the way** — no private request is issued
before the session resolves.

The guard is on the route, not on the navigation. Hiding a link is not protection;
a URL can be typed.

## The Home endpoint

`GET /api/v1/customer/home` — new, composed rather than decided.

```json
{ "customer": …, "active_trip": … , "active_order": …,
  "notification_summary": { "supported": false, "unread": null } }
```

- The journey comes from `TripService::currentFor()`, the same call the Trips tab
  makes.
- "Active" for an order is `OrderStateMachine::activeStatuses()` — a property of
  the transition table, so an order stops being active when its last outgoing
  edge is removed and this controller is not edited.
- The customer block is `toCustomerProfile()`, identical to what the profile
  screen receives, so a field redacted there is redacted here without this
  endpoint knowing which.
- **Notifications report `supported: false`, not `0`.** There is no notifications
  table. A zero would render as "nothing waiting for you", which is a claim the
  platform cannot make. No badge is drawn from a null.

**Cost control, measured rather than asserted: opening Home made exactly ONE
network request** — `/api/v1/customer/home`. Zero Google, zero Razorpay, zero
external hosts. A test binds both paid providers to doubles that fail if touched.

## Home states, all verified live

| State | Result |
| --- | --- |
| Loading | Skeleton in the shape of the screen, not a spinner in empty space |
| Loaded, no journey, no order | "No active journey" card; no empty order card at all |
| Loaded with a journey | `Delhi → Jaipur`, "View journey" |
| Loaded with an order | Restaurant, order number, server status, "Track order" |
| Failed | "We couldn't load your home screen", the request id, Try again — **and the Plan a journey CTA still works** |
| No name on the profile | "Welcome to FoodOnTheGo", never `undefined`, `null` or `Customer #123` |

Greeting is time-based for presentation only. Nothing on this screen influences a
business rule; pickup windows and order timing are settled server-side.

**No ETA is shown anywhere on Home.** The ETA engine does not exist, and a test
asserts the order card renders no arrival language.

## Responsive

All eight required widths captured from the running application: 360, 390, 430,
768, 1024, 1280, 1440, 1920. Bottom bar below 900, rail above. No horizontal
overflow at any width. The content column is capped at 68rem and centred, which is
the direct fix for the stretched layout Restart Module 01 photographed.

## Accessibility

- Skip link is the first tab stop.
- Tab order verified live: skip → Home → Trips → Orders → Notifications → Profile
  → Plan a journey.
- Focus is visible on every interactive element (`:focus-visible`, 2px ring).
- Bottom-bar targets are 56px tall.
- `aria-current` announces the selected tab; `aria-busy`/`aria-live` on loading.
- Active state never depends on colour alone.

## Platform parity

Flutter already had a correct shell and it was **audited, not rebuilt**:
`StatefulShellRoute.indexedStack` preserves tab state, and the router's redirect
holds position during `AuthRestoring` — the same no-flash property, implemented
independently and earlier. Home has greeting, journey CTA, current-journey and
active-order widgets.

What is **not** claimed: no Android device or Apple hardware is reachable from
this environment, so neither was inspected by a person in this module. CI runs the
release APK on a Pixel 6 emulator and the integration tests on an iPhone
simulator.

**iOS RESTART MODULE 02 = PENDING — RUNTIME ENVIRONMENT UNAVAILABLE.**

## Downstream, unchanged and still tracked

Restaurant listing, restaurant details, menu, item customization, cart, pickup,
checkout, payment, confirmation and tracking are **not** repaired by this module
and are not claimed to be. The Home CTA goes to `/trips/plan`, which exists and is
honest about being empty. It deliberately does **not** say "Find food on this
route": restaurant listing is Restart Module 07, and a dead CTA is worse than
none.
