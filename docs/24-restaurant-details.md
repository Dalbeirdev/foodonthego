# 24 — Restaurant details, facilities, availability and preview

Module 07 decides which restaurants are on a customer's route. Module 08
decides which of those they are looking at. Module 09 answers the question they
opened one to ask:

> **Is this the right place for me to stop?**

Everything on the screen serves that question. There is no favourite button, no
share sheet and no reviews list, because none of them helps answer it.

---

## The design, in one line

```php
$discovered = $this->discovery->discover($trip, $now);   // Module 07, cached
foreach ($result->restaurants as $found) {
    if ($found->restaurant->uuid === $restaurantUuid) return $found;
}
```

`RestaurantDetailService` asks Module 07 what is on the route and looks for the
requested restaurant in the answer. Three consequences follow, and none of them
is a rule anybody has to remember:

1. **Eligibility cannot be bypassed.** A suspended, unverified, disabled or
   permanently closed restaurant is not in the discovery result, so knowing its
   uuid buys nothing. There is no second query here with its own `where`
   clauses to get wrong.

2. **Opening this screen calls no routing provider.** `discover()` is cached
   per route and is the only thing in the application that can reach one. A
   customer tapping through five restaurants spends nothing.

3. **The figures match the card they tapped.** The detour and distance-ahead on
   this screen are the same objects the list rendered, not a second calculation
   that might round differently.

The profile half — description, photographs, the weekly schedule — is a
separate, cheap read, because discovery deliberately does not load media or pay
for a fortnight's hours arithmetic for twenty restaurants at once.

---

## The API

```
GET /api/v1/customer/trips/{trip}/restaurants/{restaurant}
```

Nested under the trip, like the list. "How far ahead is this and what does
stopping cost" has no meaning away from a journey, and a detail screen that
answered without one would be a generic restaurant page.

Sanctum-authenticated. The trip resolves through `TripService::ownedByOrFail()`,
so somebody else's journey is *not found* rather than found-and-refused. Shares
the discovery throttle: opening a page calls no provider, but it does reach
`discover()`, and a cold cache there costs what the list costs — sharing the
budget is what stops a loop over uuids from being a cheaper way to spend it.

### What comes back

| Block | Fields |
| --- | --- |
| Identity | `id` (uuid), `name`, `short_name`, `city`, `formatted_address`, `location` |
| Profile | `description`, `public_phone`, `media[]`, `cuisines[]`, `facilities[]`, `price_level`, `logo_url`, `cover_image_url` |
| Reviews | `rating`, `review_count` — both null until a reviews module exists |
| Availability | `availability` (Module 07's vocabulary), `is_accepting_orders` |
| Can I order | `ordering.state`, `ordering.can_order`, `ordering.can_browse_menu` |
| Hours | `hours.timezone`, `hours.today`, `hours.week[]`, `hours.current_window`, `hours.next_open_at` |
| Route | `route.proximity_meters`, `detour_distance_meters`, `detour_duration_seconds`, `distance_ahead_meters`, `time_ahead_seconds`, `requires_backtracking` |
| Freshness | `generated_at`, `route_from_cache` |

`availability` keeps Module 07's meaning exactly. `ordering` is the derived
rollup Module 09 adds. Two names for one concept would be a bug; one name for
two concepts is worse.

### Error codes

| Code | Status | Meaning, and what the client does |
| --- | --- | --- |
| `RESTAURANT_NOT_FOUND` | 404 | No such restaurant. Back to the list |
| `RESTAURANT_UNAVAILABLE` | 404 | Real, and withdrawn since the list was read. Its own words, and no "Try again" |
| `RESTAURANT_OUTSIDE_ROUTE` | 409 | Real and trading, on a different road. Its figures do not exist for this journey |
| `ROUTE_NOT_READY` | 409 | The trip has no usable selected route |
| `TRIP_NOT_FOUND` | 404 | Not this customer's journey |
| `DETAIL_LOAD_FAILED` | 500 | Ours. Retryable |

**Both of the first two are 404.** A 403 on the suspended one would tell
anybody holding a list of uuids exactly which businesses this platform has
suspended.

---

## Availability, and the five things a screen has to say

`RestaurantOrderingState` rolls up two independent facts: is this business
trading at all (`RestaurantStatus`), and are its doors open and its kitchen
taking orders (`RestaurantAvailability`).

| State | Copy | CTA |
| --- | --- | --- |
| `OPEN_ACCEPTING` | Open · Accepting orders | **View menu**, live |
| `OPEN_PAUSED` | Open · Not accepting orders right now | Browse the menu |
| `CLOSED` | Closed — and when it opens again | Browse the menu |
| `CLOSED_PERMANENTLY` | Unavailable | Disabled |
| `UNAVAILABLE` | Opening times unknown | Disabled |

Deliberately not a boolean. "You cannot order" covers a restaurant shut until
tomorrow, one that is open with its kitchen paused, and one that has closed for
good — three different sentences and three different next moves.

### Two rules the arithmetic obeys

**The pause beats the clock.** A restaurant inside its opening hours that has
stopped taking orders reads `OPEN_PAUSED`, never "accepting orders". Sending
somebody forty kilometres for food nobody will cook is the worst thing this
module could do.

**The business state beats the clock.** A permanently closed restaurant inside
its old opening hours is not "open" — that is exactly the case a naive
implementation gets wrong.

**And an absence never becomes permission.** No hours on file is `UNAVAILABLE`,
not "open". The safe direction for a missing fact to fall is towards "we don't
know".

### Menu browsing while shut

`can_browse_menu` is true for a restaurant that is merely closed or paused, and
false once a business has closed for good. A traveller two hours away wants to
read the menu now and order when they arrive; a menu for a business that no
longer exists describes nothing.

Module 10 owns the menu. The flag is defined here so the rule is settled before
the screen that depends on it is built.

---

## Opening hours

`RestaurantHoursService` answers what `RestaurantAvailabilityService` does not:
today's windows, the whole week, the current window, and when a shut restaurant
opens again.

Two services rather than one because they run at different moments and at
different costs. Availability runs for twenty restaurants on a discovery screen
and must stay cheap; this runs for one restaurant and can afford to walk a
fortnight looking for the next open minute.

### The cases it gets right

| Case | Behaviour |
| --- | --- |
| **Overnight** — 18:00 to 02:00 | Belongs to the day it *opens*. At 01:00 on Tuesday the window covering you is Monday's |
| **Split service** — 11:00–15:00, 18:00–23:00 | Two windows; 16:30 is shut |
| **A day off** | An empty window list, not a missing row. "Closed" is an answer; a gap is a question |
| **The opening minute** | Open. Inclusive at the open, exclusive at the close |
| **The closing minute** | Shut. A customer arriving exactly then has arrived too late |
| **Timezone** | The restaurant's, from server time. Never the device clock |
| **DST** | Delegated to the date library. India does not observe it; this platform is not staying in India forever |
| **An unusable timezone** | Falls back to the configured default and warns in the log. Silently reading Asia/Kolkata for a restaurant in Goa is a wrong answer that looks like a right one |

### Why "today" excludes last night's window

A window that opened at 18:00 yesterday and is still running at 01:00 is **not**
in `hours.today`. Under the heading "Today", a customer reading "18:00 – 02:00"
at one in the morning would reasonably expect it to start again this evening.
`current_window` is what answers "and are you open right now".

### Next opening

`next_open_at` is an instant, not a wall-clock string, so an overnight window
closing at 02:00 gives tomorrow morning rather than a time that has passed. It
is null in three cases the caller must not distinguish by guessing: no hours on
file, the restaurant is open now, or nothing opens within the eight-day
lookahead. Each is a reason to say nothing rather than to print a time.

Eight days rather than seven: a restaurant open only on Mondays, asked on a
Monday evening, opens again in six days and some hours, and the extra day covers
the wrap without a special case.

### The two implementations agree

Both services answer "does this window cover this moment", because the cheap one
has to. `RestaurantHoursTest::test_the_two_services_agree_about_being_open`
compares them across a week of split and overnight hours, so they cannot drift
apart quietly.

---

## Media

`restaurant_media` is a relation, not more columns: `image_1_url` through
`image_5_url` is a schema that runs out.

| Column | Why |
| --- | --- |
| `url`, `thumbnail_url` | Delivery URLs. Nothing in the customer API composes a bucket path |
| `alt_text` | The operator's own caption. Nullable, and never invented |
| `width`, `height` | So the page reserves the right box and does not jump |
| `position` | The operator's order |
| `is_active` | **Defaults to false** |

`is_active` is a moderation gate, not a soft delete. Media will arrive from an
operator dashboard a later module builds, and a photograph nobody has looked at
must not reach a customer because it was uploaded. Defaulting to invisible puts
the mistake on the safe side, and the relation itself is scoped — a query that
forgets `->visible()` still cannot reach an unmoderated image.

### On the screen

- **No photographs** → a branded placeholder. Never a broken image icon, and
  never a stock photograph of somebody else's dining room. A picture under a
  business's name is a claim about premises nobody has seen.
- **One photograph** → no gallery. A "1 / 1" indicator and a swipe that goes
  nowhere both promise something that is not there.
- **Several** → a swipeable gallery with a counter.
- **A photograph that fails to load** → the same branded stand-in.
- **Accessibility** → the operator's caption where there is one; otherwise
  "photograph 2 of 5", which at least says where you are. Never an invented
  description of the picture.

### Fixture images

The seeded fixtures use a one-pixel data URI. Every alternative is worse: a
stock photograph is a claim about premises; a link to a real restaurant's
website borrows their bandwidth and their picture; a broken URL makes every
fixture exercise the failure path instead of the normal one.

---

## Things a restaurant did not tell us

| Missing | What the screen does |
| --- | --- |
| Description | No **About** section |
| Facilities | No **Facilities** section |
| Price level | No price in the header |
| Rating | **New**, never `0.0` and never a hopeful 4.5 |
| Public phone | No contact line |
| Photographs | The branded placeholder |

An empty card with a heading over blank space reads as a bug, and inventing
content to fill it would be worse. `0.0` in particular is not "unrated" — a
customer reads it as "everybody hated it".

The `[TEST] Bare Bones Stop` fixture has none of these, so the four omissions
are a state somebody can look at rather than a branch nobody exercises.

---

## Privacy

The response is built from `Restaurant::toDiscoveryArray()` — an allow-list —
plus the profile fields Module 09 added. Absent, and asserted absent against the
**raw body** rather than against parsed keys:

owner name · owner phone · owner email · tax identifier · bank reference ·
commission rate · internal notes · verification status · discoverability ·
soft-delete timestamps · the sequential primary key

`public_phone` is a **different column** from `owner_phone`. Two columns rather
than one flag with a visibility boolean, because a single "phone" is one
forgotten `where` clause away from publishing somebody's personal mobile.

### Read-only

There is no customer-facing write route for a restaurant. `PUT`, `PATCH`,
`DELETE` and `POST` on the detail path all answer 404 or 405 — asserted, in both
the API tests and the integration run, because "there is no such route" is a
claim worth checking rather than assuming.

### Text a restaurant typed

Names and descriptions will eventually be entered through an operator dashboard.
They are stored and returned **verbatim**, as data. Flutter draws text and
cannot execute it; a future React surface must not hand these to
`dangerouslySetInnerHTML`. What must not happen is silent mangling on the way
out, which hides the problem from whoever eventually finds it.

---

## Caching

| Half | Source | Freshness |
| --- | --- | --- |
| Route context | Module 07's discovery cache, per route | 5 min |
| Detour per restaurant | Module 07's cache, per route and restaurant | 1 hr |
| Profile | Read fresh on every request | — |
| Availability | Computed fresh on every request | — |

The profile is not cached separately. It is one indexed read with four eager
loads, and a second cache would buy a millisecond in exchange for a staleness
window on a screen where "are you open" is the important question.

**Operational state is always re-read.** The discovery result may be five
minutes old, so the detail service reads the restaurant row again and recomputes
availability from it. A restaurant that paused its kitchen after the list was
rendered shows as paused on the page — proven in `RestaurantDetailApiTest` and
against the live server in the integration run.

The route context is keyed by route, so a customer who changes their selected
route gets figures for the new one; the old key is simply not consulted.

---

## Client state

```
preview       what the card knew, drawn immediately, never authoritative
detail        what the server said
isLoading     first load, nothing behind it
isRefreshing  pull-to-refresh over content already on screen
isOffline     the last load failed for want of a network
hoursExpanded / galleryIndex
```

### The newest request wins

Every request takes a generation number and only the newest may write. A
customer tapping through three restaurants generates three requests that can
return in any order; without this the slowest lands last and puts one
restaurant's photographs under another restaurant's name.

### A failed refresh keeps the page — unless the restaurant is gone

Losing what a customer already has because a refresh failed punishes them for
our outage, so a network failure keeps the page and adds an offline banner with
the real age of what is shown.

The exception is deliberate: a refresh that returns `RESTAURANT_UNAVAILABLE`
**takes the page away**. Leaving it up would present a suspended business as
though it were trading.

### Discovery survives the round trip

The detail route is nested under the discovery route, so `push` and back never
leave it. The search the customer typed, the filters they chose, the sort they
picked and the map/list toggle are all still there, and no request is spent
restoring them — asserted in
`discovery_filters_screen_test.dart::coming_back_keeps_the_search_and_the_filters`.

The back button is wired to `context.pop()` rather than to the automatic one.
`Navigator.maybePop` pops the widget stack without telling go_router, which
leaves its match list empty and the shell without a location.

---

## Offline

A cached page is shown with a banner carrying the **real** age of the payload —
`generated_at` from the response, never a fabricated timestamp — and the words
say opening times may have changed. The open sign is never presented as live
when the network was not reached.

---

## Handoff to Module 10

Module 10 — menu, categories and menu item browsing — receives:

- `restaurant_id`, `trip_id` and the selected route context, in the URL the
  detail screen already lives at.
- `ordering.can_order` and `ordering.can_browse_menu`, so the menu screen knows
  whether to show prices with an add button or to show them read-only.
- The availability vocabulary, unchanged since Module 07.

What Module 10 must not assume: that a restaurant on screen is still open. The
availability in a detail response is a snapshot re-checked on each request, and
a menu opened five minutes later has to ask again.

### What Module 10 did with it

The menu screen does ask again, on every request — and it does so through this
service rather than around it.

`RestaurantDetailService` now has two entry points. `detail()` is this module's
and is unchanged in behaviour. `orderingContext()` is the eligibility half
without the profile: it runs the same `onRoute()` lookup and the same freshness
re-read, and skips the photographs, cuisines, facilities and fortnight of
opening-hours arithmetic that a menu screen never renders. That took a menu open
from twenty queries to seventeen.

Both go through `onRoute()`, so **who may see a restaurant is decided in one
place** and cannot drift between the two screens. A restaurant whose page 404s
has a menu that 404s, for the same reason and by the same code.
