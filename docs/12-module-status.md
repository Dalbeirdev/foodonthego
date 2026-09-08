# 12 — Module status

| # | Module | Status | Notes |
| --: | --- | --- | --- |
| 01 | Foundation, Architecture & Design System | **COMPLETE (with 3 environment blockers)** | See below |
| 02 | Customer Mobile App Shell, Navigation & Premium Home | **COMPLETE (Android/iOS device verification pending)** | 82 mobile tests; 11 states inspected live |
| 03 | Customer Authentication, Registration, OTP, Session & Security | **COMPLETE (Android/iOS device verification pending)** | 130 backend + 72 mobile tests; real Flutter→Laravel→MySQL integration run; 20 states inspected live |
| 04 | Customer Profile & Saved Addresses | **COMPLETE (Android/iOS device verification pending)** | 99 backend + 68 mobile tests; real Flutter→Laravel→MySQL integration run; 24 states inspected live |
| 05 | Trip Planner — Origin, Destination & Trip Creation | **COMPLETE (Android/iOS device verification pending; live Places verification pending)** | 408 backend + 312 mobile tests; real Flutter→Laravel→MySQL integration run (31 assertions); 28 states inspected live |
| 06 | Maps, Route Calculation, Distance & Travel Time | **NOT COMPLETE — live routing provider verification unavailable** | 527 backend + 382 mobile + 29 web tests; integration run (21 assertions); 20 states inspected live. See below |
| 07 | Restaurant Discovery Along the Selected Route | **NOT COMPLETE — live routing-provider detour figures unavailable** | 693 backend + 453 mobile + 29 web tests; integration run (22 assertions); 21 states inspected live. See below |
| 08 | Restaurant Search, Filters, Sorting & Discovery Ranking | **COMPLETE (Android/iOS device verification pending)** | See below |
| 09 | Restaurant Details, Facilities, Availability & Customer Preview | **COMPLETE (Android/iOS device verification pending)** | See below |
| 10 | Menu, Categories & Menu Item Browsing | **COMPLETE (Android/iOS device verification pending)** | See below |
| 11 | Menu Item Details, Variants, Addons, Customization & Add to Cart | **COMPLETE** | 1,729 tests; 34 live states; **Android 8/8 and iOS 8/8 on real devices**. See below |
| 12 | Cart Management, Price Revalidation & Order Summary | **COMPLETE** | 1,815 tests; **Android 15/15 and iOS 15/15 on real devices**; KI-014 cleared. See below |
| 13 | Pickup Time Selection, Arrival Window & Pre-Checkout Validation | **COMPLETE** | 1,914 tests; live server run recorded; device runs as CI reports them. See below |
| 14 | Checkout, Final Order Review, Commercial Calculation & Payment Readiness | **COMPLETE** | 2,023 tests; **Android 5/5 and iOS 5/5 on real devices**; 12 screenshots; review APK built by CI. See below |

## Roadmap numbering — not the delivery sequence above

The table above numbers modules **as they are being built**. An earlier product
roadmap numbered a different set of features, and the two collide: "Module 11"
is Add to Cart in the sequence above and Payments in the list below. Nothing in
this repository is built against the roadmap numbers; they are kept only so the
older planning documents remain readable.

| Roadmap # | Feature | Status |
| --: | --- | --- |
| 07r | Restaurant Availability & Capacity | NOT STARTED |
| R-08 | Order Lifecycle | NOT STARTED |
| R-09 | Route & Corridor Management | NOT STARTED |
| R-10 | Notifications | NOT STARTED |
| R-11 | Payments, Refunds & Settlements | NOT STARTED |
| R-12 | Restaurant Analytics | NOT STARTED |
| R-13 | Reviews & Ratings | NOT STARTED |
| R-14 | Support | NOT STARTED |
| R-15 | Platform Analytics | NOT STARTED |
| R-16 | Promotions | NOT STARTED |
| R-17 | Platform Configuration | NOT STARTED |
| R-18 | Audit & Compliance | NOT STARTED |
| — | **ETA engine** | NOT STARTED | 

## Module 01 detail

**40 of 43 requirements COMPLETE.** Three are BLOCKED by the build environment, not by design:

| ID | Requirement | Blocker |
| --- | --- | --- |
| M01-R41 | Android build validation | `dl.google.com` denied by egress policy (KI-001) |
| M01-R42 | iOS build validation | Requires macOS + Xcode; environment is Linux (KI-002) |
| M01-R43 | PHP static analysis in CI | PHPStan uninstallable via Composer here (KI-003) |

**115 automated tests pass.** All static checks pass. Both web shells and the Flutter app were run
and visually inspected.

## Module 02 detail

**30 of 32 requirements PASSED or COMPLETE.** The two blocked are M02-017 (Android) and M02-018
(iOS) — the same environment restrictions as Module 01, not code defects.

**82 mobile tests pass** (up from 19). `flutter analyze --fatal-infos` clean, `dart format` clean.
All eleven required live-view states were inspected in a rendered app. Module 01 regression: **PASS**
(67 backend + 29 web tests, both web builds).

Eight defects were found and fixed during the module; none left open.

## Module 05 detail

**48 of 51 requirements COMPLETE or PASSED.** Three are pending, none of them a
code failure: Android (KI-001), iOS (KI-002), and live Google Places verification
(KI-004 — no API key in this environment; the adapter is verified against a
stubbed transport).

The module was **reworked**. A first pass built a journey planner — departure
times, traveller counts, notes, upcoming/past/cancelled scopes — derived from the
project roadmap rather than from the specification. The specification is narrower
and different: choose an origin, choose a destination, create a trip, and stop
before anything to do with a route. The first pass was replaced rather than
extended, and the schema, the API, the models and every screen went with it.

**720 automated tests pass** (408 backend, 312 Flutter), plus 4 web. Pint clean,
`flutter analyze` clean, `dart format` clean. Modules 01–04 regression: **PASS**.

Ten defects were found and fixed during the module; none left open. Three of them
could only have been found the way they were: a list filter mismatch that no fake
repository could catch, an accessibility defect that only appeared when driving
the built app, and a spinner that never resolved when a browser left a permission
prompt unanswered.

## Module 06 detail

**66 of 70 requirements COMPLETE or PASSED.** Four are not, and none of them is a
code failure — but one of them is the module's own Definition of Done, so the
module is reported as **NOT COMPLETE**:

| ID | Requirement | Status | Blocker |
| --- | --- | --- | --- |
| M06-051 | Live Google Routes API verification | **PENDING** | KI-012 — no Routes key, and every alternative routing provider is blocked by the egress policy |
| M06-052 | Alternative-route runtime test | **NOT APPLICABLE for this test response** | The configured provider returned one route; none was fabricated |
| M06-053 | Live map SDK render | **PENDING** | KI-011 — no Maps key, no Android SDK, no macOS host |
| M06-065/066 | Android and iOS runtime verification | **PENDING** | KI-001, KI-002 |

The specification's Definition of Done requires a **real route result from a real
provider**, and that cannot be produced here. Everything around it is verified:
persistence, validation, invalidation, selection, ownership, cost control and the
screen. The one live call is not, and calling that a pass would be exactly the
kind of invention this module exists to prevent.

**938 automated tests pass** (527 backend, 382 Flutter, 29 web), plus a 21-assertion
integration run against a live server and database, and 20 live states inspected
in a rendered release build. Pint clean, `flutter analyze` clean, `dart format`
clean. Modules 01–05 regression: **PASS** (three integration runs and Module 05's
own 28-state live run, all green).

Eight defects were found and fixed during the module; none left open. Two of them
were in other modules — a Module 01 error-contract defect that answered **500**
to an unauthenticated request without a JSON `Accept` header, and a Module 03
disposal defect — and two more were in the verification harness itself, where
assertions had been quietly incapable of failing for the right reason.

## Module 07 detail

**60 of 66 requirements COMPLETE or PASSED.** Six are not, and none of them is a
code failure — but one of them touches the module's own Definition of Done, so
the module is reported as **NOT COMPLETE**:

| ID | Requirement | Status | Blocker |
| --- | --- | --- | --- |
| M07-055 | Live routing-provider detour figures | **PENDING** | KI-012 — no Routes key, so the detour is measured against a straight-line road network |
| M07-056 | Alternative-route discovery | **NOT APPLICABLE for this test response** | Discovery reads the selected route by construction; the provider returns one route, so there is no alternative to select |
| M07-057 | Live map render with markers | **PENDING** | KI-011 — no Maps key, no Android SDK, no macOS host |
| M07-058 | Marker clustering | **NOT IMPLEMENTED** | A deliberate scope decision at a 25-result limit, documented in `22-*.md` |
| M07-044/045 | Android and iOS runtime verification | **PENDING** | KI-001, KI-002 |

The consequence worth stating plainly: the detour is the number this product
turns on, and with a straight-line road network every in-corridor stop costs
almost nothing to reach — the largest detour the live run produced for a stop
ahead was four seconds. The *rule* is verified (`RestaurantDiscoveryServiceTest`
excludes a restaurant 400 m from the road with an eighteen-minute detour), the
*arithmetic* is verified, and the pipeline around it is verified against real
route geometry. What is not verified is a real road-network detour, and calling
that a pass would be the exact fabrication this module exists to prevent.

**1 175 automated tests pass** (693 backend, 453 Flutter, 29 web), plus a
22-assertion integration run against a live server, real restaurant rows and
Module 06's real stored geometry, and 21 live states inspected in a rendered
release build. Pint clean, `flutter analyze` clean, `dart format` clean. Modules
01–06 regression: **PASS**.

Seven defects were found and fixed during the module; none left open. Two could
only have been found by driving the built app through its semantics tree — a
screen reader was being told "0 m ahead" about a restaurant the screen labelled
"Behind you", and price level was conveyed by rupee symbols alone. Two more were
faults in the *tests*: a fixture that inherited a factory default nobody had
chosen, and a fixture placed so far from the route that the rule it existed to
prove never ran.

Module 08 has **not** been started, per the one-module-at-a-time rule.

---

## Module 08 — Restaurant Search, Filters, Sorting & Discovery Ranking

**Status: COMPLETE**, with two runtime verifications honestly pending.

| Item | Status | Note |
| --- | --- | --- |
| Search (name, cuisine, city) | **PASS** | Scored relevance tiers, Unicode-safe normalisation |
| Cuisine / facility / price / availability filters | **PASS** | Slug-based, OR within cuisine and price, AND within facilities |
| Maximum detour filter | **PASS** (arithmetic) | Cannot exclude at runtime under `ROUTE_PROVIDER=development` — KI-012 |
| Distance-ahead filter | **PASS** | |
| Rating filter | **DEFERRED, honestly** | No reviews module; `rating_available: false`, no control rendered, nothing invented |
| `highest_rated` sort | **NOT AVAILABLE** | Refused with a reason rather than silently downgraded |
| Recommended / lowest detour / soonest / price sorts | **PASS** | |
| Ranking weights centralised | **PASS** | `config/foodonthego.php`, env-overridable |
| Filter draft state, chips, badge, clear-all | **PASS** | |
| Filtered-empty vs search-empty vs empty-road | **PASS** | Three screens, three ways out |
| Map/list consistency | **PASS** | One result set drives both |
| Pagination and reset-on-change | **PASS** | |
| Cache keyed on route, normalised, invalidated on status change | **PASS** | |
| Cost control — no provider call on a filter change | **PASS** | Counted, not assumed |
| SQL injection, validation, sort allow-list, array limits | **PASS** | |
| Android runtime | **PENDING** | KI-001 — no Android SDK; `dl.google.com` blocked |
| iOS runtime | **PENDING** | KI-002 — no macOS host |
| Live map render | **PENDING** | KI-011 — no Maps key |

**1 280 automated tests pass** (741 backend, 539 Flutter), plus a 28-check
integration run against a live server and real MySQL rows, 28 live states
inspected in a rendered release build, and Modules 01–07 regression green
(13 + 24 + 31 + 21 + 22 integration checks across five smoke runs).

Five defects were found and fixed; none left open. Two of them — a ranking score
that was silently zero for every restaurant, and a filter button that announced
a bare "Filters" over a filtered list — could only be found by running the thing
and reading what it actually produced.

Module 09 has **not** been started, per the one-module-at-a-time rule.

---

## Module 09 — Restaurant Details, Facilities, Availability & Customer Preview

**Status: COMPLETE**, with two runtime verifications honestly pending.

| Item | Status | Note |
| --- | --- | --- |
| Detail API, route-aware | **PASS** | Nested under the trip; no route id to substitute |
| Eligibility on a direct uuid | **PASS** | Suspended, pending, disabled, permanently closed all 404 |
| Suspended and missing share a status | **PASS** | So a uuid list cannot enumerate suspensions |
| Outside-route told apart | **PASS** | 409, because the customer's next move differs |
| Customer-safe response | **PASS** | Raw-body assertion over 16 needles |
| Read-only | **PASS** | Four verbs, none accepted |
| Media, with moderation gate | **PASS** | `is_active` defaults false; relation filters it |
| Gallery, fallback, load failure | **PASS** | Branded stand-in, never a broken icon |
| Description / facilities / price / rating | **PASS** | Each omitted where absent; **New**, never 0.0 |
| Availability: open, paused, closed, gone, unknown | **PASS** | Five states, five buttons |
| Opening hours: normal, split, overnight, closed day | **PASS** | Overnight at 01:00 verified live |
| Timezone, and DST-capable zones | **PASS** | Restaurant's zone from server time |
| Next opening | **PASS** | Eight-day lookahead; silent rather than guessing |
| Route context reuse | **PASS** | Same objects as the card; 10 of 10 opens from cache |
| No provider call on open | **PASS** | Structural — the only caller is already cached |
| No N+1 | **PASS** | Query count unchanged by 20 photographs and 15 more restaurants |
| Discovery state on return | **PASS** | Search, filters, sort, view — and zero requests |
| Request race | **PASS** | Generation-checked; the newest wins |
| Offline, with real age | **PASS** | Except a withdrawn restaurant, which loses its page |
| Android runtime | **PENDING** | KI-001 — no Android SDK |
| iOS runtime | **PENDING** | KI-002 — no macOS host |
| Live map render | **PENDING** | KI-011 — no Maps key |

**1 414 automated tests pass** (801 backend, 613 Flutter), plus a 25-check
integration run against a live server, 25 live states inspected in a rendered
release build, and Modules 01–08 regression green across six smoke runs.

One defect was found and fixed, and it could only have been found by reading the
running app's semantics tree: the discovery card was a single merged node, so
the **View** button had no node at all and a screen-reader user could not open a
restaurant's page.

---

## Module 10 — Menu, Categories & Menu Item Browsing

**Status: COMPLETE**, with the same two runtime verifications honestly pending.

| Item | Status | Note |
| --- | --- | --- |
| Menu API, route- and restaurant-scoped | **PASS** | Same eligibility path as the restaurant page |
| Categories in operator order | **PASS** | `display_order`, then id |
| Items in operator order | **PASS** | Per category |
| Money as integer minor units | **PASS** | Never a float, anywhere; unsigned column |
| Currency travels with the amount | **PASS** | `{amount_minor, currency}`; no rendered string on the wire |
| Client-side formatting | **PASS** | ₹249, ₹349.50, ₹0, ₹12,999 — all from `intl` |
| Inactive category hidden, with its items | **PASS** | Including live items inside it |
| Inactive item hidden | **PASS** | By list and by id |
| Time-limited category | **PASS** | Breakfast absent at 16:00, present at 08:00 |
| Empty category omitted | **PASS** | Not a heading with nothing under it |
| Sold out shown and marked | **PASS** | Dimmed, labelled, not removed |
| Restaurant A context, restaurant B item | **PASS** | `ITEM_NOT_FOUND` |
| Cross-restaurant item in the schema | **PASS** | Composite FK; MySQL 1452 on a direct INSERT |
| Suspended restaurant's menu by uuid | **PASS** | 404 before the menu service is reached |
| Search: match, no match, injection, oversize | **PASS** | In memory; never becomes SQL |
| Two empty states told apart | **PASS** | `visible_item_count` vs `item_count` |
| Customer-safe response | **PASS** | Allow-list; raw-body assertion over 13 needles |
| No invented description, image, diet, spice, allergen | **PASS** | Each absent where the operator published nothing |
| Preparation time not a pickup time | **PASS** | Worded, and spelled out to a screen reader |
| Read-only | **PASS** | Six verb/path pairs, none accepted |
| No N+1 | **PASS** | Two queries for the menu at 6 items and at 500 |
| 500-item menu served whole | **PASS** | 20 sections, 2 queries, ~130 KB, no pagination |
| No provider call on open | **PASS** | Stub count and real provider log both flat |
| Section selector leads and follows | **PASS** | Including a section never built |
| A dish is announced with its diet | **PASS** | Merged label carries name, diet, price, spice, availability |
| Request race | **PASS** | Generation-checked; the newest wins |
| Offline, with the menu kept | **PASS** | Except a withdrawn restaurant, which loses it |
| Android runtime | **PENDING** | KI-001 — no Android SDK |
| iOS runtime | **PENDING** | KI-002 — no macOS host |

**1 550 automated tests pass** (864 backend, 686 Flutter), plus a 32-check
integration run against a live server, 30 live states inspected in a rendered
release build, and Modules 01–09 regression green.

Three defects were found and fixed; none left open. All three were found by
running the thing rather than by reading it:

- the dietary-type wire strings did not match the server's (`VEG` against
  `VEGETARIAN`), so every diet badge would have been silently absent in
  production while every fixture-built widget test passed;
- a punctuation-only search returned the whole menu labelled as its result;
- and the menu card's merged semantics label omitted the dietary type, so a
  screen-reader user could not hear which dishes were vegetarian.

---

## Module 11 — Menu Item Details, Variants, Addons, Customization & Add to Cart

**Status: COMPLETE.** The first module with **no pending runtime row** — Android
and iOS were both verified on real devices, which every module before this one
had to leave open.

| Item | Status | Note |
| --- | --- | --- |
| Item detail with customization | **PASS** | 3 queries for it, flat at 1 group or 10 |
| Variants, absolute price | **PASS** | Regular ₹249, Large ₹329 — not ₹578 |
| Configured default honoured | **PASS** | Never "the first row" |
| Unavailable default is no default | **PASS** | The screen asks rather than quoting |
| Variant availability | **PASS** | Withdrawn absent, sold-out shown disabled |
| Modifier groups with numeric rules | **PASS** | min/max on the wire, not prose |
| Required, optional, single, multi, range | **PASS** | All four shapes exercised |
| Min and max enforced server-side | **PASS** | And on the client, as a courtesy |
| **Addon architecture: one system** | **PASS** | Add-ons are modifier groups; documented |
| Paid option never auto-selected | **PASS** | Enforced in the model, not just the UI |
| Dynamic price preview | **PASS** | Moves instantly; server's figure replaces it |
| **Authoritative backend pricing** | **PASS** | `MenuItemPricingService`, integer minor units |
| **Client price ignored** | **PASS** | 8 tampered fields in one body; charged the real price |
| **Price-increase policy** | **PASS** | Refused with both figures; decrease charged silently |
| Quantity 1..20, tamper-proof | **PASS** | 0, −1, 999999, "two", 2.5, `true` all refused |
| Special instructions, 300 chars | **PASS** | Counted in characters; markup stored as text |
| Item sold-out race | **PASS** | Refused; nothing added |
| Variant sold-out race | **PASS** | Refused |
| Modifier sold-out race | **PASS** | Refused, naming the option |
| Restaurant paused / suspended | **PASS** | 409 and 404 respectively |
| Cart model, scoped three ways | **PASS** | Customer, trip, restaurant — all enforced |
| One active cart per trip | **PASS** | Unique index on a generated column |
| One restaurant per cart | **PASS** | Conflict, named, with nothing mutated |
| Modifier snapshots | **PASS** | Names and deltas at the moment of adding |
| Cart-line matching | **PASS** | Option order canonical; note is part of identity |
| **Idempotency, lost-response retry** | **PASS** | One line at the quantity asked for once |
| Rapid double tap | **PASS** | Guarded twice — in flight, and by the key |
| Foreign trip / foreign cart | **PASS** | 404; the cart is reached *through* the trip |
| Cross-item variant, cross-group option | **PASS** | 422, and impossible in the schema |
| No private fields | **PASS** | 9 needles, raw body, both endpoints |
| Atomic write | **PASS** | One transaction; no half-configured line |
| **No provider call on any of it** | **PASS** | Stub count and real provider log both flat |
| **Android runtime** | **PASS** | **8 of 8** on an API 34 emulator, in CI |
| **iOS runtime** | **PASS** | **8 of 8** on an iPhone simulator, in CI |

**1,729 automated tests pass** (957 backend, 772 Flutter), plus a 48-check
integration run against a live server, **34 live states** inspected in a
rendered release build (61 assertions, 36 screenshots, no problems found), and
Modules 01–10 regression green — **244 integration checks across ten modules,
none failing**.

Four defects were found and fixed; none left open. All four came from running
the thing: three layout overflows at 320 dp, and a disabled quantity button that
had no accessible name — a tooltip becomes a name only on an *enabled* control,
so at quantity one a screen-reader user met an anonymous disabled thing at
exactly the moment they needed to know what it was.

### The device runs

The development machine has neither runtime (KI-001: no Android SDK,
`dl.google.com` blocked by the egress policy; KI-002: no macOS host), so CI
runs `integration_test/module_11_add_to_cart_test.dart` on both, each against a
real Laravel server and MySQL brought up by `scripts/ci-backend-up.sh`. Eight of
eight on both, on `c8c1161`, and again on `f3cf588`.

Worth stating why this is believable, because an earlier claim of a green
device run was **false and was withdrawn** (KI-013). These runs failed,
specifically and informatively, across five heads before they passed — a
mangled invocation, a tap on a control at y=977 in an 890-tall view, a
`CART_TRIP_CONFLICT` the test setup manufactured itself, and twice a button
sitting behind the confirmation snackbar. A harness that reports *that* is a
harness whose green means something. [15-test-evidence.md](15-test-evidence.md)
carries the table.

Three of those four defects existed only because a real screen is 411x890 or
402x874 and a browser window is not.

### Handed to Module 12

**KI-014** — a customer who cancels a journey holding a cart cannot add to any
cart again, on any journey. `CartStatus::Closed` exists and nothing writes it.
Found by the first device run that got as far as adding to a cart, and
reproduced against a real backend in four requests. The refusal itself is
correct; what is missing is the release, and cart lifecycle is Module 12's.
Recorded in [13-known-issues.md](13-known-issues.md).

Module 12 has **not** been started, per the one-module-at-a-time rule.

---

## Module 12 — Cart Management, Price Revalidation & Order Summary

**Status: COMPLETE.** The second module with **no pending runtime row** —
Android and iOS were both verified on real devices, and each ran fifteen checks
rather than seven, because the device jobs now run the whole `integration_test`
directory and so re-ran Module 11's eight alongside Module 12's seven.

| Item | Status | Note |
| --- | --- | --- |
| Full cart read | **PASS** | Lines, options, per-line and cart totals |
| Module 11's badge fields unmoved | **PASS** | Extended, not replaced; a test says so by name |
| Cart read cost is flat | **PASS** | Same query count at one line or three |
| Change a line's quantity | **PASS** | `1..CART_MAX_QUANTITY_PER_LINE` |
| **Quantity zero refused, not removal** | **PASS** | Client declines to ask; server refuses anyway |
| **Re-priced from live menu data** | **PASS** | 30 000, not the snapshot's 32 900, scaled |
| **Price rise refused with both figures** | **PASS** | `PRICE_UPDATED`; cart untouched |
| Price fall applied silently | **PASS** | Nobody needs a dialogue to be charged less |
| Remove a line | **PASS** | Options go with it, by the foreign key |
| Remove the last line → cart CLOSED | **PASS** | Row survives; reported as no cart |
| Empty the cart → CLOSED | **PASS** | Idempotent; emptying an empty cart succeeds |
| **A cart is never deleted** | **PASS** | Five events write CLOSED; nothing deletes |
| Journey usable again after emptying | **PASS** | The index slot is genuinely free |
| **Ownership through the trip** | **PASS** | Another customer's line: 404, not 403 |
| Idempotency on unsafe requests | **PASS** | Key minted per attempt, kept across a retry |
| **Order summary, server-calculated** | **PASS** | `CartTotalsService`, integer minor units |
| Tax on the subtotal once, half up | **PASS** | 20 lines drift by 7 paise if rounded each |
| Restaurant rate overrides platform | **PASS** | And a rate of zero does **not** fall back |
| A charge of nothing gets no row | **PASS** | The total is always shown; the zeroes are not |
| **No float touches money** | **PASS** | A value where the float path answers 14, not 15 |
| **Rates default to nought** | **PASS** | Deliberate; **the business must set them** |
| Revalidation is a read | **PASS** | Called twice against a moved world; nothing written |
| Per-line findings with both figures | **PASS** | Price, item, variant, modifier |
| Blocking vs advisory findings | **PASS** | From the server's flag, not the finding code |
| `totals_if_accepted` withheld | **PASS** | Null the moment a line cannot be priced |
| Kitchen state on the cart | **PASS** | Paused, suspended, off-route all stop it |
| One broken line does not hide others | **PASS** | Three problems reported as three |
| Conflict: two choices, no third | **PASS** | Confirmed before anything is destroyed |
| Conflict names the other cart | **PASS** | From `details`, not from the message |
| **Client never sends a price** | **PASS** | No parameter exists; 8 tampered fields ignored |
| **No provider call on any of it** | **PASS** | Counter flat, with its own negative control |
| **Android runtime** | **PASS** | **15 of 15** on an API 34 emulator, in CI |
| **iOS runtime** | **PASS** | **15 of 15** on an iPhone simulator, in CI |

**1,815 automated tests pass** (1,018 backend, 797 Flutter), plus seven
on-device checks awaiting their run.

### The device runs

The development machine has neither runtime (KI-001: no Android SDK,
`dl.google.com` blocked by the egress policy; KI-002: no macOS host), so CI runs
`integration_test/` on both — an API 34 emulator and an iPhone simulator, each
against a real Laravel server and MySQL brought up by `scripts/ci-backend-up.sh`.
**Fifteen of fifteen on both**, on `cbcf4e5`: Module 12's seven and Module 11's
eight, the latter re-run because the Android job now takes the whole directory
rather than one named file.

The seven, by name:

| # | Check |
| --: | --- |
| 1 | the cart arrives from the server with its lines and totals |
| 2 | the cart is reachable from the menu |
| 3 | the plus changes the quantity the server holds |
| 4 | the minus stops at one rather than removing the line |
| 5 | removing the line empties the cart on the server |
| 6 | emptying asks first, and backing out changes nothing |
| 7 | confirming empties it, and the journey is usable again |

Each asserts against the **server's rows** after the taps, not against what the
screen says. A cart screen that displays the right number while the database
holds a different one is exactly the failure this module exists to prevent, and
a test that only read the screen could not tell the two apart.

The seventh is KI-014's release on a handset: a cart emptied by tapping, and
then an add to the same journey that the old code could never have accepted.

Something Module 11's device test could not do, and this one can: **reset the
cart between tests.** Module 11 had to share one cart across its whole run and
assert on differences, because nothing could release a cart — the dead end
itself. Here each test empties over HTTP and seeds one known line. Being able to
do that is the fix working.

### Thirteen negative controls

Every claim above that could be satisfied by a test that cannot fail was checked
by breaking the code and watching the test go red. Thirteen, each restored
afterwards:

| # | What was broken | What caught it |
| --: | --- | --- |
| 1 | Eager loads removed from the cart read | The flat-query-count test |
| 2 | `null` and `0` tax rates collapsed with `?:` | The zero-is-not-unconfigured test |
| 3 | Snapshot scaled instead of re-priced | The live-repricing test |
| 4 | Emptied cart left `ACTIVE` | Two lifecycle tests |
| 5 | Quote check removed from the repricer | The price-rise refusal |
| 6 | Revalidation made to write the new price back | Four tests, including the one that calls it twice |
| 7 | Totals offered around an unpriceable line | Two revalidation tests |
| 8 | The stepper allowed to reach zero | The never-sends-a-zero test |
| 9 | Charges of nothing given rows | The no-empty-rows test |
| 10 | A price change ranked above a closed kitchen | The notice-order test |
| 11 | Blocking derived from the finding, not the flag | The unknown-finding test |
| 12 | The conflict confirmation removed | The asks-first test |
| 13 | "Keep my cart" made to empty it quietly | *Did not fire* — see below |

The thirteenth is the one worth reading. It did not fire, and the reason was a
defect in the test rather than in the code: its `FakeCartRepository` was
constructed and never wired into the harness, so `emptyCalls` could not move
whatever the code did. Every assertion about it was vacuous. Fixed, and the
control then fired. **An assertion that cannot fail looks identical to one that
passes**, which is the entire argument for running controls on assertions that
look obviously correct.

### Five defects found, none left open

Two of them were tests that had been green for the wrong reason — a `<script>`
in a customer's note that had never been returned by any endpoint until now, and
a cart-conflict fixture describing a server that does not exist. Three were
clock-dependent availability fixtures, the second time that family has turned CI
red on a commit touching no backend code. One suspicion turned out not to be a
bug at all and is written down as such. See
[13-known-issues.md](13-known-issues.md).

### KI-014 is cleared

A cancelled journey's cart used to block every future cart on every journey,
permanently, with no screen that could reach the cart doing the blocking.
`TripService::discard` now closes it in the same transaction that cancels the
trip, and `DELETE /trips/{trip}/cart` lets a customer release one themselves.

### Handed to Module 13

**The tax rate and both fees are nought**, and that is a decision to leave them
visibly unset rather than to guess. The mechanism is built and tested with
non-zero values; the figures are a business input and must be set before
commercial launch.

---

## Module 13 — pickup time, arrival windows and pre-checkout validation

A customer with a cart can now be told when they could collect it, choose one of
those times, and be told by the server whether the order could be paid for. The
module ends there, deliberately: **no order, no order number, no pickup code, no
payment, no capacity reservation** — and tests in both the API and device suites
assert the `orders`, `order_items`, `payments` and `pickup_codes` tables do not
exist at all.

### The arithmetic, and where it comes from

```
earliest_ready = now + preparation + buffer, floored at now + minimum_lead
recommended    = max(arrival, earliest_ready), rounded FORWARD onto the grid
```

Preparation is the **maximum** of the lines, never the sum: a kitchen cooks
several dishes at once. Quantity does not multiply it. Rounding is forward,
always — rounding back recommends a time the kitchen cannot meet.

Proved against a live server rather than only in tests: arrival 06:01, kitchen
ready 05:19, recommendation 06:10, and two dishes reading 20 minutes rather than
40. The output is in
[evidence/module-13-verification-run.txt](evidence/module-13-verification-run.txt).

### What the client is trusted with: nothing

The client receives times and sends back an **opaque 256-bit id**. There is no
field in either request that could carry a time, and the repository interface on
the Flutter side has no parameter one could go in. Not a signed timing payload:
a signed payload still has to be verified correctly on every path, and the day
one path forgets, a customer names their own pickup time.

One customer cannot use another's id, and that is structural rather than
checked — the cache key is scoped to the customer, so the id is looked for under
the wrong prefix and is simply not there. The record it would resolve to also
carries the customer and is compared as well. Expired, forged and stolen all
come back with the **same** code.

### STALE and INVALID are conclusions, not records

A cart stores what the customer chose — `NONE` or `SELECTED` — and nothing but
their own action changes it. Whether that intent still stands is computed on
every read. A column reading `SELECTED` after the restaurant edits its hours is
not wrong because a job failed to run; it is wrong because a column cannot know.

### This is not the ETA engine

Travel comes from the planned route on the assumption the customer sets off now.
That is the module's largest approximation, it is stated on the class and in
[28-pickup-time-planning.md](28-pickup-time-planning.md), and no on-device run
can close it. `ArrivalEstimateProvider` is a seam in the code so that the live
engine replaces one binding and no arithmetic moves.

### Five defects, three of which needed a better test first

[13-known-issues.md](13-known-issues.md) has all five. The three worth knowing
about:

- **The window generator read `day_of_week` with the wrong convention**, shifting
  every restaurant's schedule by a day. Its unit test was green because it
  asserted only that a *closed* day was empty — which is exactly what the wrong
  convention produced. The test agreed with the mistake.

- **A pickup time was stored five and a half hours out.** Eloquent writes a
  zoned date-time by formatting it rather than converting it, so a 1:40 PM
  Kolkata window became `13:40 UTC`.

- **The chosen window came back in UTC while the options beside it came back in
  the restaurant's zone.** Each half was individually correct and the response
  as a whole was not, so no unit test could have caught it. It took the first
  screen that renders both halves together — which is what an on-device run is
  for.

### Still handed forward

**The tax rate and both fees remain nought.** Module 12 flagged this and Module
13 does not change it: the mechanism is built and tested with non-zero values,
and the figures are a business input that must be set before commercial launch.

---

## Module 14 — checkout, commercial calculation and payment readiness

**COMPLETE.** 1,119 backend and 904 Flutter tests pass; five on-device
integration tests pass on an Android emulator and an iOS simulator; twelve
screenshots were rendered from the real app and the real web shells; an Android
review APK and app bundle are built by CI with a manifest.

Design: [29-checkout-and-payment-readiness.md](29-checkout-and-payment-readiness.md).
Handover: [30-client-review-package.md](30-client-review-package.md).

### What a customer can now do

Reach a checkout screen showing an **authoritative payable amount** for a
configured cart with a chosen pickup window, see exactly which commercial
components apply, and be told plainly that payment arrives in the next release.

### What this module deliberately does not do

**No payment, no order, no Razorpay object, nothing marked paid.** A test asserts
the `orders`, `order_items`, `payments` and `pickup_codes` tables do not exist.
`Proceed to payment` asks the server one last question and stops.

### One response, one clock — stated as an invariant this time

Module 13 established the rule after a device run showed the same window rendered
hours apart, and fixed the field rather than the rule. This module found the rest:
five instants in UTC beside two at `+05:30`, which renders as a quote held until a
time seven hours in the customer's past.

Both bodies now render every instant on the restaurant's clock, and each is pinned
by a test that walks the whole response and fails on two offsets — a test that
names no fields, so a field added later is covered by a test written before it
existed.

### Configured is not the same as zero

A rule nobody has configured is **absent** from the response and absent from the
screen. A rule configured as zero is a row whose amount is zero. The column that
made this inexpressible — `packaging_fee_minor NOT NULL DEFAULT 0` — was made
nullable, because otherwise every restaurant on the platform read as having
configured a fee of nothing.

### Still handed forward

**`COMMERCIAL POLICY PRODUCTION READINESS = PENDING CLIENT DECISION`.** Tax,
packaging, service and convenience fees, commission and discounts are all unset.
The mechanism is built and tested with non-zero values; the figures are a business
input.

**`EXTERNAL REVIEW URL = PENDING`** — nothing is deployed.
**`iOS REVIEW BUILD = PENDING — APPLE SIGNING/TESTFLIGHT ENVIRONMENT UNAVAILABLE`.**
**Six of seven roles have no login and no API surface**, so no credentials exist
for them and none were invented.
