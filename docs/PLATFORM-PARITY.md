# PLATFORM PARITY

Restart Module 01. Commit `b49dcb4`.

## The architectural fact that decides this document

Customer Web, Customer Android and Customer iOS are **the same Dart codebase**,
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
