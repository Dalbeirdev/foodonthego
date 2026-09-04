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
    │   ├── RouteSummaryCard       ← only when a journey exists
    │   ├── ActiveOrderCard        ← only when an order exists
    │   ├── HowItWorks             ← only when neither exists
    │   └── QuickActions
    ├── TripsScreen                EmptyStateView
    ├── OrdersScreen               EmptyStateView
    ├── NotificationsScreen        EmptyStateView
    └── ProfileScreen              header + three grouped sections
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

## Development harness

A floating control (development builds only) that switches persona, forces offline, and forces a
failure — so the loading, error and offline states can be *inspected in a running app*, not merely
asserted in tests. It renders `child` untouched when the environment forbids fixtures.
