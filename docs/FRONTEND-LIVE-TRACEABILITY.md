# FRONTEND LIVE TRACEABILITY

Restart Module 01. Commit `b49dcb4`.

## The rule this table enforces

**A feature is not COMPLETE until it is visible and usable in the running
application.**

Backend complete ≠ complete. API complete ≠ complete. A component in the source
tree ≠ complete. Passing tests ≠ complete. COMPLETE requires all of:
**code + API + UI + navigation + live view + test + screenshot.**

Customer Web, Android and iOS are one codebase (`mobile/`), so the three customer
columns are filled from the same routes. "Live" means seen running in this audit.

| ID | Feature | Backend | API | Cust. Web | Android | iOS | Rest. Web | Admin Web | Live route | Screenshot | Test | Status | Missing reason | Next module |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| M01-1 | API foundation, envelope, correlation ids | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | `/api/v1/*` | ✔ | ✔ | **VERIFIED COMPLETE** | — | — |
| M01-2 | System health page | ✔ | ✔ | n/a | n/a | n/a | n/a | ✔ | `/admin/system-health` | ✔ | ✔ | **VERIFIED COMPLETE** | — | — |
| M01-3 | Web design system (`@fotg/ui`) | n/a | n/a | n/a | n/a | n/a | ✔ | ✔ | both shells | ✔ | ✔ | **VERIFIED COMPLETE** | — | — |
| M01-4 | Mobile design system / theme | n/a | n/a | ✔ | ✔ | ✔ | n/a | n/a | all | ✔ | ✔ | **PARTIALLY IMPLEMENTED** | No bundled font — MF-01 | R-01 follow-up |
| M01-5 | Responsive foundation ≥1024 | n/a | n/a | ✖ | n/a | n/a | ✔ | ✔ | `/` | ✔ | ✖ | **MISSING** | Phone layout stretched — MF-02 | R-02 |
| M02-1 | Customer shell + bottom navigation | n/a | n/a | ✔ | ✔ | ✔ | n/a | n/a | `/` | ✔ | ✔ | **IMPLEMENTED BUT NOT LIVE** | Not driven end to end | R-02 |
| M02-2 | Home screen | ✔ | ✔ | ✔ | ✔ | ✔ | n/a | n/a | `/` | ✔ | ✔ | **IMPLEMENTED BUT NOT LIVE** | Signed-in home not photographed | R-02 |
| M03-1 | Phone + OTP sign-in | ✔ | ✔ | ✔ | ✔ | ✔ | n/a | n/a | `/auth/phone` → `/auth/otp` | ✔ | ✔ | **VERIFIED COMPLETE** | — | — |
| M03-2 | SMS delivery | ✔ | ✔ | n/a | n/a | n/a | n/a | n/a | — | — | ✔ | **BLOCKED** | No Twilio credentials / DLT — MF-09 | client |
| M04-1 | Profile | ✔ | ✔ | ✔ | ✔ | ✔ | n/a | n/a | `/profile` | ✔ (guard) | ✔ | **IMPLEMENTED BUT NOT LIVE** | Not driven signed-in | R-04 |
| M04-2 | Saved addresses | ✔ | ✔ | ✔ | ✔ | ✔ | n/a | n/a | `/profile` | ✖ | ✔ | **IMPLEMENTED BUT NOT LIVE** | Not driven | R-04 |
| M05-1 | Trip planner | ✔ | ✔ | ✔ | ✔ | ✔ | n/a | n/a | `/trips/plan` | ✖ | ✔ | **IMPLEMENTED BUT NOT LIVE** | Not driven | R-05 |
| M06-1 | Route calculation | ✔ | ✔ | ✔ | ✔ | ✔ | n/a | n/a | `/trips/:id/route` | ✖ | ✔ | **IMPLEMENTED BUT NOT LIVE** | Not driven | R-06 |
| M06-2 | Map tiles | n/a | n/a | ✖ | ✖ | ✖ | n/a | n/a | — | ✖ | n/a | **BLOCKED** | No Maps API key — MF-08 | client |
| M06-3 | Traffic-aware duration | ✖ | ✖ | n/a | n/a | n/a | n/a | n/a | — | ✖ | ✔ | **BLOCKED** | No routing provider — MF-12 | client |
| M07-1 | Restaurant listing along route | ✔ | ✔ | ✔ | ✔ | ✔ | n/a | n/a | `…/route/restaurants` | ✖ | ✔ | **IMPLEMENTED BUT NOT LIVE** | Not driven | R-07 |
| M08-1 | Search, filters, sort | ✔ | ✔ | ✔ | ✔ | ✔ | n/a | n/a | `…/restaurants` | ✖ | ✔ | **IMPLEMENTED BUT NOT LIVE** | Not driven | R-08 |
| M09-1 | Restaurant details | ✔ | ✔ | ✔ | ✔ | ✔ | n/a | n/a | `…/restaurants/:id` | ✖ | ✔ | **IMPLEMENTED BUT NOT LIVE** | Not driven | R-09 |
| M10-1 | Menu browsing | ✔ | ✔ | ✔ | ✔ | ✔ | n/a | n/a | `…/menu` | ✖ | ✔ | **IMPLEMENTED BUT NOT LIVE** | Not driven | R-10 |
| M11-1 | Item detail, variants, addons, add to cart | ✔ | ✔ | ✔ | ✔ | ✔ | n/a | n/a | `…/menu/items/:id` | ✖ | ✔ | **IMPLEMENTED BUT NOT LIVE** | Not driven | R-11 |
| M12-1 | Cart + revalidation | ✔ | ✔ | ✔ | ✔ | ✔ | n/a | n/a | `/trips/:id/cart` | ✖ | ✔ | **IMPLEMENTED BUT NOT LIVE** | Not driven | R-12 |
| M13-1 | Pickup time | ✔ | ✔ | ✔ | ✔ | ✔ | n/a | n/a | `…/cart/pickup` | ✖ | ✔ | **IMPLEMENTED BUT NOT LIVE** | Not driven | R-13 |
| M14-1 | Checkout + commercial calculation | ✔ | ✔ | ✔ | ✔ | ✔ | n/a | n/a | `…/checkout` | ✖ | ✔ | **IMPLEMENTED BUT NOT LIVE** | Not driven | R-14 |
| M14T-1 | Tenant isolation | ✔ | ✔ | n/a | n/a | n/a | ✖ | ✖ | `/api/v1/restaurant/*` | ✖ | ✔ | **BACKEND ONLY** | No operator UI — MF-07 | R-Ops |
| M15-1 | Razorpay payment | ✔ | ✔ | ✔ | ✔ | ✔ | n/a | n/a | `…/payment` | ✖ | ✔ | **BLOCKED** | No credentials — MF-10 | client |
| M16-1 | Order confirmation, number, pickup code | ✔ | ✔ | ✔ | ✔ | ✔ | n/a | n/a | `/orders/:id/confirmation` | ✖ | ✔ | **IMPLEMENTED BUT NOT LIVE** | Not driven | R-16 |
| M16-2 | Pickup **QR** | ✖ | ✖ | ✖ | ✖ | ✖ | n/a | n/a | — | ✖ | ✖ | **MISSING** | A pickup *code* exists; no QR is generated anywhere | R-16 |
| M17-1 | Order tracking + timeline | ✔ | ✔ | ✔ | ✔ | ✔ | n/a | n/a | `/orders/:id/track` | ✖ | ✔ | **PARTIALLY IMPLEMENTED** | Nothing can advance state — MF-11 | R-17 |
| M18-1 | ETA engine | ✖ | ✖ | ✖ | ✖ | ✖ | ✖ | ✖ | — | ✖ | ✖ | **NOT YET SCHEDULED** | Never specified, never started — MF-03 | R-18 |
| OPS-1 | Staff sign-in | ✖ | ✖ | n/a | n/a | n/a | ✖ | ✖ | — | ✖ | ✖ | **MISSING** | MF-04 | R-Ops |
| OPS-2 | Restaurant dashboard, 11 areas | ✖ | partial | n/a | n/a | n/a | ✖ | n/a | `/restaurant/*` | ✔ (placeholders) | ✖ | **MISSING** | 0 of 11 implemented — MF-05 | R-Ops |
| OPS-3 | Admin panel, 13 remaining areas | ✖ | partial | n/a | n/a | n/a | n/a | ✖ | `/admin/*` | ✔ (placeholders) | ✖ | **MISSING** | 1 of 14 implemented — MF-06 | R-Ops |

## Newly discovered in this audit

**M16-2 — the pickup QR does not exist.** The brief lists "Pickup QR generation"
under Module 16, and Module 16 was reported complete. A pickup *credential* is
generated, hashed and served by `/api/v1/customer/orders/{order}/pickup-credential`
— but nothing renders it as a QR code, on any platform, and no QR library is a
dependency of the mobile app. This was not previously recorded as missing.
