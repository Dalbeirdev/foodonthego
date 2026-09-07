# 17 — Customer app UI

## Screen hierarchy

```
FoodOnTheGoApp                     theme · localization · router · text-scale clamp
├── SessionSplash                  while secure storage is read — never flashes a wrong screen
├── WelcomeScreen                  unauthenticated entry, one decision, no form
├── PhoneEntryScreen               country picker + number, nothing else asked
├── OtpVerificationScreen          countdown · resend · change number
├── RegistrationScreen             first name required, everything else optional
└── CustomerShell                  offline banner · bottom navigation · Android back
    ├── HomeScreen                 loading | error | data
    │   ├── GreetingHeader
    │   ├── JourneyPlannerCard     ← the primary action
    │   ├── CurrentJourneyCard     ← only when a journey exists
    │   ├── ActiveOrderCard        ← only when an order exists
    │   ├── HowItWorks             ← only when neither exists
    │   └── QuickActions
    ├── TripsScreen                EmptyStateView
    ├── OrdersScreen               EmptyStateView
    ├── NotificationsScreen        EmptyStateView
    └── ProfileScreen              header + three grouped sections
TripsScreen                        two scopes | loading | empty | error | list
TripPlannerScreen                  two rows and a button
LocationPickerSheet                current location · saved addresses · search
TripDetailScreen                   one journey, in full
EditProfileScreen                  three editable fields; the phone is read-only
SavedAddressesScreen               loading | empty | error | list
AddressFormScreen                  create and edit, one screen, one form
ComingSoonScreen                   pushed over the shell
```

## The authentication screens

Four screens, each with one job, and a guard that decides which of them (or the shell) is on screen.
The reasoning behind each control is in
[18-customer-authentication.md](18-customer-authentication.md); what matters for the UI:

**Welcome** explains the product before asking for anything. A sign-in screen that opens with a
phone field is the last screen a lot of people see. The copy scrolls and the action is pinned, so it
stays reachable at a 1.4× text scale on a short device.

**Phone entry** asks for a number and nothing else — no device id, no referral code, no marketing
opt-in. The country picker is a bottom sheet rather than a dropdown: at four markets a dropdown
would do, but a sheet stays usable at twenty and at large text sizes. The picker sits inside the
field as a `prefix`, so the dial code and the digits share a baseline and read as one number.

**Code entry** is one real text field behind the appearance of digit boxes, never one field per
digit: separate fields look identical and behave badly — they break paste, fight SMS autofill, and
make backspacing an accessibility problem. Two countdowns run, both a courtesy over a server rule.
An expired or exhausted code clears the field and ends the countdown, which turns *Resend code* on:
the screen offers the action that can actually help rather than inviting another doomed attempt.

**Registration** shows the verified number back as a chip and has no field to change it. First name
is required; surname is optional because plenty of people have one name, and a required surname is a
wall they cannot pass. Email is optional and labelled with why it is wanted.

Every failure is a sentence the customer can act on, chosen by the API's machine-readable error code
— never the server's own prose, which is free to be reworded or translated.

## Journeys

The Trips tab is a list with a two-way segmented control above it — Planned and
Discarded — and the same four states as every other list in this app. A row leads
with the two ends, because "New Delhi → Jaipur" is how somebody identifies their
own journey.

The second line says **"Route not calculated yet"**. Not a distance, not a travel
time, not a progress bar: there is no route, and Module 06 is what adds one. A
placeholder number would be read as a real one by everybody who saw it, which is
why several tests exist purely to fail if one appears.

Discarded is spelled out as a word in a badge, never signalled by colour alone.
The row's overflow menu names its own journey ("Options for New Delhi → Jaipur"),
and it is offered only while the server would still accept the action — a menu
that offers something the server will refuse teaches people not to trust the
menu.

There is no "Past" scope, because nothing in this module observes a journey
happening and a tab that never fills is worse than no tab.

### The planner

Two rows and a button. Tapping either row opens the picker; the button creates
the journey; a swap control between them turns it round, and works with one end
chosen as well as two, because somebody who typed their destination into the
wrong box expects it to move rather than nothing to happen.

The button stays **enabled while the plan is incomplete**, so tapping it says
what is missing. A disabled button that will not explain itself is the most
common dead end in a form.

Under it, in as many words:

> Route and travel time arrive with the next release. This saves where you are
> going.

That is there instead of a map placeholder, which would look like something
loading.

### Choosing a place

One sheet, three ways in, in the order people reach for them: the device's own
position, a saved address, a search. All three produce the same value, so nothing
downstream needs to know which was used.

**Current location** is where the app asks for permission — the only place it
does, and never before. Every outcome has its own words and its own way onwards,
and every one of them offers the search box, because a permission wall with no
alternative is how an app traps somebody. "Location is switched off" is never
reported as a refusal: the customer refused nothing.

**Saved addresses** are listed with the default first. One that has never been
located is shown rather than hidden, and tapping it explains why it cannot be
used and points at the search box — the alternative is inventing a position for
it.

**Search** waits 350 ms after typing stops, so a whole word costs one request
rather than six, and discards any answer that is no longer for the current query.
A suggestion carries no coordinates: choosing one resolves it, and the position
comes back from the server with the place.

### Locating a saved address

The address form gained a **Find this address** row, because Module 04 let a
customer write an address down but never gave it a position — so no saved address
could be one end of a journey. It opens search alone: offering the device's
position would pin an address somebody is describing from memory to wherever they
happen to be standing, and offering the saved addresses would be circular.

Leaving it unlocated is fine. The address still works as an address; it simply
cannot be an end of a journey yet, and both screens say so.

Both Module 04 layout rules apply throughout: a non-lazy scrolling `Column` so
validation cannot skip an off-screen field, and a primary action that is never
under the keyboard or the navigation bar.

### On home

Home shows the customer's current journey when there is one, and nothing at all
when there is not. The card shows the two ends, when it was planned, and — stated
rather than implied — that the route has not been worked out. No progress bar, no
remaining time, no next pickup. Module 02's card drew all three from fixture
data; a progress bar at zero would imply the app is tracking a journey it cannot
see.

The planner card's two rows show whichever ends that journey has, so the card
reflects reality rather than always inviting a journey the customer has already
planned.

## The three home states

The layout is **conditional, not padded**. A customer with no journey sees no journey section — not
an empty container captioned "no journey". An empty shell is worse than an absent one: it implies
something is broken.

| State | Journey | Order | Explainer |
| --- | :-: | :-: | :-: |
| New customer | — | — | ✅ How FoodOnTheGo works |
| Active journey | ✅ | — | — |
| Active order | ✅ | ✅ | — |

The explainer earns its place only when there is nothing more useful to show; once a real journey
exists it disappears rather than pushing real content down.

## Design decisions

**The planner is a route, not a form.** An origin dot, a dashed line, a destination pin — that is the
product in one glance. Two stacked text fields look like every other search screen.

**The fields are tappable rows, not `TextField`s.** They accept no input in this module, so rendering
them as text fields would open a keyboard onto a control that cannot be typed into. That is the whole
of the keyboard story for Module 02: there is no editable control anywhere in the customer app yet.

**The order card leads with *when to be there*, not what was ordered.** The countdown is the largest
element; the status track sits beneath it. A traveller deciding whether to pull over needs one number.

**The countdown floors at zero.** An estimate the clock has overtaken reads "Ready now", never
"-3 min".

**Order status varies three things, not one.** Colour, icon and label. Roughly one man in twelve
cannot reliably separate amber "Cooking" from green "Ready" — and that is the moment that matters
most.

**A cancelled order draws no progress track.** Rendering the remaining steps as "still to come" for
an order that will never reach them would be a lie.

**Empty states teach.** They say what will appear, why it is worth having, and offer the one action
that fills it.

## The route motif

The product is FOOD + ROUTE + TIME + PICKUP, and the route half is carried by a recurring visual:

- a ringed origin dot and a destination pin in the planner, joined by a dashed line
- the same pairing, horizontal, on the journey card, with a progress bar between them
- a dashed ring around every empty-state icon — a road circling the subject
- numbered stops joined by a line in *How FoodOnTheGo works*

Teal is the journey; amber is the food. Keeping them in different hues means a screen showing both is
readable at a glance.

## Reusable components

| Component | Location |
| --- | --- |
| `PrimaryButton` / `SecondaryButton` / `LinkAction` | `shared/widgets/buttons.dart` |
| `SectionHeader` | `shared/widgets/section_header.dart` |
| `EmptyStateView` | `shared/widgets/empty_state_view.dart` |
| `AppErrorView` | `shared/widgets/app_error_view.dart` |
| `OfflineBanner` | `shared/widgets/offline_banner.dart` |
| `AppSkeleton` / `HomeSkeleton` | `shared/widgets/app_skeleton.dart` |
| `OrderStatusChip` / `OrderStatusTrack` | `shared/widgets/order_status_chip.dart` |
| `CustomerShell` | `shared/widgets/customer_shell.dart` |
| `GreetingHeader`, `JourneyPlannerCard`, `RouteSummaryCard`, `ActiveOrderCard`, `QuickActions`, `HowItWorks` | `features/home/widgets/` |

### Empty states on a short screen

`EmptyStateView` shrinks its motif and tightens its spacing below 420px of
height. The illustration is decoration; the action under it is not, and on a
320×568 screen only one of the two fits above the fold. Measured, not guessed:
the Trips action landed 13px below the display before this rule existed.

## Loading, error, offline

**Loading** is a skeleton shaped like the content it replaces — greeting line, planner card, journey
card — so the page does not visibly reflow when data lands. A centred spinner tells the user nothing
about what is coming. The shimmer stops under `prefers-reduced-motion`.

**Errors** map a `HomeFailureKind` to a cause the customer can act on, with distinct wording for
offline, timeout, server-unavailable and unknown. A raw exception is never rendered: it is
meaningless to a traveller, and a stack trace in a screenshot is an information leak.

**Offline** is a non-blocking banner below the status bar. Someone who has lost signal should still
be able to read the order already on screen; a modal would take away the only useful thing left. It
is a live region, so a screen reader announces the change.

## Animation

| Where | What | Duration |
| --- | --- | --- |
| Bottom navigation | Indicator slide, icon fill | 220ms |
| Journey progress | Bar grows from zero on first paint | 320ms decelerate |
| Order status track | Segments fill in sequence | 320ms |
| Offline banner | Height in/out, content settles rather than jumps | 220ms |
| Buttons | Material ink + 1px press translate | 80ms |
| Skeletons | Shimmer sweep | 1200ms loop |

Short on purpose: in a moving vehicle a long transition reads as lag, not polish. Everything routes
through `FotgMotion.respectingReducedMotion`, and the skeleton stops looping entirely.

Nothing pulses, bounces or animates on every element.

## Accessibility

- **48dp touch targets**, above the 44pt/48dp floor, because this is tapped one-handed by someone
  about to drive. The avatar's tappable box is 48 even though the circle is 46.
- **Text scaling honoured and clamped to 1.4x.** Android allows 2.0x, which turns a 34sp greeting
  into 68sp and pushes the primary action off screen.
- **The greeting steps down on narrow screens.** At 34sp on 320dp it truncated to
  "Good evening, R…", losing the name — the entire point of a greeting.
- **Semantic labels** on the avatar, status chips, progress track, quick actions and route endpoints;
  `header: true` on section titles so a screen-reader user can jump between sections.
- **Status is never conveyed by colour alone.**
- **`SafeArea` everywhere**, never hard-coded insets, with edge-to-edge system bars.

## Light and dark

Both are supported and follow the OS (`ThemeMode.system`). A phone in a windscreen cradle at night is
in dark mode for a reason.

## Orientation

Portrait only for now (`main.dart`). Landscape is a real layout with real work behind it; shipping a
stretched portrait layout would be worse than not offering it.

## The profile identity block

From Module 03 the header reads the **session**, not the home dashboard: name, initials and the
masked number come from the signed-in account. The number is masked even here, on the account's own
screen — a phone is read over shoulders and screenshotted into support tickets, and the last four
digits are enough to confirm which number it is.

Sign out is behind a confirmation dialog. That is not friction for its own sake: signing back in
means waiting for an SMS, so an accidental tap in a list people scroll has a real cost.

From Module 04 the first two rows open real screens. **Edit profile** offers exactly three fields —
first name, last name, email — and renders the verified number as a locked field with a lock icon and
a sentence explaining that it is the verified number for this account. It is not a disabled text
input the customer might try to fight; it looks like what it is, a fact about the account rather than
a field. **Saved addresses** shows a live count in its trailing text, so the row says something
before it is tapped.

The rest of the list still routes to a controlled placeholder naming its module. A form that
silently discards what somebody typed is worse than one that is honestly not there yet.

## Saved addresses

The list is default-first, then newest, and each row carries its type icon, its label, a one-line
address and — on the default — the word **DEFAULT**, spelled out rather than signalled by colour
alone. The row menu is a single overflow button whose tooltip names its row ("Options for Home"),
because a screen reader announcing "Edit" four times tells you nothing about which one you are on.

Four states, all real:

- **Loading** — a skeleton of the list shape, not a spinner on a blank screen, so the layout does not
  jump when the data lands.
- **Empty** — an illustration, a sentence, and the add button as the primary action. This is the
  first thing a new customer sees, so it is a starting point rather than an apology.
- **Error** — the message the error code maps to, plus Retry. Never the server's prose.
- **List** — pull to refresh, and a per-row busy state so setting a default disables that row rather
  than freezing the screen.

Nothing here is optimistic. A row does not show DEFAULT until the server has confirmed the change, an
address is not added to the list until it has an id from the database, and a deletion removes the row
only after the server has deleted it. If the server refuses, the list is what the server says it is
and a snackbar says what went wrong.

### The form

One screen for create and edit, because they are the same fields and two screens would drift apart.
The type selector is a segmented control; choosing **Other** reveals the label field, and it is
required only there — Home and Work name themselves.

Two layout rules were learned the hard way and are pinned by tests. The form scrolls in a **non-lazy
`Column`**, not a `ListView`: `ListView` builds lazily, so a field scrolled off screen is never
registered with the `Form` and `validate()` skips it silently. And the primary action is **pinned to
the bottom** above the keyboard, not placed after the last field, where on a small screen it sat
under the bottom navigation bar and the tap went to the wrong widget.

## The route screen

Reached from a journey — from the detail screen's "Calculate route", or from a
journey that already has one. Map above, summary below, in a 4:5 split, so the
map takes what is left after the sheet rather than framing itself for the whole
screen and then being covered by it.

The summary sheet, in order: both place names, then **Travel time** and
**Distance** as two large figures, then the traffic delay where the provider
supplied one, then the sentence that keeps this module honest —

> Driving time from the route. Pickup timing arrives with restaurants.

— then how long ago it was calculated, then "Calculate again", then the
alternatives if there are any.

Four rules the screen follows:

1. **Opening it does not spend money.** The route is calculated once per journey,
   automatically only if there is none, and never again on a rebuild. "Calculate
   again" is the only thing that asks a second time.
2. **A failure never costs the customer what they already had.** A refresh that
   fails leaves the existing route on screen with a banner, rather than replacing
   a working route with an error.
3. **No selection is optimistic.** Tapping an alternative asks the server; the
   screen shows what came back. A choice the server refused must not linger
   looking accepted.
4. **Every failure is its own state.** No route, timed out, busy, provider down,
   offline-with-a-route, offline-with-nothing — six states rather than one
   "something went wrong", because the customer's next move differs for each and
   two of them should not offer a retry at all.

### When the map cannot be drawn

Not an error state. The screen shows the map icon, one line of explanation, both
place names, and the entire summary underneath — everything except the picture.
A customer whose tiles will not load still needs to know where they are going,
how far it is and how long it takes.

## Discovery: food on your route

Reached from the route screen's "Find food on this route" — the only way in,
because discovery has no meaning without a journey and a journey without a
calculated route cannot be searched along.

Header, toggle, then results. The card is the module in miniature:

> **Highway Spice Kitchen**  ·  *Open*
> North Indian, Vegetarian · ₹₹
> **66 km ahead**   ·   4 min detour
> 900 m off your route
> Parking · Restroom · Seating

Reading order is the argument. **How far ahead** and **what the stop costs** come
first and largest, because those are the two facts that decide whether somebody
stops here rather than at the next one. The name is the heading; cuisine, price
and rating are supporting detail; how far off the road it sits is a third,
quieter line — a useful signal, and never a substitute for the detour.

Four rules the screen follows:

1. **Opening it searches once.** Discovery is the most expensive endpoint in the
   application, and a rebuild, a map pan, or a switch between map and list never
   costs a second request.
2. **Nothing is invented.** A restaurant with no rating shows none; one whose
   detour could not be established says "Detour unknown" rather than showing a
   zero.
3. **Closed is not hidden.** A shut restaurant is still a fact about the road.
   "There is somewhere and it is shut" is a different and more useful answer than
   "there is nothing here", and a whole result set of them gets its own words.
4. **A paused restaurant never reads as available.** Open by the clock and not
   cooking is "Not accepting orders", in words, on the chip and in the spoken
   label.

### Map and list

The same results, two presentations, and switching between them never re-runs the
search. The map draws the selected route at all times — including while a
restaurant is selected, because a discovery map that loses the route has stopped
answering the question it exists for and become a pin on a generic map. Only the
restaurants in the result set are marked; a nearby restaurant the server rejected
on detour is not quietly offered anyway.

Marker and card are one selection, not two. Tapping either highlights both,
because they are the same act and giving them separate state is how the two come
to disagree.

### States

| State | What it shows |
| --- | --- |
| Loading | Card skeletons and "Finding food stops along your route…" |
| Results | The stops, in journey order |
| Empty | "No stops on this route yet", naming the corridor that was searched |
| Closed only | The stops, above a notice that none is taking orders |
| Route not ready | "Work out your route first", and a way back to the route |
| Rate limited | "Just a moment" |
| Failed | A retry |
| Offline, cached | The stops, and a banner that opening times may have changed |
| Offline, cold | An offline state |
| Map unavailable | Both place names and how many stops were found |

## Development harness

A floating control (development builds only) that switches persona, forces offline, and forces a
failure — so the loading, error and offline states can be *inspected in a running app*, not merely
asserted in tests. It renders `child` untouched when the environment forbids fixtures.

---

## Discovery, refined (Module 08)

The discovery screen keeps everything above and adds four controls between the
app bar and the results.

```
┌──────────────────────────────────────────────┐
│ ← Food on your route                         │
│   New Delhi → Jaipur International Airport   │
├──────────────────────────────────────────────┤
│ 🔍 Search stops on your route            ✕   │
│ ⟨ North Indian ✕ ⟩ ⟨ Parking ✕ ⟩   Clear all │
│ 3 of 12 stops        ⚙ Filters②      ⇅       │
│ Sorted by Recommended            [Map│List]  │
├──────────────────────────────────────────────┤
│ … restaurant cards …                         │
└──────────────────────────────────────────────┘
```

### Search

Debounced at 350 ms. One character is treated as no search rather than as an
error — a customer mid-keystroke should not be shown a validation message
between the first letter and the second. A clear button appears only when there
is something to clear.

While a search runs, the previous results stay on screen under a 2 dp progress
bar. A list that empties on every keystroke cannot be read while typing.

### Filters

A bottom sheet that edits a **draft**. Nothing is applied until *Show results*;
dismissing discards. Applying each checkbox as it was ticked would send a
request per tap and re-sort the list under the customer's finger.

Applied filters become chips above the results, each removing its own value. The
filter button carries a badge with the count, and announces it — "Filter these
stops, 2 filters".

### Sort

A sheet listing the orders the *server* says this route can support. "Highest
rated" appears, disabled, with the server's own reason under it, because a
missing row reads as a lost feature. The current order is named in text under
the count, so a customer never has to open the sheet to find out what they are
looking at.

### The three empty screens

| State | Words | Button |
| --- | --- | --- |
| Nothing on this road | "No stops on this route yet" | Back to journey |
| Filters hid everything | "No stops match your filters" — and how many there are | Clear filters |
| Search matched nothing | "Nothing matched your search" — and the term | Clear search |

The search field and the chips stay on screen through all three. A screen that
swaps its whole body for an empty state takes away the only way out of it.

### Map and list

The same filtered set drives both, from one piece of state. Switching between
them re-fetches nothing; markers for filtered-out restaurants are gone because
they are not in the list either, and a selection is cleared whenever a new
result set arrives rather than surviving as a card for a restaurant no longer
shown.

---

## The restaurant page (Module 09)

Reached only from discovery, and it keeps the journey in the URL. The customer's
question is narrow — *is this the right place for me to stop?* — and everything
on the screen serves it. No favourite button, no share sheet, no reviews list.

### Down the page

| Element | Notes |
| --- | --- |
| Hero gallery | Swipeable with a counter; a branded placeholder where there are no photographs |
| Name | Wraps rather than truncating. A restaurant's own name is the last thing to cut |
| Cuisines · price | Price announced as a word, not as rupee symbols |
| Rating | A score with its review count, or **New** — never `0.0` |
| Availability chip | Icon and word as well as colour |
| Availability banner | Full width, for any state that blocks ordering |
| **On your route** card | Distance ahead, time ahead, detour, distance off route |
| About | Only where the operator wrote one |
| Facilities | Only where declared. Icon, label and semantics for each |
| Opening hours | Today, then the week on request, then the timezone |
| Location | City, the published phone if there is one, and a way back to the map |
| Sticky button | Pinned above the safe area |

### Loading

A skeleton in the shape of the answer, not a spinner — and where the customer
came from a card, that card's real name is drawn immediately while the rest
loads. The transition has something in it from the first frame.

### The three refusals

| State | Words | Action |
| --- | --- | --- |
| Withdrawn | "This restaurant is no longer available" | Back to restaurants |
| On another road | "Not on this journey" | Back to restaurants |
| Outage | "We couldn't load this restaurant" | Try again |

A withdrawn restaurant gets no "Try again": it will not come back because the
customer pressed a button, and offering the button implies it might.

### Offline

The page stays, with a banner carrying the real age of what is shown — "Last
updated 12 min ago. Opening times may have changed." Never a fabricated
timestamp, and never a claim that the open sign is live.

The one exception: a refresh that finds the restaurant *withdrawn* takes the
page away. Leaving it up would present a suspended business as trading.

---

## The menu (Module 10)

Reached from the restaurant page's sticky button, and only where the ordering
state permits browsing. The customer's question has narrowed again — *what can I
eat here, and what does it cost?* — and the screen answers only that. No cart,
no quantity stepper, no variant list.

### Down the screen

| Element | Notes |
| --- | --- |
| Ordering banner | Only when an order could not be placed. "Closed now — you can still browse" |
| Offline banner | Only when what is shown came from a failed refresh |
| Search field | Capped at 100 characters, so a customer cannot type into an error |
| Section selector | Pinned. Absent when there is only one section — one section is not a choice |
| Section heading | The operator's name and description, marked as a header for a screen reader |
| Item card | Name, price, up-to-two-line description, badges, thumbnail |
| Item sheet | The same, in full, plus the cooking time and the browse-only notice |

### The item card

Name and price first, because that is what the customer is scanning for.
Description clipped to two lines — the sheet has it in full. Badges only for
what the restaurant declared: no "diet unspecified" chip, no greyed placeholder,
because a customer who cannot eat egg needs an absent badge to mean *nobody
said*, not *we checked*.

The photograph is the dish's own or a monogram. **There is no stock-image
fallback anywhere in this app.** A generic curry standing in for an
unphotographed dish is a claim about what arrives in the box.

A sold-out dish stays on the menu, dimmed to 55% with a label over its
thumbnail. Removing it would be tidier and worse: a customer who came for one
thing deserves to learn the kitchen has run out.

### Prices

`₹249`, not `₹249.00` — a menu of trailing zeroes reads like a spreadsheet.
`₹349.50` keeps its paise, because `₹349` would be a lie. `₹0` for a free item,
because a blank invites the question. `₹12,999` grouped the way the customer's
locale groups. All of it from `intl` and the customer's own locale; the symbol
is never concatenated.

Announced to a screen reader as **"249 rupees"**, because some engines read
"₹249" as "rupee two four nine".

### The section selector leads and follows

Tapping a chip scrolls to that section; scrolling the list moves the highlight
and brings its chip into view. The second half is the one that matters — a
selector that only leads is a set of shortcuts, while one that follows tells a
customer halfway down a twenty-section menu where they are.

### Searching

Debounced 350 ms, so typing "paneer" is one request rather than six. Below two
characters nothing is sent. **The menu does not blank while a search is in
flight** — the previous results stay under a two-pixel progress bar, because a
list that empties and refills on every letter is unreadable.

### The two empty states, which are different problems

| State | Words | Action |
| --- | --- | --- |
| No menu published | "No menu yet — Highway Spice Kitchen hasn't published a menu here yet." | None. Not a failure |
| Search found nothing | "Nothing matched — No items on this menu match 'pizza'." | **Clear search** |

Conflating them would send a customer away from a restaurant that has a perfectly
good menu they mistyped a word into.

### The item sheet

Read-only, and fetched fresh rather than echoed from the list — a customer may
have had the menu open for ten minutes. The card's copy is drawn immediately
under a thin progress bar, then replaced.

Where Module 10 stops is visible here: a notice saying *"Ordering opens soon"*,
and **no button at all**. Not a disabled one — a greyed-out "Add to cart"
promises a cart that does not exist and invites a customer to keep tapping it.

An item withdrawn since the list was drawn loses the card's copy too, for the
same reason a withdrawn restaurant loses its page.

### Offline

The menu stays, with a banner. Prices from a failed refresh are still worth
showing — but never silently, because a price from an hour ago presented as
current is the kind of thing a customer discovers at the counter.

---

## Configuring a dish (Module 11)

Reached by tapping a dish on the menu. Module 10's read-only sheet is gone; this
replaced it.

### Down the screen

| Element | Notes |
| --- | --- |
| Hero | The dish's own photograph, or nothing. No stock imagery, ever |
| Name and base price | The price before any choices; the running total lives on the button |
| Description | The operator's words, in full. Never generated |
| Badges | Diet, spice, cooking time — each only where published |
| Sold-out / paused notice | Prominent, above the choices, so nobody configures something they cannot have |
| Size selector | Radios. Absent where the dish has no sizes |
| Modifier groups | One per question, each with its rule stated |
| Quantity stepper | −, the number, + |
| Special instructions | Optional, with a caveat and no promise |
| Sticky button | Pinned above the safe area, carrying the running total |

### Rules are stated, not discovered

"Required · Choose 1" and "Optional · Choose up to 2" sit **above** the options.
A customer should not have to be refused to learn what was being asked of them,
and a validation message is a poor place to explain a rule for the first time.

Required is a word and a colour, never a colour alone and never a bare asterisk.

### The button never goes dead without saying why

| State | Label | Enabled |
| --- | --- | --- |
| Everything answered | **Add to cart · ₹778** | yes |
| Something missing | **Choose required options** | **yes** |
| Submitting | Adding… | no |
| Dish sold out | Sold out | no |
| Kitchen paused | Not taking orders right now | no |

The second row is the interesting one. A disabled button with no explanation is
a customer wondering what they did wrong; this one takes the tap, scrolls to the
first unanswered question and marks it.

Nothing is marked until they have tried. A screen that opens covered in red is
telling somebody off for not having started.

### The price moves as they choose, and is a preview

It updates on every tap, because a total that lags feels broken. It is replaced
by the server's figure on every add. The two disagree only when the menu changed
underneath the customer — and then both are shown:

> **The price changed.** This item was ₹249 and is now ₹269. Review the new
> price before adding.
>
> [ Add at ₹269 ] [ Not now ]

"The price changed" without saying to what is not information.

### At the ceiling, options disable rather than swap

A customer who taps a third extra when two are allowed keeps their two, sees the
others go quiet, and reads *"You can choose up to 2."* Silently dropping their
first choice would leave them to work out which one went.

### Unavailable is shown, not hidden

A sold-out size stays on the list, dimmed, with **Unavailable** where its price
would be. Hiding it leaves somebody who came for the family portion wondering
whether they misremembered the menu.

### The note is a request, not an instruction

> Special instructions · Optional
> *Add a note for the restaurant*
> The kitchen will see this and will do what they can.

Never "the restaurant will follow this", and never presented as a way to declare
an allergy. The counter appears only in the last forty characters — a counter
that is always on turns a note into a test.

### Adding

A quiet snackbar — *"Added to cart · 2 items in your cart"* — and the customer
stays where they are. No full-screen celebration; they are mid-task and may want
a second dish. The **View cart** action says the cart screen arrives in the next
release rather than opening a half-built one.

### Failures, each with the move that fixes it

| State | Words | Action |
| --- | --- | --- |
| Offline | "You're offline. Connect to the internet to add this to your cart. Your choices are kept." | Try again |
| Sold out mid-choice | "Just sold out — the kitchen has run out while you were choosing." | none |
| Kitchen paused | "Not taking orders — you can still browse." | none |
| Cart holds another restaurant | "Your cart has items from Highway Spice Kitchen." | none yet — Module 12 |
| Price rose | Both figures, and a choice | Add at the new price / Not now |

A network failure keeps every selection. The customer does not customize their
dinner again because our request failed.

### Accessibility

Every control is named as a sentence rather than as a control plus a label:

- *"Regular. 249 rupees. Selected"*
- *"Extra Cheese. Adds 40 rupees. Not selected"*
- *"Mild. No extra charge. Not selected"* — a screen reader cannot see that the
  trailing column is empty, so "free" is said out loud
- *"Quantity, 2"* — a bare "2" between two buttons counts nothing
- *"Add to cart · ₹778"* on the button

The quantity buttons are named even when **disabled**: a tooltip becomes an
accessible name only on an enabled control, so at quantity one the minus button
would otherwise be an anonymous disabled thing at exactly the moment a
screen-reader user needs to know what it is. See M11-B04.

---

## The cart (Module 12)

Three jobs, in the order a customer does them: check that what is here is what
they meant, correct it if not, and understand what they will pay.

### Nothing on this screen is calculated on the device

Every price, every charge and the total came from the server in the response to
the request that changed them. An edit replaces the whole view rather than
patching a figure.

A client that adjusted its own subtotal after a quantity change would be right
most days and wrong on the day a price moved underneath it — and this is the
screen where a customer decides what to spend. The one arithmetic the app does
is none.

### Edits are not optimistic

A stepper that moves before the server has agreed shows a quantity the cart may
not have. So the line being changed disables its own controls and shows a
spinner in place of its number; **the rest of the cart stays usable**. Blocking
the whole screen to change one quantity makes a fast connection feel slow and a
slow one feel broken.

Every unsafe request carries an `Idempotency-Key`, kept across a retry. A
connection that dies after the server acted must not remove a second line when
the customer tries again.

### The minus stops at one

At a quantity of one the minus is disabled and the **Remove** control beside it
is what the customer uses. Turning the last decrement into a deletion is how a
mis-tap loses a selection, and it leaves the app unable to tell a mistake from
an intention. The client does not even send the zero — not as enforcement, which
is the server's job, but as a refusal to ask a question whose only honest answer
is no.

### Emptying is confirmed, and says what will happen

"Empty your cart? Everything in it will be removed. This cannot be undone." —
with **Keep it** first and unstyled, and the destructive action the one that has
to be reached for. A cart emptied by one stray tap in a moving car is a cart
rebuilt from memory.

### The order summary

Subtotal, then each charge that is not nothing, then the total. Tabular figures
so the column lines up at the decimal point and can be added up by eye.

A charge of zero gets **no row**: "Service fee ₹0.00" is a line somebody has to
read to discover it is nothing, and a summary is easier to check the fewer
nothings it contains. The total is always shown, zero or not.

### What revalidation puts on the screen

The cart screen opens with `GET /cart/revalidate` — one request, because the
screen needs the cart and the verdict the same instant and fetching them
separately would show a total from one moment beside a judgement from another.

One banner at most, and the order is deliberate:

| Rank | Notice | Tone |
| --- | --- | --- |
| 1 | The kitchen has stopped taking orders | blocking |
| 2 | Some items need your attention | blocking |
| 3 | Prices have changed | advisory |

A customer who cannot order here does not need to be told the paneer went up by
seventy rupees first.

Per line: a price change shows **both figures** — "Was ₹329 · Now ₹399" — and a
missing dish shows the server's own message with the name struck through.
Blocking and advisory findings differ in icon, wording and colour, so the
distinction survives a monochrome screen and a customer who cannot tell amber
from red.

**A blocked line is never removed for the customer.** It stays in the cart, says
what is wrong, and waits for them to deal with it. An app that tidied it away
would be deciding on their behalf what they no longer want.

`blocks_ordering` is read from the server's own per-line flag rather than
derived from the finding code, so a finding added to the API after a build has
shipped still blocks that build correctly instead of being waved through as
unrecognised.

### An empty cart is not a failure

A customer who has added nothing has a cart with nothing in it, and so does one
who has just emptied theirs — the server closes an emptied cart and reports it
as no cart at all. Both land on the same empty state, with the one action that
fills it. `CART_NOT_FOUND` from revalidation is treated the same way, because to
the customer it means the same thing.
