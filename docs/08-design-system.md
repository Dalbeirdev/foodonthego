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
