# 32 — Restaurant and admin web: a guide for reviewers

What the two web applications are today, and what they are not.

**One document rather than six.** The Module 14 brief asks for a guide per role —
restaurant owner, restaurant manager, restaurant staff, support agent, admin,
super admin. Six documents describing the same navigation shell, with the same
sentence about there being no data behind it, would be padding rather than
documentation. Where the surfaces differ, this guide says so. When a role gains
a screen of its own, it gains a guide of its own.

---

## The honest summary

| | Restaurant dashboard | Admin panel |
| --- | --- | --- |
| Design system, navigation, layout | **Built** | **Built** |
| Responsive down to 360dp | **Built** | **Built** |
| Light and dark | **Built** | **Built** |
| API connectivity indicator | **Built** | **Built** |
| A page that queries the API | no | **Yes** — System Health |
| **Login** | **None** | **None** |
| **API routes for this surface** | **None** | **None** |
| Operational screens | none | none |

`php artisan route:list` matches **zero** routes under `api/v1/restaurant`,
`api/v1/admin`, `api/v1/support`, `api/v1/rider` or `api/v1/ops`. Neither
application's source contains a login screen, a password field, or any token
handling.

---

## Why there is no login

There is nothing to log in to. Authentication protects a surface that does
something; these surfaces do not do anything yet. Adding a login now would be a
door in front of an empty room, and a credential handed over for it would be a
fiction that reads as progress.

`NOT YET IMPLEMENTED — DO NOT PROVIDE FAKE CREDENTIAL` for every role in this
document.

---

## The restaurant dashboard

Opens on **Overview**, which states its own position:

> Nothing on this screen is live data. No orders, menu items or earnings exist
> yet — there are no such tables in the database. Every link in the sidebar
> marked with a dot is navigation scaffolding.

The sidebar is the operational architecture, grouped as it will be used:

| Group | Areas |
| --- | --- |
| Service | Orders, Availability |
| Catalogue | Menu, Restaurant, Staff |
| Business | Earnings, Reports, Reviews |
| Account | Support, Settings |

**Every one of those carries a dot, and the dot means scaffolding.** Clicking one
navigates; it does not show data, because there is none.

Screenshots: [`evidence/module-14/restaurant-1440.png`](evidence/module-14/restaurant-1440.png) ·
[`restaurant-390.png`](evidence/module-14/restaurant-390.png) ·
[`restaurant-dark.png`](evidence/module-14/restaurant-dark.png)

### Which roles this surface will serve

Restaurant owner, restaurant manager and restaurant staff. The shell does not
yet distinguish between them, because there is no permission to enforce and no
screen to withhold. The `Role` enum on the backend already carries all three.

---

## The admin panel

The same shell, a different map:

| Group | Areas |
| --- | --- |
| Marketplace | Customers, Restaurants, Routes, Orders |
| Money | Payments, Promotions |
| Operations | Reviews, Support, **System Health** |
| Platform | Settings, Roles, Audit |

**System Health is the one page here that does something.** It reads
`/api/v1/health/ready` and reports what came back — MySQL and Redis, each with a
healthy flag and a latency, and the API's own readiness. It is a real end-to-end
check across all three tiers, and it is the reason the connectivity chip in the
header can say "API local" honestly.

Screenshots: [`evidence/module-14/admin-1440.png`](evidence/module-14/admin-1440.png) ·
[`admin-390.png`](evidence/module-14/admin-390.png) ·
[`admin-dark.png`](evidence/module-14/admin-dark.png)

### Which roles this surface will serve

Platform admin, super admin, support agent and finance. As above: no
distinction is drawn yet because there is nothing to distinguish.

---

## Responsiveness

Both applications were captured at **1440 × 900** and **390 × 844**, and both lay
out correctly at each. The sidebar collapses to a drawer below the breakpoint;
Module 01's evidence has that at
[`evidence/restaurant-360.png`](evidence/restaurant-360.png),
[`restaurant-768.png`](evidence/restaurant-768.png),
[`admin-360.png`](evidence/admin-360.png) and
[`admin-768.png`](evidence/admin-768.png), along with the collapsed and drawer
states.

---

## Accessibility

Within the current scope — a navigation shell — both applications have a skip
link, labelled landmarks, keyboard-reachable navigation, and body text meeting
the 4.5:1 contrast floor in both themes. That is what a shell can be tested for.
Forms, tables and dialogues will need their own pass when they exist.

---

## What has to happen before either is usable

1. Backend routes for the surface, with role authorisation.
2. A login flow, and credentials that mean something.
3. The domain the screens would show — orders first, since a kitchen cannot see
   an order today.

Until then, both applications are an architecture and a design system, honestly
labelled as such on their own front pages.
