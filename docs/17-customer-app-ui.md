# 17 — Customer app UI

## Screen hierarchy

```
FoodOnTheGoApp                     theme · localization · router · text-scale clamp
└── CustomerShell                  offline banner · bottom navigation · Android back
    ├── HomeScreen                 loading | error | data
    │   ├── GreetingHeader
    │   ├── JourneyPlannerCard     ← the primary action
    │   ├── RouteSummaryCard       ← only when a journey exists
    │   ├── ActiveOrderCard        ← only when an order exists
    │   ├── HowItWorks             ← only when neither exists
    │   └── QuickActions
    ├── TripsScreen                EmptyStateView
    ├── OrdersScreen               EmptyStateView
    ├── NotificationsScreen        EmptyStateView
    └── ProfileScreen              header + three grouped sections
ComingSoonScreen                   pushed over the shell
```

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

## Development harness

A floating control (development builds only) that switches persona, forces offline, and forces a
failure — so the loading, error and offline states can be *inspected in a running app*, not merely
asserted in tests. It renders `child` untouched when the environment forbids fixtures.
