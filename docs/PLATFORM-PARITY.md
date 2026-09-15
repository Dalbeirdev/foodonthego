# PLATFORM PARITY

Restart Module 01. Commit `b49dcb4`.

## SUPERSEDED IN PART BY RESTART MODULE 02

The client chose React for Customer Web. Customer Web is now
`web/apps/customer`; Flutter builds Android and iOS only. Parity is therefore
**no longer structural** — it is a property that has to be maintained, and this
document is where the two surfaces are compared. The trade-off below was written
before that decision and is kept because it states the cost that was accepted.

Restart Module 02 verified the first row of that parity: the five destinations,
the Home screen and the authentication routing exist on both, with the same
labels and the same behaviour.

## The architectural fact that decided this document, before Restart Module 02

Customer Web, Customer Android and Customer iOS were **the same Dart codebase**,
`mobile/`, compiled three ways:

- `flutter build web`      → `/var/www/customer`, served at the site root
- `flutter build apk/aab`  → the Android review build
- `flutter build ios`      → the iOS build (unsigned in CI)

A screen, a route, a controller or a validation rule written once appears on all
three. Parity is therefore **structural**, not maintained by discipline. The
parity table below has no gaps in the customer columns for that reason, and the
claim is cheap to re-verify: `mobile/lib/core/routing/routes.dart` is one file.

## Parity matrix

Where Web, Android and iOS share a codebase, the meaningful distinction is not
"is the feature there" but "has it been *seen* on that platform".

| Feature | Web | Android | iOS | Shared API | Visually verified | Gap |
| --- | --- | --- | --- | --- | --- | --- |
| Login (phone + OTP) | YES | YES | YES | YES | Web ✔ (live site + this audit) | Android/iOS by CI only |
| Home | YES | YES | YES | YES | Web ✔ | — |
| Profile | YES | YES | YES | YES | Web — route opens | — |
| Saved addresses | YES | YES | YES | YES | not driven | — |
| Trip planner | YES | YES | YES | YES | not driven | — |
| Route + map | YES | YES | YES | YES | not driven | **map tiles blank — MF-08** |
| Restaurant list | YES | YES | YES | YES | not driven | — |
| Search | YES | YES | YES | YES | not driven | — |
| Filters | YES | YES | YES | YES | not driven | — |
| Restaurant details | YES | YES | YES | YES | not driven | — |
| Menu | YES | YES | YES | YES | not driven | — |
| Item details | YES | YES | YES | YES | not driven | — |
| Cart | YES | YES | YES | YES | not driven | — |
| Pickup time | YES | YES | YES | YES | not driven | — |
| Checkout | YES | YES | YES | YES | not driven | — |
| Payment | YES | YES | YES | YES | not driven | **no credentials — MF-10** |
| Order confirmation | YES | YES | YES | YES | not driven | — |
| Tracking | YES | YES | YES | YES | not driven | **nothing advances state — MF-11** |
| ETA | NO | NO | NO | NO | — | **MISSING everywhere — MF-03** |

**There is no PLATFORM GAP in the customer journey.** Every gap found is a gap on
*all three* platforms at once, which is what a shared codebase produces. The gaps
are credentials and unbuilt modules, not divergence.

## Where parity genuinely differs: presentation

| Concern | Web today | Android / iOS today | Verdict |
| --- | --- | --- | --- |
| Navigation | Bottom navigation, as on mobile | Bottom navigation | Acceptable on a phone-width browser; **wrong on a desktop browser** |
| Layout at ≥1024 | The phone layout stretched edge to edge | n/a | **MF-02 — open** |
| Typography | Fetched from `fonts.gstatic.com` at runtime | Platform font available | **MF-01 — open, web only** |
| Back behaviour | Browser back drives `go_router` | System back / edge gesture | Structurally sound, not hand-tested |

Those three rows are the real parity work, and they are presentation, which the
brief expressly allows to be adapted per platform.

## The decision the client must make

The brief asks for a Customer Web application in React + TypeScript under
`/web/customer`, *if one does not already exist*. One does exist — as Flutter Web.
The two options are not equivalent and neither is free:

**Keep Flutter Web (recommended).** Parity is structural and permanent. One
codebase, one set of business rules, one place to fix a bug. Cost: a heavier first
load, no server-side rendering or SEO, and text rendered to canvas — which is what
makes MF-01 as severe as it is. MF-01 and MF-02 are both fixable inside this
codebase and are ordinary work.

**Build a React customer web app.** Better web-native feel, real DOM text,
SEO, smaller first paint. Cost: the entire customer journey — roughly fifteen
screens, their state, their validation and their error handling — built and then
maintained **twice**, forever. Every future restart module doubles. And the parity
this document reports as structural becomes a manual promise, enforced by review
rather than by the compiler — which is precisely the failure mode the brief's
"PLATFORM PARITY PRINCIPLE" exists to prevent.

This is not a recommendation dressed up as a fact: both are legitimate. But it is
a decision to take deliberately, with the cost visible, rather than by treating
"Customer Web is missing" as true when it is not.

---

# Restart Module 05 — trip planner parity

Web is the React customer app driven live in Chromium. Android and iOS are the
Flutter app: the code exists and its tests pass, but **no Android SDK, emulator
or Apple hardware is reachable from this environment**, so no screen on either
was looked at by a person. That is recorded as PENDING, never as a pass.

| Feature | Web | Android | iOS | Backend | Live | Screenshot | Gap |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Open planner | ✅ | code + tests | code + tests | ✅ | Web | ✅ | device runtime |
| Origin search | ✅ | code + tests | code + tests | ✅ | Web | ✅ | device runtime |
| Destination search | ✅ | code + tests | code + tests | ✅ | Web | ✅ | device runtime |
| Saved HOME | ✅ | code + tests | code + tests | ✅ | Web | ✅ | device runtime |
| Saved WORK | ✅ | code + tests | code + tests | ✅ | Web | ✅ | device runtime |
| Saved OTHER | ✅ tests | code + tests | code + tests | ✅ | — | — | not driven live on any platform |
| Current location | ✅ | code + tests | code + tests | ✅ | Web | ✅ | **http review site blocks it — MF-28** |
| Permission granted | ✅ | code + tests | code + tests | — | Web | ✅ | device runtime |
| Permission denied | ✅ | code + tests | code + tests | — | Web | ✅ | device runtime |
| Place suggestions | ✅ | code + tests | code + tests | ✅ | Web | ✅ | Google never called — MF-29 |
| Place details | ✅ | code + tests | code + tests | ✅ | Web | ✅ | as above |
| Clear location | ✅ | code + tests | code + tests | — | Web | ✅ | device runtime |
| Swap | ✅ | code + tests | code + tests | — | Web | ✅ | device runtime |
| Same-location validation | ✅ | code + tests | code + tests | ✅ | Web + API | ✅ | device runtime |
| Create journey | ✅ | code + tests | code + tests | ✅ | Web + API | ✅ | device runtime |
| Idempotency | ✅ | code + tests | code + tests | ✅ | API | — | — |
| Route handoff | ✅ | code + tests | code + tests | ✅ | Web | ✅ | Module 06 content |
| Active trip on Home | ✅ | code + tests | code + tests | ✅ | Web | ✅ | device runtime |
| Saved places — create | ✅ | code + tests | code + tests | ✅ | Web | ✅ | web edit/default missing — MF-26 |
| Map preview | — | — | — | — | — | — | **out of scope**: Module 06 owns the map |

## The one place the platforms genuinely differ

Browser geolocation requires a secure context. On the review deployment
(`http://techpio.tech:8080`) `navigator.geolocation` is unavailable, so
"Use my current location" reports the insecure-context message to every visitor
there. Android and iOS have no such restriction. This is not a parity defect in
the code — it is **MF-28**, and it closes when **MF-16** (TLS) does.

---

# Restart Module 06 — routing and maps parity

Web is the React customer app driven live against the real API on a production
build. Android and iOS are the Flutter app: the code exists and its tests pass,
and **no Android SDK, emulator or Apple hardware is reachable here**, so no
screen on either was looked at by a person.

| Feature | Web | Android | iOS | Backend | Live | Screenshot | Gap |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Route screen | ✅ | code + tests | code + tests | ✅ | Web | ✅ | device runtime |
| Map (tiles) | ❌ | ❌ | ❌ | — | — | — | **no Maps key — MF-08** |
| Map (route shape, no tiles) | ✅ | ✅ | ✅ | — | Web | ✅ | — |
| Origin marker | ✅ | code + tests | code + tests | — | Web | ✅ | device runtime |
| Destination marker | ✅ | code + tests | code + tests | — | Web | ✅ | device runtime |
| Polyline | ✅ | code + tests | code + tests | ✅ | Web | ✅ | device runtime |
| Distance | ✅ | code + tests | code + tests | ✅ | Web | ✅ | synthetic provider — MF-12 |
| Duration | ✅ | code + tests | code + tests | ✅ | Web | ✅ | synthetic provider — MF-12 |
| Traffic duration | ✅ (absence handled) | ✅ | ✅ | ✅ | Web | ✅ | **never returned — MF-12** |
| Single route | ✅ | code + tests | code + tests | ✅ | Web | ✅ | — |
| Route alternatives | ✅ tests | code + tests | code + tests | ✅ | — | — | **NOT RETURNED BY PROVIDER — MF-35** |
| Route selection | ✅ tests | code + tests | code + tests | ✅ | API | — | needs alternatives to drive live |
| Route persistence | ✅ | code + tests | code + tests | ✅ | Web | ✅ | device runtime |
| Route refresh | ✅ | code + tests | code + tests | ✅ | Web + API | ✅ | — |
| Stale route | ✅ | code + tests | code + tests | ✅ | API | — | — |
| Provider error | ✅ | code + tests | code + tests | ✅ | Web | ✅ | — |
| No route | ✅ | code + tests | code + tests | ✅ | Web | ✅ | — |
| Offline cached route | ❌ | ❌ | ❌ | — | — | — | **not implemented — MF-30** |
| Find Food CTA | ✅ | code + tests | code + tests | — | Web | ✅ | listing is Module 07 |

## Where the platforms genuinely differ

Nothing in this module's design. Both the web and the Flutter app gate the map
on a key and render an honest map-unavailable state without one — and until
Restart Module 06 the mobile halves would have rendered a **broken** map rather
than that state the moment a key arrived, because the key never reached either
native SDK. That is now wired on all three.
