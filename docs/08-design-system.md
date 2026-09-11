# 08 — Design system

Two implementations of one system:

| | File |
| --- | --- |
| Web | `web/packages/ui/src/tokens.css` |
| Flutter | `mobile/lib/core/theme/tokens.dart` |

They cannot share a file, so **this document is the contract**. A change to one is a change to both.

## Rule

Components reference tokens. A hex code, a raw pixel value or a bare duration inside a component is
a bug. Names are semantic (`--color-danger`), never literal (`--color-red`).

## Colour

**Primary — amber/saffron.** Food, and highway signage. Deliberately not the red every delivery
competitor uses.

**Secondary — deep teal.** The journey half of the product: routes, maps, ETA. Keeping "the road"
and "the food" in different hues means a screen showing both is readable at a glance.

| Token | Light | Dark |
| --- | --- | --- |
| `primary-600` | `#EF6008` | — |
| `primary-700` | `#C64709` | — |
| `primary-400` | — | `#FF9A38` |
| `secondary-600` | `#0D9488` | `#14B8A6` |
| `background` | `#FAFAF9` | `#0C0A09` |
| `surface` | `#FFFFFF` | `#1C1917` |
| `text-primary` | `#1C1917` | `#FAFAF9` |
| `text-secondary` | `#57534E` | `#A8A29E` |

### `--color-primary-interactive` exists for a reason

White text on `primary-600` measures **3.31:1** — below the WCAG AA floor of 4.5:1 for normal text.
`primary-700` is **4.88:1**.

So `--color-primary-interactive` (`primary-700` in light, `primary-500` in dark) is the shade used
**wherever text sits on the brand colour** — filled buttons, the brand mark, the skip link.
`primary-600` remains correct for rails, dots and decoration carrying no text.

This was a real defect in the first cut of the palette, caught by a contrast test in
`mobile/test/tokens_test.dart` which computes the WCAG ratio and fails if it regresses.

## Typography

Body text floor is **16sp/16px**, prose floor **15**. This is read at arm's length on a phone mount,
often in motion — the 12–13px that passes on a desktop dashboard is not legible there. 13 is
permitted for metadata (timestamps, counts) only.

| Step | Size |
| --- | --- |
| Display | 40 / 34 |
| H1 | 32 / 28 |
| H2 | 24 |
| H3 | 20 |
| H4 | 18 |
| Body large | 18 / 17 |
| Body | 16 |
| Body small | 15 |
| Label | 14 |
| Caption | 13 — metadata only |

### Font family

Flutter uses the **platform font** (`fontFamily = null`): Roboto on Android, San Francisco on iOS.

Naming `'Roboto'` explicitly was a real bug: it is not a system font on iOS, so iOS fell back
silently, and on Flutter web the engine tried to fetch it from a CDN. Bundling a brand face is a
deliberate change here **plus** an asset in `pubspec.yaml` — never an unbundled name.

Component themes derive their text styles from the themed `TextTheme` rather than constructing bare
`TextStyle`s, so a bundled family would apply to app bars and chips too. Constructing one fresh
silently drops the family.

## Spacing

4px base: `4 · 8 · 12 · 16 · 20 · 24 · 32 · 40 · 48 · 64`. Anything off the grid is an accident.

## Radius

`xs 4 · sm 6 · md 10 · lg 14 · xl 20 · full 9999`. Cards `lg`, controls `md`, pills/sheets `full`/`xl`.

## Elevation

Four steps only — `xs · sm · md · lg`. More and nothing reads as raised.

## Motion

| Token | Duration |
| --- | --- |
| instant | 80ms |
| fast | 140ms |
| normal | 220ms |
| slow | 320ms |

Standard easing `cubic-bezier(0.2, 0, 0, 1)`.

Short on purpose: in a moving vehicle a long transition reads as lag, not polish.

**`prefers-reduced-motion` is honoured at the token level** on web (durations become 0) and through
`FotgMotion.respectingReducedMotion` in Flutter. This is an accessibility control — vestibular
disorders make large transitions genuinely unpleasant.

## Icons

**One family per platform, never mixed.**

- Web: **Lucide** (`lucide-react`), stroke width 1.8–1.9, sizes 16/19/22/26.
- Flutter: **Material Symbols** (built in), outlined for rest, rounded-filled for selected.

The selected state changes **shape as well as colour**, so the current tab is distinguishable without
relying on hue.

No emoji in product UI, no Font Awesome, no one-off SVGs.

## Touch targets

**44px minimum on web, 48dp on mobile.** WCAG 2.2 asks for 44; mobile uses 48 because this app is
tapped one-handed by someone about to drive. Verified by an automated sweep across eight viewport
widths, and by a unit test on the mobile token.

## Z-index

A declared scale so no component invents `z-index: 99999`:
`base 0 · sticky 100 · sidebar 200 · topbar 300 · overlay 400 · modal 500 · popover 600 · toast 700`.

## Responsive breakpoints (web)

| Range | Behaviour |
| --- | --- |
| ≥1024px | Sidebar in the grid; collapsible to a 72px rail |
| 768–1023px | Sidebar becomes an overlay drawer; account name hidden |
| <900px | API health pill collapses to a dot |
| <768px | Search hidden; padding reduced |
| <480px | Breadcrumbs reduced to the current page |

Every flex child of the topbar sets `min-width: 0`. Without it one longer string —
"API unreachable" instead of "API local" — pushes the bar past the viewport. That was a real defect:
the layout only fitted while the API was up.

## Order status visual language (Module 02)

Six states, each varying **three** things — colour, icon and label — because colour alone is not a
usable signal:

| State | Icon | Tone |
| --- | --- | --- |
| Placed | `receipt_long_outlined` | Info blue |
| Accepted | `check_circle_outline` | Teal (secondary) |
| Cooking | `local_fire_department_outlined` | Amber (warning) |
| Ready for pickup | `takeout_dining_outlined` | Green (success) |
| Picked up | `task_alt_outlined` | Neutral |
| Cancelled | `cancel_outlined` | Red (error) |

A cancelled order renders **no** progress track: drawing the remaining steps as "still to come" for
an order that will never reach them would be a lie.

## Button sizing — a trap worth naming

Use `Size(0, height)` for a minimum size, never `Size.fromHeight(height)`. The latter sets width to
`double.infinity`, which forces every button to fill its parent and silently defeats any `expand`
parameter. Width is the caller's decision; only the height floor belongs to the theme.

## Map surfaces (Module 06)

A map is a picture, so everything that matters must also exist as words.

- **Never colour alone.** The selected route is distinguished from alternatives by
  stroke width and z-order as well as colour: an 8dp line on top, 5dp lines
  beneath. On a greyscale display the selected route is still obviously the
  selected one.
- **A polyline is not a touch target.** Every route tappable on the map is also a
  row in the list beneath it, at full width and full height. Tapping a 5dp line
  is a fine shortcut and a poor only-way.
- **A banner floats over tiles, never over words.** The offline and
  development-provider notices are overlaid on a real map, where they cover
  nothing that cannot be panned back into view. In the map-unavailable state,
  where the content *is* the words, they take their own place in the layout
  instead.
- **A control that cannot act is not shown.** The recentre button appears only
  where there is a map to recentre. An inert control reads as a broken app rather
  than as an absent feature.
- **The map-unavailable state is a designed state**, not a fallback: the icon, a
  one-line explanation, both place names, and the full summary below it — never a
  blank grey rectangle, and never a screen that has lost the journey.

## Discovery surfaces (Module 07)

A card that recommends a stop has to survive being read aloud, being read at 1.6x
text, and being read on a phone 320 logical pixels wide.

- **The hierarchy is the argument.** Distance ahead and detour come first and
  largest, because those are the two facts that decide whether somebody stops
  here rather than at the next one. The name is the heading; cuisine, price and
  rating are supporting detail.
- **Every part is conditional.** No rating, no rating line. No declared price, no
  price. No detour the server could establish, an explicit "Detour unknown" — not
  a zero, which would be a claim that stopping is free.
- **One string per fact, used by both the eye and the ear.** A stop that needs
  backtracking shows "Behind you" *and* announces "Behind you"; computing the two
  separately is how a screen reader came to be told "0 m ahead" about a
  restaurant the screen labelled "Behind you".
- **A symbol is never the only carrier.** "₹₹" is a visual convention that a
  screen reader announces as nothing useful and a font without the glyph draws as
  two empty boxes, so the price level is also spoken as a word — "Moderate".
  Availability is likewise always a word, never only a colour.
- **Facts wrap, they do not overflow.** The route facts sit in a `Wrap`, and each
  one is itself flexible: at 320dp a single fact — "1.8 km off your route" — is
  wider than the card, and measured 69 pixels past its edge before that was
  fixed.
- **A control too wide for the screen loses its labels, not its meaning.** The
  map/list toggle drops to icons below 300dp and keeps a tooltip on each segment,
  which is also its accessible name.

## Accessibility baseline

- Visible `:focus-visible` ring on every interactive element
- Skip link to main content
- The navigation landmark is labelled on the `<nav>`, not the `<aside>` (`<aside>` is
  `complementary`, so labelling it does not name the navigation)
- Disabled controls keep a legible label — Material's default disabled opacity rendered button text
  effectively invisible, which is fixed in the Flutter theme
- Body contrast ≥ 4.5:1 in both themes, asserted by test

---

## Filter surfaces (Module 08)

### The controls, in order down the screen

```
Search field                     full width, rounded, clear button when non-empty
Active filter chips              horizontally scrollable · "Clear all" pinned right
Result count      Filters (2)  ⇅ sort
Sorted by …                              Map | List
```

Four rows sounds like a lot; measured at 320 dp it is 168 dp, leaving the list
the majority of a small screen. The count and the sort share a row with their
own controls rather than each taking one.

### Chips

`InputChip` with a delete affordance for an applied filter; each removes **its
own value**, not its group. Removing "North Indian" from "North Indian, Cafe"
leaves "Cafe".

"Clear all" is a `TextButton` pinned outside the scrolling row, not the last
chip in it. Three filters already push a trailing chip off the side of a 390 dp
phone, and the customer who most needs that control is the one whose filters
left them with an empty screen.

### The filter sheet

Drag handle, title, "Clear all" in the header when anything is on, scrollable
groups, and an apply button pinned at the bottom inside the safe area. Capped at
85% of screen height so the list stays visible behind it.

Groups say what they mean: **Any of these** under cuisine and price, **All of
these** under facilities. A customer who assumes the wrong one is sent to a
restaurant without the thing they stopped for.

Each option carries its count for this route — `North Indian (2)` — and options
this route cannot satisfy are simply absent.

### Controls that are not offered

A rating control is not rendered at all while nothing on the route is rated —
not greyed out, not showing zero stars. A disabled control implies the data
exists and the restaurants fall short of it.

A sort that cannot work yet is the opposite case: it stays in the sheet,
disabled, with the server's own reason underneath. A missing row reads as a lost
feature; a greyed-out row with no explanation reads as a bug. The difference is
that the customer went looking for the sort and did not go looking for the
rating filter.

### Accessibility

- The filter button's accessible name carries the count — "Filter these stops,
  2 filters" — not a bare "Filters" over a filtered list. A `Tooltip` around a
  labelled button does **not** name it: it lands in the semantics tree as a
  separate node. Found in the live tree; see M08-B02.
- Each chip's delete button has its own name ("Remove this filter").
- The result count is a live region, so applying a filter is announced.
- Price is announced in words ("Moderate"), never as rupee symbols alone.
- The refining indicator is a 2 dp bar with a live-region label, not a spinner
  over the list — the results underneath are still the last honest answer.

---

## The restaurant page (Module 09)

```
┌──────────────────────────────────────┐
│ ←  Highway Spice Kitchen             │
├──────────────────────────────────────┤
│                                      │
│          [ hero gallery ]      1 / 3 │
│                                      │
│ Highway Spice Kitchen                │
│ North Indian · Vegetarian · ₹₹       │
│ ★ 4.3 (214)      or      [ New ]     │
│ ✓ Open · Accepting orders            │
│ ┌──────────────────────────────────┐ │
│ │ On your route                    │ │
│ │ 68 km ahead                      │ │
│ │ About 1 hr ahead                 │ │
│ │ 4 min detour                     │ │
│ │ 900 m off your route             │ │
│ └──────────────────────────────────┘ │
│ About · Facilities · Opening hours   │
│ Location                             │
├──────────────────────────────────────┤
│          [   View menu   ]           │
└──────────────────────────────────────┘
```

### The route card comes before the description

A generic restaurant page leads with the business. This one leads with the
journey, because the customer is deciding whether to *stop*, not whether to
visit. Distance ahead first, then detour: that is the order a driver decides in.

### Sections that are not there

Every section omits itself when the restaurant declared nothing — no
description, no facilities, no price in the header, no gallery. An empty card
with a heading over blank space reads as a bug, and inventing content to fill it
would be worse. `[TEST] Bare Bones Stop` exists so all four omissions are a
state somebody can look at.

### Availability gets a chip *and* a banner

A customer who scrolled past a small amber pill to the button has been failed by
the screen, so any state that blocks ordering also gets a full-width band. The
chip carries an icon and a word as well as a colour: somebody who cannot
distinguish the green from the amber must not read "open" off a chip that says
paused.

### The button's state is the ordering state

| State | Button |
| --- | --- |
| Open, accepting | **View menu**, live |
| Open, paused | Browse the menu |
| Closed | Browse the menu |
| Permanently closed | Unavailable, disabled |
| Unknown hours | Unavailable, disabled |

Pinned above the safe area rather than at the end of the scroll, so large text
cannot push it off the bottom.

### The gallery

No photographs → a branded placeholder with the app's own storefront mark.
Never a broken image icon, and never a stock photograph of somebody else's
dining room: a picture under a business's name is a claim about premises nobody
has seen. One photograph → no counter and no swipe, because "1 / 1" promises
something that is not there. A photograph that fails to load → the same branded
stand-in.

### Accessibility

- The **View** button on a discovery card is named with its restaurant. A list
  of twelve buttons all called "View" is a list a screen-reader user cannot
  navigate — and before Module 09 that button had no node at all, so the page
  could not be reached without sight. See M09-B01.
- Each day of the week is its own semantics node ("Tuesday, 11:00 AM – 3:00 PM,
  6:00 PM – 11:00 PM"), so the schedule can be stepped through a day at a time
  rather than heard as one blob.
- A photograph is announced with the operator's caption where there is one, and
  with its position otherwise. Never an invented description of the picture.
- Price is announced as a word. "₹₹" is a visual convention.
- An overnight window says "(overnight)" — "6:00 PM – 2:00 AM" read quickly
  looks like a typo.

---

## Module 10 — a badge that is absent means nobody said

The menu introduces three small components, and the interesting rule is shared
by all of them: **a badge is drawn only where the restaurant published the field
behind it.** There is no "unspecified" chip and no greyed-out placeholder,
because a customer who cannot eat egg needs the absence of a badge to mean
*nobody said*, not *we checked and it's fine*.

| Component | Tokens | Notes |
| --- | --- | --- |
| `MenuItemBadges` | `successSurface`/`success` for veg and vegan, `errorSurface`/`error` for non-veg, `warningSurface`/`warning` for spice, `neutral100`/`neutral600` for cooking time | Pill radius, `labelSmall`, weight 600. `compact` drops the cooking time for the list card |
| `MenuItemCard` | `FotgRadius.card` ink, 72 dp thumbnail at `FotgRadius.control` | Sold out dims the whole row to 55% opacity and overlays `neutral950` at 45% on the thumbnail |
| `MenuCategorySelector` | `ChoiceChip`, 52 dp row | Horizontal, lazy, and scrolls the active chip into view when the highlight moves |

### The veg/non-veg mark

The square-in-a-square mark Indian menus use is drawn beside the word, never
instead of it — colour alone is not information, and the mark is meaningless to
somebody who has not seen an Indian menu. It is wrapped in `ExcludeSemantics`,
so a screen reader hears "Dietary: Veg" once rather than an anonymous image
between two words.

### Dimming, not recolouring

A sold-out row is dimmed with `Opacity`, not repainted from a grey palette. A
greyed palette would flatten the badge colours to the point where "Non-veg" and
"Veg" stop being distinguishable — which is exactly the information a customer
still needs while deciding whether to wait for the kitchen to restock.

### Money is never a string in a widget

`Money.format()` is the only place a price becomes text. No widget concatenates
a symbol, and no design token holds one — the symbol comes from the customer's
locale through `intl`. See [02-architecture.md](02-architecture.md).

---

## Module 11 — a control that is disabled still has to say what it is

Three components, and one rule that runs through them: **the whole row is one
semantics node with a sentence of its own.**

| Component | Notes |
| --- | --- |
| `OptionRow` | A mark, a name, an optional subtitle, a trailing price. Hand-drawn rather than `RadioListTile`/`CheckboxListTile` |
| `QuantityStepper` | 48 dp targets; the number is its own live region |
| `SpecialInstructionsField` | Three lines, a caveat, a counter that appears only near the limit |
| `StickyAddBar` | Pinned above the safe area, carrying the running total |

### Why the list tiles were replaced

Material's `RadioListTile` and `CheckboxListTile` announce the control and the
label as **separate stops**. On a screen with twenty options that is forty things
to swipe past, and none of them says the price. `OptionRow` produces one node
reading *"Extra Cheese. Adds 40 rupees. Not selected"*.

### Wrap, not Row, wherever two labels share a line

Three overflows at 320 dp were found and fixed in this module — a group heading
beside its rule chip, a field label beside "Optional", and a caveat beside a
counter. All three were `Row`s that fitted at 390 dp.

**The rule taken from it:** when a line holds two independent pieces of text and
either can grow (a long group name, a long rule, large text), it is a `Wrap`.
A `Row` is for things that are genuinely fixed beside each other.

### A disabled control is still named

`IconButton(tooltip:)` becomes an accessible name only when the button is
**enabled**. At quantity one the minus button is disabled — which is exactly the
moment a screen-reader user needs to hear what it is and why nothing happened.
Every step button carries an explicit `Semantics(label:)` for that reason.

The general form: **if a control can be disabled, name it explicitly rather than
relying on a tooltip.**

### Required is a word

The rule chip beside a group name reads "Required" or "Optional" in the primary
or neutral surface. Colour alone is not information, and an asterisk is a
convention rather than a sentence.

## Status is never colour alone (Module 17)

The order timeline is the first component whose whole job is conveying state, so
it is where the rule gets written down.

Each step carries **three** signals: an icon whose shape differs (a tick, a
filled ring, an empty ring, a cross), a text label, and a semantics sentence
saying what state it is in. Colour is the least of them.

A customer who cannot distinguish green from grey still has to be able to tell
whether their food is ready. So the current step is marked by **font weight**,
which survives greyscale and colour blindness, rather than by a colour the
design system happens to like.

Semantic colour roles are used where colour does appear — `primary` for
progress, `error` for an exception, `outline` for something not yet reached —
and no component in this module holds a literal colour value.

### The timeline's screen-reader form

One sentence per step, in the order a person would say it:

> "Restaurant accepted your order. Completed. at 4:03 PM."
> "Your food is being prepared. Current status. at 4:05 PM."
> "Ready for pickup. Not started."

`excludeSemantics: true` on the wrapper, because the default merged tree
announces an icon name and a bare number, which tells somebody nothing about
their order.
