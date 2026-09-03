# 16 — Mobile navigation architecture

## State management: Riverpod

Module 01 did not name a state-management approach, so Module 02 chose one and it
is **Riverpod 3** (`flutter_riverpod`). Do not introduce a second.

Riverpod over Bloc because this app's state is mostly *derived, cached, async reads* rather than long
event streams — and, decisively, because overriding a provider is the cleanest way to swap a fixture
repository for a real one. That override is what keeps demo data out of production builds.

### Two Riverpod 3 specifics worth knowing

**`StateProvider` no longer exists.** Mutable state is a `Notifier` + `NotifierProvider`.

**Failed providers retry automatically, and we switch that off.** Riverpod 3 re-runs a failed
provider on its own with exponential backoff. For this app that is wrong: a traveller in a signal
dead zone would have the app quietly re-requesting in a loop — spending battery and mobile data on
requests that cannot succeed — while the *Try again* button in front of them does nothing they can
observe. `homeDashboardProvider` passes `retry: (_, __) => null`; recovery is an explicit user
action.

## Routing: go_router with `StatefulShellRoute`

```
StatefulShellRoute.indexedStack          ← CustomerShell (offline banner + bottom bar)
├── branch 0  /                          → HomeScreen
├── branch 1  /trips                     → TripsScreen
├── branch 2  /orders                    → OrdersScreen
├── branch 3  /notifications             → NotificationsScreen
└── branch 4  /profile                   → ProfileScreen

/coming-soon?feature=…&module=…          ← pushed OVER the shell, covering the bar
```

`StatefulShellRoute.indexedStack` is the specific choice that makes tabs behave natively: **each
branch keeps its own `Navigator` and its own state.** Scroll Orders halfway, visit Profile, come
back — you are where you left off. A plain `IndexedStack` of screens would preserve widget state but
give every tab one shared navigation history, which breaks Android's back button.

Later modules attach nested routes beneath the branch they belong to (`/orders/:reference` under the
Orders branch) and inherit its back stack for free.

### Behaviours this buys, all covered by tests

| Behaviour | How |
| --- | --- |
| Tab state survives switching | Per-branch `Navigator` |
| No re-fetch on return | Branch state + a 2-minute `keepAlive` on the dashboard |
| Android back from a non-home tab returns to Home | `PopScope` with `canPop: currentIndex == 0` |
| Re-tapping the current tab pops it to its root | `goBranch(index, initialLocation: index == currentIndex)` |
| Double-tap is harmless | The same call is idempotent |
| Rapid switching does not corrupt the index | Asserted over 60 un-settled taps |

## The five destinations

| # | Route | Label | Icon (rest → selected) |
| --: | --- | --- | --- |
| 0 | `/` | Home | `home_outlined` → `home_rounded` |
| 1 | `/trips` | Trips | `route_outlined` → `route_rounded` |
| 2 | `/orders` | Orders | `receipt_long_outlined` → `receipt_long_rounded` |
| 3 | `/notifications` | Alerts | `notifications_outlined` → `notifications_rounded` |
| 4 | `/profile` | Profile | `person_outline_rounded` → `person_rounded` |

Five is the practical ceiling for a bottom bar; beyond that the targets get too narrow for a thumb.
The label is "Alerts" rather than "Notifications" purely because the longer word wraps at 320dp.

**The selected state changes shape as well as colour** — outlined to filled — so the current tab is
identifiable without relying on hue.

## Unbuilt features

Tapping a future feature must never show a dead button and must never do nothing silently.

- **Development:** it routes to `/coming-soon`, which names the feature and the module delivering it.
- **Production:** the feature is *hidden* by its flag; the route is unreachable, and degrades to a
  neutral message if it is somehow reached. No module numbers ever reach a customer.

## Feature flags

`FeatureFlags` in `core/config`. Coarse by design — one per significant capability, owned by the
module that will deliver it, all `false` today: `tripPlannerEnabled`, `tripsEnabled`,
`ordersEnabled`, `notificationsEnabled`, `savedPlacesEnabled`, `supportEnabled`,
`profileEditingEnabled`.

## Fixture isolation

```
AppEnvironment.current        ← compile-time constant from --dart-define=FOTG_ENV
        │
        ├── allowsFixtures ── true  → FixtureHomeRepository  (development personas)
        └── allowsFixtures ── false → UnconfiguredHomeRepository (no trip, no order)
```

`AppEnvironment.current` is `const`, so the compiler can prove the fixture branch is dead in a
release build and tree-shake it: development personas are not merely unreachable in production, they
are **not in the binary**. `FixtureHomeRepository`'s constructor also asserts the environment allows
fixtures, so a mistake fails loudly in debug.

There is no `if (development)` scattered through widgets. The question is answered once, by which
repository is injected.

## Analytics

Boundary only — no vendor SDK, because embedding a tracking library in an app with no consent flow
is not a decision to make by accident.

Convention: `object_verb`, lower snake case. `home_viewed`, `plan_journey_tapped`,
`orders_tab_opened`, `profile_tab_opened`, `quick_action_tapped`, `unbuilt_feature_opened`.

**Never in a payload:** a name, email, phone number, precise location, address, payment detail or an
order's contents. Events carry what was interacted with, never who the person is.

## Localization

`AppStrings` + `AppStringsDelegate`. Every user-visible string lives there; widgets read
`AppStrings.of(context)`. A hand-rolled class rather than `gen-l10n`, because with one language it
gives the same separation without an ARB pipeline and a code-generation step in CI. When a second
language is commissioned, this class becomes the interface `gen-l10n` implements.

## Currency

`ActiveOrderSummary` carries `totalMinorUnits` (an `int`) and `currencyCode` (default `INR`). Money
is never a `double`, and no widget assumes a symbol.
